package model.slack

import play.api.libs.functional.syntax._
import play.api.libs.json.{JsPath, Reads}

object Message {
  // Slack API JSON formats
  implicit val reads: Reads[Message] = (
    (JsPath \ "type").read[String] and
    (JsPath \ "bot_id").readNullable[String] and
    (JsPath \ "text").read[String] and
    (JsPath \ "ts").read[String]
  )(Message.apply _)
}
case class Message(
  `type`: String,
  botId: Option[String],
  text: String,
  ts: String
)
