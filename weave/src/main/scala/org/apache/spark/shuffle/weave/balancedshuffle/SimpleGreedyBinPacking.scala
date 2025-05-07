package org.apache.spark.shuffle.weave.balancedshuffle

import scala.collection.mutable

class SimpleGreedyBinPacking[K: Ordering](
    histogram: Map[K, Long],
    numBins: Int,
    orderBy: String = "hashcode"
) extends BalancedShuffleStrategy[K] {

  // Final bin assignment table
  private val keyToBin: Map[K, Int] = {
    val orderedKeys: Seq[K] = orderBy match {
      case "ordering" =>
        histogram.keys.toSeq.sorted // requires K: Ordering
      case "hashcode" =>
        histogram.keys.toSeq.sortBy(_.hashCode())
      case _ =>
        throw new IllegalArgumentException(s"Unknown orderBy: $orderBy")
    }

    val binLoads = Array.fill(numBins)(0L)
    val assignment = mutable.HashMap.empty[K, Int]

    for (key <- orderedKeys) {
      val weight = histogram(key)
      val targetBin = binLoads.zipWithIndex.minBy(_._1)._2
      assignment.update(key, targetBin)
      binLoads(targetBin) += weight
    }

    assignment.toMap
  }

  override def assignBin(key: K): Int = {
    keyToBin.getOrElse(key, key.hashCode().abs % numBins)
  }
}
