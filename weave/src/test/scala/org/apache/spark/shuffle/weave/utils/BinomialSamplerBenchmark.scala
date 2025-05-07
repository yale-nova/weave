package org.apache.spark.shuffle.weave.utils

import org.scalatest.funsuite.AnyFunSuite

class BinomialSamplerBenchmark extends AnyFunSuite {

  val trialsPerSample = 1000000
  val p = 0.5
  val seed = 1337L
  val repeatCount = 1000

  private def benchmark(mode: String): Unit = {
    val sampler = new BinomialSampler(seed, mode)
    val values = new Array[Int](repeatCount)

    val t0 = System.nanoTime()
    for (i <- 0 until repeatCount) {
      values(i) = sampler.sample(trialsPerSample, p)
    }
    val t1 = System.nanoTime()
    val totalTimeMs = (t1 - t0) / 1e6

    println(f"\n[$mode] drew $repeatCount values from Binomial($trialsPerSample, $p)")
    println(f"Time: $totalTimeMs%.2f ms")

    val min = values.min
    val max = values.max
    val avg = values.sum.toDouble / values.length

    println(f"Min: $min, Max: $max, Avg: $avg%.2f")
    println(s"Sample: ${values.take(20).mkString(", ")} ...")
  }

  test("Full benchmark and sample comparison for BinomialSampler modes") {
    println(s"\n--- BinomialSampler Benchmark ---")
    println(s"Drawing $repeatCount samples per mode with n = $trialsPerSample, p = $p")

    benchmark("exact")
    benchmark("normal")
    benchmark("library")
  }
}
