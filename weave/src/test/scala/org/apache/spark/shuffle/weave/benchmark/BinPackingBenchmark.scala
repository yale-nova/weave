package org.apache.spark.shuffle.weave.benchmark

import org.apache.spark.shuffle.weave.balancedshuffle.SimpleGreedyBinPacking
import org.scalatest.funsuite.AnyFunSuite

import scala.util.Random

class BinPackingBenchmark extends AnyFunSuite {

  def generateHistogram(size: Int): Map[String, Long] = {
    val rng = new Random(42)
    (0 until size).map(i => s"k_$i" -> (rng.nextInt(100) + 1).toLong).toMap
  }

  def benchmark(numKeys: Int, numBins: Int): Unit = {
    val histogram = generateHistogram(numKeys)
    val start = System.nanoTime()
    val strategy = new SimpleGreedyBinPacking[String](histogram, numBins)
    val end = System.nanoTime()
    val timeMs = (end - start) / 1e6
    println(f"[BinPacking] keys=$numKeys%6d, bins=$numBins%3d => time=${timeMs}%.2f ms")
  }

  test("SimpleGreedyBinPacking scalability") {
    val keyCounts = Seq(1000, 10000, 100000)
    val binCounts = Seq(4, 16, 64, 256)

    for {
      keys <- keyCounts
      bins <- binCounts
    } benchmark(keys, bins)
  }
}
