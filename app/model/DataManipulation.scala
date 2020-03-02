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
  case object Reset extends Operation("reset")

  // TODO this whole JSON reads/writes thing can probably be better
  private val topicKeyValueDataManipulationReads: Reads[DataManipulation] =
    (
      (JsPath \ "type").read[String] and
      (JsPath \ "op").read[Operation] and
      (JsPath \ "key").read[String] and
      (JsPath \ "value").read[Topic]
    )(KeyValueDataManipulation.apply[Topic] _)

  private val stringKeyValueDataManipulationReads: Reads[DataManipulation] =
    (
      (JsPath \ "type").read[String] and
      (JsPath \ "op").read[Operation] and
      (JsPath \ "key").read[String] and
      (JsPath \ "value").read[String]
    )(KeyValueDataManipulation.apply[String] _)

  private val keyOnlyDataManipulationReads: Reads[DataManipulation] =
    (
      (JsPath \ "type").read[String] and
      (JsPath \ "op").read[Operation] and
      (JsPath \ "key").read[String]
    )(KeyOnlyDataManipulation.apply _)
  private val dataManipulationMetadataReads: Reads[DataManipulation] =
    (__ \ "op").read[Operation].map(DataManipulationMetadata.apply)

  implicit val reads: Reads[DataManipulation] =
    topicKeyValueDataManipulationReads orElse
    stringKeyValueDataManipulationReads orElse
    keyOnlyDataManipulationReads
  implicit val seqReads: Reads[Seq[DataManipulation]] = Reads.seq(DataManipulation.reads)

  implicit val writes: Writes[DataManipulation] = Writes {
    case KeyOnlyDataManipulation(typ: String, operation: Operation, key: String) =>
      Json.obj(
        "type" -> typ,
        "op" -> operation.code,
        "key" -> key
      )

    case KeyValueDataManipulation(typ: String, operation: Operation, key: String, value: String) =>
      Json.obj(
        "type" -> typ,
        "op" -> operation.code,
        "key" -> key,
        "value" -> value
      )

    case KeyValueDataManipulation(typ: String, operation: Operation, key: String, value: Topic) =>
      Json.obj(
        "type" -> typ,
        "op" -> operation.code,
        "key" -> key,
        "value" -> Json.toJson(value)
      )

    case DataManipulationMetadata(operation: Operation) =>
      Json.obj(
        "op" -> operation.code
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
case class DataManipulationMetadata(
  operation: DataManipulation.Operation
) extends DataManipulation