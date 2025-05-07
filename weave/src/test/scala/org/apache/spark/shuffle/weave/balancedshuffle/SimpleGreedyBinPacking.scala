package org.apache.spark.shuffle.weave.balancedshuffle

import org.scalatest.funsuite.AnyFunSuite

class SimpleGreedyBinPackingTest extends AnyFunSuite {

  test("assigns keys to bins with balanced load") {
    val histogram = Map("a" -> 10L, "b" -> 8L, "c" -> 6L, "d" -> 4L, "e" -> 2L)
    val strategy = new SimpleGreedyBinPacking[String](histogram, numBins = 2)

    val binLoads = Array(0L, 0L)
    histogram.keys.foreach { k =>
      val bin = strategy.assignBin(k)
      binLoads(bin) += histogram(k)
    }

    val imbalance = math.abs(binLoads(0) - binLoads(1))
    assert(imbalance <= 4, s"Bin imbalance too large: $imbalance")
  }

  test("uses hash fallback if key is missing") {
    val histogram = Map("x" -> 1L)
    val strategy = new SimpleGreedyBinPacking[String](histogram, 2)
    assert(strategy.assignBin("notInMap") >= 0)
  }
}
