package model.slack

import play.api.libs.functional.syntax._
import play.api.libs.json.{JsPath, Reads}

object ChannelHistory {
  // Slack API JSON formats
  implicit val reads: Reads[ChannelHistory] = (
    (JsPath \ "ok").read[Boolean] and
    (JsPath \ "messages").read[Seq[Message]] and
    (JsPath \ "has_more").read[Boolean]
  )(ChannelHistory.apply _)
}
case class ChannelHistory(
  ok: Boolean,
  messages: Seq[Message],
  hasMore: Boolean
)
