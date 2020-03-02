package model.slack

import play.api.libs.functional.syntax._
import play.api.libs.json.{JsPath, Reads}

object ConversationsHistory {
  // Slack API JSON formats
  implicit val reads: Reads[ConversationsHistory] = (
    (JsPath \ "ok").read[Boolean] and
    (JsPath \ "messages").readNullable[Seq[Message]](Reads.seq(Message.reads)).
      map(_.getOrElse(Nil))
  )(ConversationsHistory.apply _)
}
case class ConversationsHistory(
  ok: Boolean,
  messages: Seq[Message]
)
