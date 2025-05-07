package org.apache.spark.shuffle.weave.balancedshuffle

import scala.collection.mutable

class SimpleGreedyBinPacking[K: Ordering](
    val numBins: Int,
    val orderBy: String = "hashcode"
) extends BalancedShuffleStrategy[K] {

  private var keyToBin: Map[K, Int] = Map.empty

  def fit(histogram: Map[K, Long]): Unit = {
    val orderedKeys: Seq[K] = orderBy match {
      case "ordering" =>
        histogram.keys.toSeq.sorted
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

    keyToBin = assignment.toMap
  }

  override def assignBin(key: K): Int = {
    keyToBin.getOrElse(key, key.hashCode().abs % numBins)
  }
}


