package model

import play.api.libs.functional.syntax._
import play.api.libs.json._

object DataManipulation {
  object Operation {
    implicit val reads: Reads[Operation] = Reads {
      case JsString("+") => JsSuccess(Add)
      case JsString("-") => JsSuccess(Remove)
      case _ => JsError("Invalid operation")
    }
  }
  sealed abstract class Operation(val code: String)
  case object Add extends Operation("+")
  case object Remove extends Operation("-")

  implicit val reads: Reads[DataManipulation] = (
    (JsPath \ "type").read[String] and
    (JsPath \ "op").read[Operation] and
    (JsPath \ "key").read[String]
  )(KeyOnlyDataManipulation.apply _)

  implicit val writes: Writes[DataManipulation] = Writes {
    case KeyOnlyDataManipulation(typ: String, operation: Operation, key: String) =>
      Json.obj(
        "type" -> typ,
        "op" -> (
          operation match {
            case Add => "+"
            case Remove => "-"
          }
        ),
        "key" -> key
      )
  }
}
sealed abstract class DataManipulation
case class KeyOnlyDataManipulation (
  `type`: String,
  operation: DataManipulation.Operation,
  key: String
) extends DataManipulation
case class KeyValueDataManipulation[T] (
  `type`: String,
  operation: DataManipulation.Operation,
  key: String,
  value: T
) extends DataManipulation
