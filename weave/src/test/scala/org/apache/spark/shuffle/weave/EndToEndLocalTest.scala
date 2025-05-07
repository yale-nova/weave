package org.apache.spark.shuffle.weave.writer

import org.apache.spark.shuffle.weave.histogram.HistogramBuilder
import org.apache.spark.shuffle.weave.randomshuffle.PRGShuffle
import org.apache.spark.shuffle.weave.balancedshuffle.SimpleGreedyBinPacking
import org.apache.spark.shuffle.weave.fakepadding.RepeatRealPlanner
import org.scalatest.funsuite.AnyFunSuite

import scala.collection.mutable

class EndToEndLocalTest extends AnyFunSuite {

  test("fake planner generates correct number of fake records per reducer") {
    val numBins = 4
    val alpha = 0.1
    val beta = 0.2
    val seed = 1337L

    // Simulate map output
    val input = (1 to 1000).map { i =>
      val key = s"key${i % 10}"
      (key, i)
    }.iterator

    val shuffle = new PRGShuffle(seed)
    val histBuilder = new HistogramBuilder[String](alpha, seed, "DirectCount")

    val tempBins = Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])
    var localCount = 0
    while (input.hasNext) {
      val (k, v) = input.next()
      val bin = shuffle.assignBin(k, numBins)
      tempBins(bin) += ((k, v))
      histBuilder.maybeAdd(k)
      localCount += 1
    }

    val localSerialized = histBuilder.serialize()
    val globalHist = localSerialized.real

    val binPacker = new SimpleGreedyBinPacking[String](globalHist, numBins, orderBy = "hashcode")
    val finalBins = Array.fill(numBins)(mutable.Buffer.empty[(Boolean, String, Int)])

    // Tag real records
    for (bin <- tempBins; (k, v) <- bin) {
      val targetBin = binPacker.assignBin(k)
      finalBins(targetBin) += ((false, k, v))
    }

    val d = localCount.toDouble / numBins
    val realCounts = finalBins.map(_.count(!_._1))

    val planner = new RepeatRealPlanner(alpha, beta, numBins, seed)
    val fakeCounts = planner.computeFakeCounts(realCounts, d)

    // Tag fake records
    for (i <- 0 until numBins) {
      for (_ <- 0 until fakeCounts(i)) {
        val fakeKey = s"fake-$i"
        finalBins(i) += ((true, fakeKey, -1))
      }
    }

    val totalTagged = finalBins.map(_.size).sum
    val totalFakes = finalBins.map(_.count(_._1)).sum
    val totalReals = finalBins.map(_.count(!_._1)).sum

    assert(totalReals == localCount)
    assert(totalFakes == fakeCounts.sum)
    assert(totalTagged == totalFakes + totalReals)
  }
}
