package controllers

import actors.{RepositoryActor, WebSocketActor}
import akka.actor.{ActorRef, ActorSystem}
import akka.stream.Materializer
import javax.inject._
import play.api._
import play.api.libs.json.JsValue
import play.api.libs.streams.ActorFlow
import play.api.libs.ws.WSClient
import play.api.mvc._

/**
 * This controller creates an `Action` to handle HTTP requests to the
 * application's home page.
 */
@Singleton
class MainController @Inject()
    (ws: WSClient, cc: ControllerComponents, cfg: Configuration)
    (implicit system: ActorSystem, mat: Materializer)
    extends AbstractController(cc) {
  private val repositoryActor: ActorRef =
    system.actorOf(RepositoryActor.props(ws, cfg), "repository")

  def index(): Action[AnyContent] = Action { implicit request: Request[AnyContent] =>
    Ok(views.html.index())
  }

  def admin(): Action[AnyContent] = Action { implicit request: Request[AnyContent] =>
    Ok(views.html.admin())
  }

  def store(): WebSocket = WebSocket.accept[JsValue,JsValue] { _: RequestHeader =>
    ActorFlow.actorRef { webSocketClient: ActorRef =>
      WebSocketActor.props(webSocketClient, repositoryActor)
    }
  }
}
