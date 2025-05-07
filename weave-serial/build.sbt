enablePlugins(AssemblyPlugin)

name := "spark-weave-shuffle"
version := "0.1.0"
scalaVersion := "2.12.17"
organization := "org.apache.spark.shuffle.weave"

libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.2.2" excludeAll ExclusionRule("io.netty"),
  "org.apache.spark" %% "spark-sql"  % "3.2.2" excludeAll ExclusionRule("io.netty"),
  "org.scalatest"    %% "scalatest"  % "3.2.18" % Test,
  "io.netty"          % "netty-all"  % "4.1.63.Final"
)

dependencyOverrides ++= Seq(
  "io.netty" % "netty-common"    % "4.1.63.Final",
  "io.netty" % "netty-buffer"    % "4.1.63.Final",
  "io.netty" % "netty-transport" % "4.1.63.Final",
  "io.netty" % "netty-codec"     % "4.1.63.Final",
  "io.netty" % "netty-handler"   % "4.1.63.Final"
)

ThisBuild / versionScheme := Some("early-semver")
ThisBuild / resolvers += Resolver.sonatypeRepo("releases")

assembly / assemblyMergeStrategy := {
  case PathList("git.properties")   => MergeStrategy.discard
  case PathList("META-INF", _ @ _*) => MergeStrategy.discard
  case _                            => MergeStrategy.first
}

Test / classLoaderLayeringStrategy := ClassLoaderLayeringStrategy.ScalaLibrary
