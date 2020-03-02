package actors

import java.net.URLEncoder

import akka.actor.{Actor, ActorLogging, ActorRef, Props, Status, Terminated}
import akka.pattern.{BackoffOpts, BackoffSupervisor, pipe}
import model._
import model.slack.{Channel, ConversationsHistory, ConversationsList, Message}
import play.api.Configuration
import play.api.libs.json.Json
import play.api.libs.ws.{WSClient, WSResponse}

import scala.concurrent.Future
import scala.concurrent.duration._
import scala.util.{Failure, Success, Try}

object RepositoryActor {
  // Incoming messages
  case class ListenerRegistration(listener: ActorRef)
  case class UserUpdateRequest(dataManipulations: Seq[DataManipulation])

  // Outgoing messages
  case class StorageUpdateEvent(dataManipulations: Seq[DataManipulation])

  // Internal messages
  private case class Initialized(channelId: String, dataManipulations: Seq[DataManipulation])

  def props(ws: WSClient, cfg: Configuration): Props =
    // BackoffSupervisor pattern, as described here -
    // https://doc.akka.io/docs/akka/2.5/general/supervision.html#delayed-restarts-with-the-backoffsupervisor-pattern
    // So that we don't get throttled by Slack
    BackoffSupervisor.props(
      BackoffOpts.onStop(
        Props(new RepositoryActor(ws, cfg)),
        childName = "supervised",
        minBackoff = 3.seconds,
        maxBackoff = 30.seconds,
        randomFactor = 0.2 // adds 20% "noise" to vary the intervals slightly
      )
    )

  private case class Board(
    rooms: Set[String] = Set(),
    timeSlots: Set[String] = Set(),
    topics: Map[(String,String),Topic] = Map()
  )

  private case class ChannelNotFoundException(name: String) extends IllegalArgumentException
}
private class RepositoryActor(ws: WSClient, cfg: Configuration) extends Actor with ActorLogging {
  import RepositoryActor._
  import context.dispatcher
  import model.slack.ConversationsHistory.reads

  private val slackBaseUrl: String = cfg.get[String]("open-spaces-board.storage.slack.api.base-url")
  private val slackToken: String = cfg.get[Seq[String]]("open-spaces-board.storage.slack.api.token").mkString

  private def slackApiGet(url: String): Future[WSResponse] =
    ws.url(url).execute().
    flatMap {
      case okResp: WSResponse if okResp.status == 200 && (okResp.json \ "ok").as[Boolean] =>
        Future.successful(okResp)

      case badHttpResp: WSResponse if badHttpResp.status != 200 =>
        Future.failed(
          new IllegalStateException(s"Bad HTTP response from server: ${badHttpResp.status}")
        )

      case badApiResp: WSResponse =>
        Future.failed(
          new IllegalStateException(s"Bad Slack API response:\n${badApiResp.json}")
        )
    }

  private def applyDataManipulations(
      dataManipulations: Seq[DataManipulation], board: Board): Board = {
    val (enrichedBoard: Board, topicsById: Map[String,Topic], topicIdsByTimeSlotRoom: Map[(String,String),String]) =
      dataManipulations.foldRight((board, Map[String,Topic](), Map[(String,String),String]())) {
        case (
              dataManipulation: DataManipulation,
              (
                board @ Board(rooms: Set[String], timeSlots: Set[String], _),
                topicsById: Map[String,Topic],
                topicIdsByRoomTimeSlot: Map[(String,String),String]
              )
            ) =>
          dataManipulation match {
            case KeyOnlyDataManipulation("room", DataManipulation.Add, room: String) =>
              (board.copy(rooms = rooms + room), topicsById, topicIdsByRoomTimeSlot)

            case KeyOnlyDataManipulation("room", DataManipulation.Remove, room: String) =>
              (board.copy(rooms = rooms - room), topicsById, topicIdsByRoomTimeSlot)

            case KeyOnlyDataManipulation("timeSlot", DataManipulation.Add, timeSlot: String) =>
              (board.copy(timeSlots = timeSlots + timeSlot), topicsById, topicIdsByRoomTimeSlot)

            case KeyOnlyDataManipulation("timeSlot", DataManipulation.Remove, timeSlot: String) =>
              (board.copy(timeSlots = timeSlots - timeSlot), topicsById, topicIdsByRoomTimeSlot)

            case KeyValueDataManipulation("topic", DataManipulation.Add, id: String, topic: Topic) =>
              (board, topicsById + (id -> topic), topicIdsByRoomTimeSlot)

            case KeyValueDataManipulation("topic", DataManipulation.Remove, id: String, _) =>
              (board, topicsById - id, topicIdsByRoomTimeSlot)

            case KeyValueDataManipulation("pin", DataManipulation.Add, timeSlotRoom: String, topicId: String) =>
              val Array(timeSlot: String, room: String) = timeSlotRoom.split("\\|", 2)
              (board, topicsById, topicIdsByRoomTimeSlot + ((timeSlot, room) -> topicId))

            case KeyValueDataManipulation("pin", DataManipulation.Remove, timeSlotRoom: String, _) =>
              val Array(timeSlot: String, room: String) = timeSlotRoom.split("\\|", 2)
              (board, topicsById, topicIdsByRoomTimeSlot - ((timeSlot, room)))

            case _ => (board, topicsById, topicIdsByRoomTimeSlot)
          }
      }

    enrichedBoard.copy(
      topics = enrichedBoard.topics ++ topicIdsByTimeSlotRoom.view.mapValues(topicsById)
    )
  }

