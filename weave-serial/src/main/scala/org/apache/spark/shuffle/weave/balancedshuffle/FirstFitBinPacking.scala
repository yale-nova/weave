package org.apache.spark.shuffle.weave.balancedshuffle

import scala.collection.mutable

class FirstFitBinPacking[K: Ordering](
    val numBins: Int,
    val orderBy: String = "hashcode"
) extends BalancedShuffleStrategy[K] {

  private var keyToBin: Map[K, Int] = Map.empty

  def fit(histogram: Map[K, Long]): Unit = {
    val orderedKeys: Seq[K] = orderBy match {
      case "ordering" => histogram.keys.toSeq.sorted
      case "hashcode" => histogram.keys.toSeq.sortBy(_.hashCode())
      case _ => throw new IllegalArgumentException(s"Unknown orderBy: $orderBy")
    }

    val totalWeight = histogram.values.sum
    val rawCap = totalWeight.toDouble / numBins
    val binCap = math.ceil(rawCap * (2.0 * numBins / (numBins + 1))).toLong
    val assignment = mutable.HashMap.empty[K, Int]
    val binLoads = Array.fill(numBins)(0L)
    var currentBin = 0

    for (key <- orderedKeys) {
      val weight = histogram(key)
      if (binLoads(currentBin) + weight > binCap) {
        currentBin += 1
        if (currentBin >= numBins) {
          throw new IllegalStateException(s"Too many keys to fit into $numBins bins")
        }
      }
      assignment.update(key, currentBin)
      binLoads(currentBin) += weight
    }

    keyToBin = assignment.toMap
  }

  override def assignBin(key: K): Int = {
    keyToBin.getOrElse(key, key.hashCode().abs % numBins)
  }
}
