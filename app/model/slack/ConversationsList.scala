package model.slack

import play.api.libs.functional.syntax._
import play.api.libs.json.{JsPath, Reads}

object ConversationsList {
  // Slack API JSON formats
  implicit val reads: Reads[ConversationsList] = (
    (JsPath \ "ok").read[Boolean] and
    (JsPath \ "channels").readNullable[Seq[Channel]].map(_.getOrElse(Nil))
  )(ConversationsList.apply _)
}
case class ConversationsList(
  ok: Boolean,
  channels: Seq[Channel]
)
