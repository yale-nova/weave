package org.apache.spark.shuffle.weave.balancedshuffle

import scala.collection.mutable
import scala.reflect.ClassTag

case class SplitBinPackingResult[K](
  keyToBin: Map[K, Int],
  brokenKeys: Map[K, (Int, Double)], // key → (firstReducer, percentAssignedToFirst)
  cutoffs: Array[K]                  // Highest key assigned to each bin
)

object SplitBinPacking {

  def assignKeysWithSplits[K: Ordering : ClassTag](
    histogram: Map[K, Long],
    numBins: Int,
    allowSplits: Boolean
  ): SplitBinPackingResult[K] = {
    val orderedKeys = histogram.keys.toSeq.sorted
    val binLoads = Array.fill(numBins)(0L)
    val assignment = mutable.HashMap.empty[K, Int]
    val brokenKeys = mutable.HashMap.empty[K, (Int, Double)]

    val avgTarget = averageBinTarget(histogram, numBins)

    for (key <- orderedKeys) {
      val weight = histogram(key)
      val target = binLoads.indices.minBy(binLoads)

      if (!allowSplits || binLoads(target) + weight <= avgTarget) {
        assignment(key) = target
        binLoads(target) += weight
      } else {
        val firstBin = target
        val secondBin = math.min(firstBin + 1, numBins - 1)

        val capacity = avgTarget - binLoads(firstBin)
        val ratio = (capacity / weight).min(1.0).max(0.0)

        assignment(key) = firstBin
        brokenKeys(key) = (firstBin, ratio)
        binLoads(firstBin) += (weight * ratio).toLong
        binLoads(secondBin) += (weight * (1 - ratio)).toLong
      }
    }

    // Compute cutoffs: highest key assigned to each bin
    val cutoffs = Array.fill[K](numBins)(null.asInstanceOf[K])
    for ((key, bin) <- assignment) {
      if (cutoffs(bin) == null || implicitly[Ordering[K]].gt(key, cutoffs(bin))) {
        cutoffs(bin) = key
      }
    }

    SplitBinPackingResult(assignment.toMap, brokenKeys.toMap, cutoffs)
  }

  def assignKeysWithSplitsFirstFit[K: Ordering : ClassTag](
  histogram: Map[K, Long],
  numBins: Int,
  allowSplits: Boolean
): SplitBinPackingResult[K] = {
  val orderedKeys = histogram.keys.toSeq.sorted
  val binCap = math.ceil(histogram.values.sum.toDouble / numBins).toLong

  val binLoads = Array.fill(numBins)(0L)
  val assignment = mutable.HashMap.empty[K, Int]
  val brokenKeys = mutable.HashMap.empty[K, (Int, Double)]

  var currentBin = 0

    for (key <- orderedKeys) {
  val weight = histogram(key)
  val currentLoad = binLoads(currentBin)
  val remainingCap = binCap - currentLoad

  //println(f"[Key: $key] Weight = $weight, Bin $currentBin Load = $currentLoad, Remaining = $remainingCap")

  if (!allowSplits || weight <= remainingCap) {
    // No split needed
    //println(f"→ Assigning whole key to Bin $currentBin")
    assignment(key) = currentBin
    binLoads(currentBin) += weight
  } else {
    // Split required
    val ratio = (remainingCap.toDouble / weight).min(1.0).max(0.0)
    val splitFirst = (weight * ratio).toLong
    val splitSecond = (weight * (1 - ratio)).toLong

    //println(f"→ Splitting key: $key | Ratio = $ratio%.2f")
    //println(f"   First part to Bin $currentBin: $splitFirst")
    assignment(key) = currentBin
    brokenKeys(key) = (currentBin, ratio)

    binLoads(currentBin) += splitFirst

    currentBin += 1
    if (currentBin >= numBins)
      throw new IllegalStateException(s"Not enough bins to accommodate all keys (key = $key, weight = $weight)")

    //println(f"   Second part to Bin $currentBin: $splitSecond")
    binLoads(currentBin) += splitSecond
  }

  // Advance bin if it's full
  while (currentBin < numBins && binLoads(currentBin) >= binCap) {
    //println(f"→ Bin $currentBin is full (load = ${binLoads(currentBin)}, cap = $binCap), advancing")
    currentBin += 1
   }
    if (currentBin >= numBins && orderedKeys.last != key) {
      throw new IllegalStateException("Exceeded available bin capacity before assigning all keys")
    }
  }

  // Compute cutoffs: highest key assigned to each bin
  val cutoffs = Array.fill[K](numBins)(null.asInstanceOf[K])
  for ((key, bin) <- assignment) {
    if (cutoffs(bin) == null || implicitly[Ordering[K]].gt(key, cutoffs(bin))) {
      cutoffs(bin) = key
    }
  }

  SplitBinPackingResult(assignment.toMap, brokenKeys.toMap, cutoffs)
  }


  def averageBinTarget[K](hist: Map[K, Long], numBins: Int): Double =
    hist.values.sum.toDouble / numBins
  
}
