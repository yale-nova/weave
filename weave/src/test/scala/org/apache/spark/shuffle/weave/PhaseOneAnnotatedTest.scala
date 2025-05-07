package org.apache.spark.shuffle.weave.writer

import org.apache.spark.shuffle.weave.histogram.{HistogramBuilder, SerializedHistogram}
import org.apache.spark.shuffle.weave.randomshuffle.PRGShuffle
import org.apache.spark.shuffle.weave.balancedshuffle.SimpleGreedyBinPacking
import org.scalatest.funsuite.AnyFunSuite

import scala.collection.mutable

class RshufHistogramLocalTest extends AnyFunSuite {

  test("rshuf + histogram + bshuf completes pipeline locally with logs") {
    val numBins = 5
    val alpha = 0.1
    val seed = 42L
    val distinctKeys = 20
    val totalRecords = 1000

    println(s"[Stage 1] Generating input with $totalRecords records and $distinctKeys unique keys")
    val input = (1 to totalRecords).map { i =>
      val key = s"key${i % distinctKeys}"
      (key, i)
    }.iterator

    val shuffle = new PRGShuffle(seed)
    val histBuilder = new HistogramBuilder[String](alpha, seed, "DirectCount")
    val tempBins = Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])

    println(s"[Stage 2] Assigning to bins via PRGShuffle and sampling keys")
    while (input.hasNext) {
      val (k, v) = input.next()
      val bin = shuffle.assignBin(k, numBins)
      tempBins(bin) += ((k, v))
      histBuilder.maybeAdd(k)
    }

    println(s"[Stage 3] Serializing local histogram")
    val localSerialized: SerializedHistogram[String] = histBuilder.serialize()
    histBuilder.merge(localSerialized)

    println(s"[Stage 4] Sampled Histogram (real) on Worker 0:")
    localSerialized.real.toSeq.sortBy(_._1).foreach {
      case (k, v) => println(f"  $k%-6s -> $v")
    }

    val totalSampled = localSerialized.real.values.sum
    println(s"Total sampled keys: $totalSampled")

    val binPacker = new SimpleGreedyBinPacking[String](localSerialized.real, numBins, orderBy = "hashcode")
    val binAssignments = localSerialized.real.keys.map(k => (k, binPacker.assignBin(k))).toMap

    println(s"[Stage 5] Bin assignments (key -> bin):")
    binAssignments.toSeq.sortBy(_._1).foreach {
      case (k, bin) => println(f"  $k%-6s -> bin $bin")
    }

    println(s"[Stage 6] Reassigning records to final bins")
    val finalBins: Array[mutable.Buffer[(String, Int)]] =
      Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])
    for (bin <- tempBins; (k, v) <- bin) {
      val targetBin = binPacker.assignBin(k)
      finalBins(targetBin) += ((k, v))
    }

    println("[Stage 7] Final bin distribution:")
    finalBins.zipWithIndex.foreach { case (records, i) =>
      val keys = records.map(_._1)
      val counts = keys.groupMapReduce(identity)(_ => 1)(_ + _)
      println(f"  Bin $i: ${records.size} records, key breakdown: $counts")
    }

    val allRecords = finalBins.iterator.flatMap(_.iterator).toVector
    assert(allRecords.size == totalRecords)

    println(s"[Stage 8] Verifying histogram coverage and distribution sanity")
    assert(localSerialized.real.keySet.subsetOf((0 until distinctKeys).map(i => s"key$i").toSet))

    val expected = totalRecords.toDouble / distinctKeys * alpha
    localSerialized.real.foreach { case (k, count) =>
      assert(count <= 2 * expected && count >= expected / 4,
        s"Unexpected count for $k: $count vs expected $expected")
    }

    println(s"[✅ Done] All tests passed.")
  }
}
