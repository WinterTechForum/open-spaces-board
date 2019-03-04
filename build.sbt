name := "open-spaces-board"
organization := "com.wintertechforum"

version := "1.0-SNAPSHOT"

lazy val root = (project in file(".")).enablePlugins(PlayScala)

scalaVersion := "2.12.8"

libraryDependencies += guice
libraryDependencies += ws
libraryDependencies += "org.scalatestplus.play" %% "scalatestplus-play" % "3.1.2" % Test

val elmMakeAdmin = taskKey[Seq[File]]("elm-make-admin")

elmMakeAdmin := {
  import scala.sys.process._
  import com.typesafe.sbt.web.LineBasedProblem
  import play.sbt.PlayExceptions.CompilationException

  val outputPath: String = "target/elm/admin.js"
  val debugFlag: String =
    if (sys.props.getOrElse("elm.debug", "false").toLowerCase != "true") ""
    else "--debug"
  var outErrLines: List[String] = Nil
  var srcFilePath: Option[String] = None
  var lineNum: Option[String] = None
  var offset: Option[String] = None
  Seq(
    "bash", "-c",
    "elm-make " +
    (file("app/assets/javascripts/Admin") ** "*.elm").get.mkString(" ") +
    s" --output ${outputPath} " +
    s"--yes ${debugFlag} --warn"
  ).!(
    new ProcessLogger {
      override def out(s: => String): Unit = {
        streams.value.log.info(s)
        outErrLines = s :: outErrLines
      }

      override def err(s: => String): Unit = {
        streams.value.log.warn(s)
        val SrcFilePathExtractor = """-- [A-Z ]+ -+ (app/assets/javascripts/.+\.elm)""".r
        val LineNumExtractor = """([0-9]+)\|.*""".r
        val PosExtractor = """ *\^+ *""".r
        s match {
          case SrcFilePathExtractor(path: String) =>
            srcFilePath = srcFilePath orElse Some(path)
          case LineNumExtractor(num: String) =>
            lineNum = lineNum orElse Some(num)
          case PosExtractor() =>
            offset = offset orElse Some(s)
          case _ =>
        }
        outErrLines = s :: outErrLines
      }

      override def buffer[T](f: => T): T = f
    }
  ) match {
    case 0 =>
      streams.value.log.success("elm-make (for Admin) completed.")
      Seq(file(outputPath))

    case 127 =>
      streams.value.log.warn("elm-make not found in PATH. Skipping Elm build.")
      Nil

    case _ =>
      throw CompilationException(
        new LineBasedProblem(
          message = outErrLines.reverse.mkString("\n"),
          severity = null,
          lineNumber = lineNum.map(_.toInt).getOrElse(0),
          characterOffset = offset.map(_.indexOf('^') - 2 - lineNum.map(_.length).getOrElse(0)).getOrElse(0),
          lineContent = "",
          source = file(srcFilePath.getOrElse(""))
        )
      )
  }
}

resourceGenerators in Assets += elmMakeAdmin.taskValue

val elmMakeBoard = taskKey[Seq[File]]("elm-make-board")

elmMakeBoard := {
  import scala.sys.process._
  import com.typesafe.sbt.web.LineBasedProblem
  import play.sbt.PlayExceptions.CompilationException

  val outputPath: String = "target/elm/board.js"
  val debugFlag: String =
    if (sys.props.getOrElse("elm.debug", "false").toLowerCase != "true") ""
    else "--debug"
  var outErrLines: List[String] = Nil
  var srcFilePath: Option[String] = None
  var lineNum: Option[String] = None
  var offset: Option[String] = None
  Seq(
    "bash", "-c",
    "elm-make " +
    (file("app/assets/javascripts/Board") ** "*.elm").get.mkString(" ") +
    s" --output ${outputPath} " +
    s"--yes ${debugFlag} --warn"
  ).!(
    new ProcessLogger {
      override def out(s: => String): Unit = {
        streams.value.log.info(s)
        outErrLines = s :: outErrLines
      }

      override def err(s: => String): Unit = {
        streams.value.log.warn(s)
        val SrcFilePathExtractor = """-- [A-Z ]+ -+ (app/assets/javascripts/.+\.elm)""".r
        val LineNumExtractor = """([0-9]+)\|.*""".r
        val PosExtractor = """ *\^+ *""".r
        s match {
          case SrcFilePathExtractor(path: String) =>
            srcFilePath = srcFilePath orElse Some(path)
          case LineNumExtractor(num: String) =>
            lineNum = lineNum orElse Some(num)
          case PosExtractor() =>
            offset = offset orElse Some(s)
          case _ =>
        }
        outErrLines = s :: outErrLines
      }

      override def buffer[T](f: => T): T = f
    }
  ) match {
    case 0 =>
      streams.value.log.success("elm-make (for Board) completed.")
      Seq(file(outputPath))

    case 127 =>
      streams.value.log.warn("elm-make not found in PATH. Skipping Elm build.")
      Nil

    case _ =>
      throw CompilationException(
        new LineBasedProblem(
          message = outErrLines.reverse.mkString("\n"),
          severity = null,
          lineNumber = lineNum.map(_.toInt).getOrElse(0),
          characterOffset = offset.map(_.indexOf('^') - 2 - lineNum.map(_.length).getOrElse(0)).getOrElse(0),
          lineContent = "",
          source = file(srcFilePath.getOrElse(""))
        )
      )
  }
}

resourceGenerators in Assets += elmMakeBoard.taskValue
