package model.slack

import play.api.libs.functional.syntax._
import play.api.libs.json.{JsPath, Reads}

object Channel {
  // Slack API JSON formats
  implicit val reads: Reads[Channel] = (
    (JsPath \ "id").read[String] and
    (JsPath \ "name").read[String]
  )(Channel.apply _)
  implicit val seqReads: Reads[Seq[Channel]] = Reads.seq(Channel.reads)
}
case class Channel(
  id: String,
  name: String
)
