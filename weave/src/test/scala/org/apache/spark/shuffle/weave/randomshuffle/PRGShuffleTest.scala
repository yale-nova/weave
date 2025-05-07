package org.apache.spark.shuffle.weave.randomshuffle

import org.scalatest.funsuite.AnyFunSuite

class PRGShuffleTest extends AnyFunSuite {

  test("PRGShuffle assigns bins within range [0, numBins)") {
    val numBins = 8
    val prgShuffle = PRGShuffle(taskId = 0, baseSeed = 1337L)

    for (_ <- 1 to 10000) {
      val bin = prgShuffle.assignBin("dummy_key", numBins)
      assert(bin >= 0 && bin < numBins, s"Assigned bin $bin out of range 0 to ${numBins - 1}")
    }
  }

  test("PRGShuffle is reproducible with the same seed and taskId") {
    val numBins = 8
    val seed = 1234L
    val taskId = 42

    val prg1 = PRGShuffle(taskId, seed)
    val prg2 = PRGShuffle(taskId, seed)

    val bins1 = (1 to 1000).map(_ => prg1.assignBin("dummy_key", numBins))
    val bins2 = (1 to 1000).map(_ => prg2.assignBin("dummy_key", numBins))

    assert(bins1 == bins2, "PRGShuffle is not reproducible with same seed and taskId")
  }

  test("PRGShuffle produces reasonably uniform distribution") {
    val numBins = 8
    val prgShuffle = PRGShuffle(taskId = 1, baseSeed = 555L)

    val counts = Array.fill(numBins)(0)

    for (_ <- 1 to 100000) {
      val bin = prgShuffle.assignBin("dummy_key", numBins)
      counts(bin) += 1
    }

    val avg = counts.sum / numBins.toDouble
    val maxDeviation = counts.map(c => math.abs(c - avg)).max

    // Allow ~10% deviation for randomness
    assert(maxDeviation < avg * 0.1, s"Distribution too skewed: counts=${counts.mkString(",")}")
  }
}
