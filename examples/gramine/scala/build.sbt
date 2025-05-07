ThisBuild / scalaVersion := "2.13.14"
ThisBuild / version := "0.1"
ThisBuild / organization := "com.mahdi"

lazy val root = (project in file("."))
  .settings(
    name := "scala-fatjar-tests",
    assembly / assemblyJarName := "fatjar-assembly.jar",
    mainClass := Some("HelloWorld") // default, overridden per build
  )
