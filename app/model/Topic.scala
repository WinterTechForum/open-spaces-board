package model

import play.api.libs.functional.syntax._
import play.api.libs.json._

object Topic {
  implicit val format: Format[Topic] = (
    (JsPath \ "text").format[String] and
    (JsPath \ "convener").format[String]
  )(Topic.apply _, unlift(Topic.unapply _))
}
case class Topic(
  text: String,
  convener: String
)