ThisBuild / scalaVersion := "2.13.12"

enablePlugins(AssemblyPlugin)

lazy val root = (project in file("."))
  .settings(
    name := "fork-tests",
    version := "0.1",
    Compile / scalaSource := baseDirectory.value / "src" / "fork" / "scala",
    assembly / assemblyJarName := "fork-tests-assembly.jar",
    assembly / mainClass := Some("ForkTestSuite"),
    libraryDependencies ++= Seq()
  )

