ThisBuild / scalaVersion := "2.12.18"

lazy val root = (project in file("."))
  .settings(
    name := "SimpleApp",
    version := "0.1",
    assembly / assemblyMergeStrategy := {
      case PathList("META-INF", _*) => MergeStrategy.discard
      case _ => MergeStrategy.first
    },
    libraryDependencies ++= Seq(
      "org.apache.spark" %% "spark-core" % "3.3.2" % "provided",
      "org.apache.spark" %% "spark-sql" % "3.3.2" % "provided"
    )
  )

