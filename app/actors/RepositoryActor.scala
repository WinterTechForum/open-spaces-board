package actors

import java.net.URLEncoder

import akka.actor.{Actor, ActorLogging, ActorRef, Props, Terminated}
import akka.pattern.pipe
import model._
import model.slack.{ChannelHistory, Message}
import play.api.Configuration
import play.api.libs.json.Json
import play.api.libs.ws.{WSClient, WSResponse}

import scala.util.{Failure, Success, Try}

object RepositoryActor {
  // Incoming messages
  case class ListenerRegistration(listener: ActorRef)
  case class UserUpdateRequest(dataManipulations: Seq[DataManipulation])

  // Outgoing messages
  case class StorageUpdateEvent(dataManipulations: Seq[DataManipulation])

  def props(ws: WSClient, cfg: Configuration): Props =
    Props(new RepositoryActor(ws, cfg))

  private case class Board(
    rooms: Set[String] = Set(),
    timeSlots: Set[String] = Set(),
    topics: Map[(String,String),Topic] = Map()
  )
}
private class RepositoryActor(ws: WSClient, cfg: Configuration) extends Actor with ActorLogging {
  import RepositoryActor._
  import model.slack.ChannelHistory.reads
  import context.dispatcher

  private val slackBaseUrl: String = cfg.get[String]("open-spaces-board.storage.slack.api.base-url")
  private val slackToken: String = cfg.get[Seq[String]]("open-spaces-board.storage.slack.api.token").mkString
  private val slackChannel: String = cfg.get[String]("open-spaces-board.storage.slack.transaction-log.channel")
//  private val slackBotId: String = cfg.get[String]("open-spaces-board.storage.slack.transaction-log.botId")
  ws.url(s"${slackBaseUrl}/conversations.history?token=${slackToken}&channel=${slackChannel}&limit=1000").
    execute().
    pipeTo(self)
//  ws.url(s"${slackBaseUrl}/conversations.list?token=${slackToken}&types=private_channel").
//    execute().
//    foreach { resp: WSResponse => println(resp.json) }

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
      topics = enrichedBoard.topics ++ topicIdsByTimeSlotRoom.mapValues(topicsById)
    )
  }

  private val initializing: Receive = {
    case resp: WSResponse =>
      val board: Board =
        applyDataManipulations(
          resp.json.as[ChannelHistory].messages.
            collect {
              case Message("message", _, text: String, _) =>
                Try(Json.parse(text).as[Seq[DataManipulation]])
            }.
            flatMap {
              case Success(dataManipulations: Seq[DataManipulation]) => dataManipulations
              case Failure(_) => Seq()
            },
          Board()
        )
      context.become(
        running(board, Set())
      )
      println(board)
  }

  private def running(board: Board, listeners: Set[ActorRef]): Receive = {
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
      println(urlEncDataManJson)
      ws.url(s"${slackBaseUrl}/chat.postMessage?token=${slackToken}&channel=${slackChannel}&text=${urlEncDataManJson}").
        execute().
        filter { _.status == 200 }.
        map { _: WSResponse =>
          StorageUpdateEvent(idEnrichedDataManipulation)
        }.
        pipeTo(self)

    case event @ StorageUpdateEvent(dataManipulations: Seq[DataManipulation]) =>
      val newBoard: Board = applyDataManipulations(dataManipulations, board)
      if (board != newBoard) {
        for (listener: ActorRef <- listeners) {
          listener ! event
        }
        context.become(
          running(newBoard, listeners)
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
        running(board, listeners + listener)
      )

    case Terminated(listener: ActorRef) if listeners.contains(listener) =>
      context.become(
        running(board, listeners - listener)
      )
  }

  override val receive: Receive = initializing
}
