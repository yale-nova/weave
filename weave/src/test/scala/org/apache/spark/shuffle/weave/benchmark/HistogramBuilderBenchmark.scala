package org.apache.spark.shuffle.weave.benchmark

import org.apache.spark.shuffle.weave.histogram.HistogramBuilder
import org.scalatest.funsuite.AnyFunSuite

import scala.util.Random

class HistogramBuilderBenchmark extends AnyFunSuite {

  def generateKeys(total: Int, distinct: Int): Seq[String] = {
    val keySpace = (0 until distinct).map(i => s"key_$i").toArray
    val rng = new Random(1337L)
    Array.fill(total)(keySpace(rng.nextInt(distinct))).toSeq
  }

  def benchmark(total: Int, distinct: Int, alpha: Double, strategy: String): Unit = {
    val keys = generateKeys(total, distinct)
    val builder = new HistogramBuilder[String](
      alpha = alpha,
      seed = 42L,
      histogramStrategy = strategy
    )

    val start = System.nanoTime()
    keys.foreach(builder.maybeAdd)
    val snapshot = builder.snapshot()
    val end = System.nanoTime()

    val elapsedMs = (end - start) / 1e6
    println(f"[$strategy] total=$total, distinct=$distinct, alpha=$alpha => sampled=${snapshot.size}, time=$elapsedMs%.2f ms")
  }

  test("Benchmark HistogramBuilder vs scale") {
    val alphas = Seq(0.01, 0.05, 0.1)
    val totals = Seq(10000, 100000, 1000000)
    val distincts = Seq(100, 1000, 10000)
    val strategies = Seq("DirectCount", "HashedCount")

    for {
      strategy <- strategies
      alpha <- alphas
      total <- totals
      distinct <- distincts
    } yield benchmark(total, distinct, alpha, strategy)
  }
}
