package actors

import akka.actor.{Actor, ActorLogging, ActorRef, Props}
import model.DataManipulation
import play.api.libs.json.{JsValue, Json}

import scala.util.{Failure, Success, Try}

object WebSocketActor {
  def props(webSocketClient: ActorRef, repository: ActorRef): Props =
    Props(new WebSocketActor(webSocketClient, repository))
}
class WebSocketActor(webSocketClient: ActorRef, repository: ActorRef) extends Actor with ActorLogging {
  repository ! RepositoryActor.ListenerRegistration(self)

  override def receive: Receive = {
    case RepositoryActor.StorageUpdateEvent(dataManipulations: Seq[DataManipulation]) =>
      webSocketClient ! Json.toJson(dataManipulations)

    case json: JsValue =>
      Try(json.as[Seq[DataManipulation]]) match {
        case Success(dataManipulations: Seq[DataManipulation]) =>
          repository ! RepositoryActor.UserUpdateRequest(dataManipulations)

        case Failure(t: Throwable) =>
          log.error(t, "Unexpected JSON")
      }
  }
}