  (
    for {
      channelsResponse: WSResponse <-
        slackApiGet(
          s"${slackBaseUrl}/conversations.list?token=${slackToken}&exclude_archived=true"
        )
      channelName: String = cfg.get[String]("open-spaces-board.storage.slack.transaction-log.channel")
      channelId: String <-
        channelsResponse.json.as[ConversationsList].channels.
        collectFirst {
          case ch: Channel if ch.name == channelName => ch.id
        } match {
          case Some(channelId: String) => Future.successful(channelId)
          case None => Future.failed(ChannelNotFoundException(channelName))
        }
      _: WSResponse <-
        slackApiGet(
          s"${slackBaseUrl}/conversations.join?token=${slackToken}&channel=${channelId}"
        )
      botId: String <-
        slackApiGet(
          s"${slackBaseUrl}/auth.test?token=${slackToken}"
        ).
        map { resp: WSResponse => (resp.json \ "bot_id").as[String] }
      dataManipulations: Seq[DataManipulation] <-
        slackApiGet(
          s"${slackBaseUrl}/conversations.history?token=${slackToken}&channel=${channelId}&limit=1000"
        ).
        map { resp: WSResponse =>
          resp.json.as[ConversationsHistory].messages.
            collect {
              case Message("message", Some(`botId`), text: String, _) =>
                Try(Json.parse(text).as[Seq[DataManipulation]])
            }.
            flatMap {
              case Success(dataManipulations: Seq[DataManipulation]) => dataManipulations
              case Failure(_) => Seq()
            }
        }
    } yield Initialized(channelId, dataManipulations)
  ).pipeTo(self)

  private val initializing: Receive = {
    case Initialized(channelId, dataManipulations) =>
      val board: Board = applyDataManipulations(dataManipulations, Board())
      context.become(
        running(board, Set(), channelId)
      )

    case Status.Failure(ChannelNotFoundException(name: String)) =>
      log.error(s"""Channel "${name}" not found, please create it, or update "open-spaces-board.storage.slack.transaction-log.channel" in application.conf.""")
      context.stop(self)
      context.system.terminate().foreach { _ =>
        System.exit(1)
      }

    case Status.Failure(t: Throwable) => throw t // Crash
  }

  private def running(board: Board, listeners: Set[ActorRef], channelId: String): Receive = {
    case UserUpdateRequest(dataManipulations: Seq[DataManipulation]) =>
      val newKey: Long = System.currentTimeMillis()
      val idEnrichedDataManipulation: Seq[DataManipulation] = dataManipulations.
        map {
          case dataMan @ KeyValueDataManipulation("topic", DataManipulation.Add, "new", _) =>
            dataMan.copy(key = newKey.toString)
          case dataMan @ KeyValueDataManipulation("pin", DataManipulation.Add, _, "new") =>
            dataMan.copy(value = newKey.toString)
          case dataMan: DataManipulation =>
            dataMan
        }
      val urlEncDataManJson: String = URLEncoder.encode(
        Json.stringify(Json.toJson(idEnrichedDataManipulation)),
        "UTF-8"
      )
      slackApiGet(s"${slackBaseUrl}/chat.postMessage?token=${slackToken}&channel=${channelId}&text=${urlEncDataManJson}").
        map { _: WSResponse =>
          StorageUpdateEvent(idEnrichedDataManipulation)
        }.
        pipeTo(self)
        // TODO instead of piping this to self, consider using the RTM API to support multi-node synchronizing
        // https://api.slack.com/rtm

    case event @ StorageUpdateEvent(dataManipulations: Seq[DataManipulation]) =>
      val newBoard: Board = applyDataManipulations(dataManipulations, board)
      if (board != newBoard) {
        for (listener: ActorRef <- listeners) {
          listener ! event
        }
        context.become(
          running(newBoard, listeners, channelId)
        )
      }

    case ListenerRegistration(listener: ActorRef) =>
      listener ! StorageUpdateEvent(
        board.rooms.toSeq.map { room =>
          KeyOnlyDataManipulation("room", DataManipulation.Add, room)
        }
        ++
        board.timeSlots.toSeq.map { timeSlot =>
          KeyOnlyDataManipulation("timeSlot", DataManipulation.Add, timeSlot)
        }
        ++
        board.timeSlots.toSeq.map { timeSlot =>
          KeyOnlyDataManipulation("timeSlot", DataManipulation.Add, timeSlot)
        }
        ++
        board.topics.toSeq.zipWithIndex.flatMap {
          case (((timeSlot: String, room: String), topic: Topic), topicId: Int) =>
            Seq(
              KeyValueDataManipulation("topic", DataManipulation.Add, topicId.toString, topic),
              KeyValueDataManipulation("pin", DataManipulation.Add, s"${timeSlot}|${room}", topicId.toString)
            )
        }
      )
      context.watch(listener)
      context.become(
        running(board, listeners + listener, channelId)
      )

    case Terminated(listener: ActorRef) if listeners.contains(listener) =>
      context.become(
        running(board, listeners - listener, channelId)
      )

    case Status.Failure(t: Throwable) => throw t // Crash
  }

  override val receive: Receive = initializing
}
