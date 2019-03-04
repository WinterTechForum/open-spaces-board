package actors

import java.net.URLEncoder

import akka.actor.{Actor, ActorLogging, ActorRef, Props, Terminated}
import akka.pattern.pipe
import model.{DataManipulation, KeyOnlyDataManipulation}
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
}
private class RepositoryActor(ws: WSClient, cfg: Configuration) extends Actor with ActorLogging {
  import RepositoryActor._
  import model.slack.ChannelHistory.reads
  import context.dispatcher

  private val slackBaseUrl: String = cfg.get[String]("open-spaces-board.storage.slack.api.base-url")
  private val slackToken: String = cfg.get[Seq[String]]("open-spaces-board.storage.slack.api.token").mkString
  private val slackChannel: String = cfg.get[String]("open-spaces-board.storage.slack.transaction-log.channel")
  private val slackBotId: String = cfg.get[String]("open-spaces-board.storage.slack.transaction-log.botId")
  ws.url(s"${slackBaseUrl}/conversations.history?token=${slackToken}&channel=${slackChannel}&limit=1000").
    execute().
    pipeTo(self)
//  ws.url(s"${slackBaseUrl}/conversations.list?token=${slackToken}&types=private_channel").
//    execute().
//    foreach { resp: WSResponse => println(resp.json) }

  private def applyDataManipulations(
      dataManipulations: Seq[DataManipulation], rooms: Set[String], timeSlots: Set[String]):
      (Set[String], Set[String]) =
    dataManipulations.foldRight(rooms, timeSlots) {
      case (dataManipulation: DataManipulation, (rooms: Set[String], timeSlots: Set[String])) =>
        dataManipulation match {
          case KeyOnlyDataManipulation("room", DataManipulation.Add, room) =>
            (rooms + room, timeSlots)

          case KeyOnlyDataManipulation("room", DataManipulation.Remove, room) =>
            (rooms - room, timeSlots)

          case KeyOnlyDataManipulation("timeSlot", DataManipulation.Add, timeSlot) =>
            (rooms, timeSlots + timeSlot)

          case KeyOnlyDataManipulation("timeSlot", DataManipulation.Remove, timeSlot) =>
            (rooms, timeSlots - timeSlot)

          case _ => (rooms, timeSlots)
        }
    }

  private val initializing: Receive = {
    case resp: WSResponse =>
      val (rooms: Set[String], timeSlots: Set[String]) =
        applyDataManipulations(
          resp.json.as[ChannelHistory].messages.
            collect {
              case Message("message", Some(`slackBotId`), text: String, _) =>
                Try(Json.parse(text).as[Seq[DataManipulation]])
            }.
            flatMap {
              case Success(dataManipulations: Seq[DataManipulation]) => dataManipulations
              case Failure(_) => Seq()
            },
          Set[String](),
          Set[String]()
        )
      context.become(
        running(rooms, timeSlots, Set())
      )
  }

  private def running(rooms: Set[String], timeSlots: Set[String], listeners: Set[ActorRef]): Receive = {
    case UserUpdateRequest(dataManipulations: Seq[DataManipulation]) =>
      val urlEncDataManJson: String = URLEncoder.encode(
        Json.stringify(Json.toJson(dataManipulations)),
        "UTF-8"
      )
      ws.url(s"${slackBaseUrl}/chat.postMessage?token=${slackToken}&channel=${slackChannel}&text=${urlEncDataManJson}").
        execute().
        filter { _.status == 200 }.
        map { _: WSResponse =>
          StorageUpdateEvent(dataManipulations)
        }.
        pipeTo(self)

    case event @ StorageUpdateEvent(dataManipulations: Seq[DataManipulation]) =>
      val (newRooms: Set[String], newTimeSlots: Set[String]) =
        applyDataManipulations(dataManipulations, rooms, timeSlots)
      if (rooms != newRooms || timeSlots != newTimeSlots) {
        for (listener: ActorRef <- listeners) {
          listener ! event
        }
        context.become(
          running(newRooms, newTimeSlots, listeners)
        )
      }

    case ListenerRegistration(listener: ActorRef) =>
      listener ! StorageUpdateEvent(
        rooms.toSeq.map { room =>
          KeyOnlyDataManipulation("room", DataManipulation.Add, room)
        }
        ++
        timeSlots.toSeq.map { timeSlot =>
          KeyOnlyDataManipulation("timeSlot", DataManipulation.Add, timeSlot)
        }
      )
      context.watch(listener)
      context.become(
        running(rooms, timeSlots, listeners + listener)
      )

    case Terminated(listener: ActorRef) if listeners.contains(listener) =>
      context.become(
        running(rooms, timeSlots, listeners - listener)
      )
  }

  override val receive: Receive = initializing
}
