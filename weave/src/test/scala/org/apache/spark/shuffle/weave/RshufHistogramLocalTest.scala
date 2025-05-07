package org.apache.spark.shuffle.weave.writer

import org.apache.spark.shuffle.weave.histogram.{HistogramBuilder, SerializedHistogram}
import org.apache.spark.shuffle.weave.randomshuffle.PRGShuffle
import org.apache.spark.shuffle.weave.balancedshuffle.SimpleGreedyBinPacking
import org.scalatest.funsuite.AnyFunSuite

import scala.collection.mutable

class RshufHistogramLocalTest extends AnyFunSuite {

  test("rshuf + histogram + bshuf completes pipeline locally") {
    val numBins = 4
    val alpha = 0.1
    val seed = 42L

    val input = (1 to 1000).map { i =>
      val key = s"key${i % 10}"  // 10 distinct keys
      (key, i)
    }.iterator

    val shuffle = new PRGShuffle(seed)
    val histBuilder = new HistogramBuilder[String](alpha, seed, "DirectCount")

    val (bins: Array[mutable.Buffer[(String, Int)]], globalHist: Map[String, Long]) = {
      val tempBins = Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])
      while (input.hasNext) {
        val (k, v) = input.next()
        val bin = shuffle.assignBin(k, numBins)
        tempBins(bin) += ((k, v))
        histBuilder.maybeAdd(k)
      }
      val localSerialized: SerializedHistogram[String] = histBuilder.serialize()
      histBuilder.merge(localSerialized)
      (tempBins, localSerialized.real)
    }

    val binPacker = new SimpleGreedyBinPacking[String](globalHist, numBins, orderBy = "hashcode")
    val binAssignments = globalHist.keys.map(k => (k, binPacker.assignBin(k))).toMap

    binAssignments.foreach { case (_, bin) =>
      assert(bin >= 0 && bin < numBins)
    }

    val finalBins: Array[mutable.Buffer[(String, Int)]] =
      Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])
    for (bin <- bins; (k, v) <- bin) {
      val targetBin = binPacker.assignBin(k)
      finalBins(targetBin) += ((k, v))
    }

    val allRecords = finalBins.iterator.flatMap(_.iterator).toVector
    assert(allRecords.size == 1000)

    val keyToBin = mutable.Map.empty[String, Int]
    for ((bin, idx) <- bins.zipWithIndex; (k, _) <- bin) {
      keyToBin.get(k) match {
        case Some(prev) => assert(prev == shuffle.assignBin(k, numBins))
        case None       => keyToBin(k) = idx
      }
    }

    assert(globalHist.keySet.subsetOf((0 until 10).map(i => s"key$i").toSet))

    val expected = 100.0 * alpha
    globalHist.foreach { case (_, count) =>
      assert(count <= 2 * expected && count >= expected / 4)
    }
  }
}
