name := "spark-weave-shuffle"

import sbtprotoc.ProtocPlugin.autoImport._

version := "0.1.0"

scalaVersion := "2.12.15"

organization := "org.apache.spark.shuffle.weave"

libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.2.2" % "provided",
  "org.apache.spark" %% "spark-sql"  % "3.2.2" % "provided",
  "org.scalatest"    %% "scalatest"  % "3.2.9" % "test",
  "org.apache.commons" % "commons-math3" % "3.6.1"
)

libraryDependencies += "com.thesamet.scalapb" %% "scalapb-runtime" % scalapb.compiler.Version.scalapbVersion % "protobuf"

scalacOptions ++= Seq(
  "-deprecation",
  "-feature",
  "-unchecked",
  "-encoding", "utf8"
)

javacOptions ++= Seq(
  "-source", "1.8",
  "-target", "1.8"
)

ThisBuild / versionScheme := Some("early-semver")
 
Compile / PB.targets := Seq(
  scalapb.gen() -> (Compile / sourceManaged).value
)
