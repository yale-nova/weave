package org.apache.spark.shuffle.weave.randomshuffle

import java.util.Random

class HierarchicalShuffle(seed: Long) extends RandomShuffleStrategy {
  private val rng = new Random(seed)

  override def assignBin[K](key: K, numBins: Int): Int = {
    if (numBins <= 1) return 0
    val half = numBins / 2
    val flip = rng.nextBoolean()
    if (flip) rng.nextInt(half)
    else half + rng.nextInt(numBins - half)
  }
}

object HierarchicalShuffle {
  def apply(taskId: Int, baseSeed: Long): HierarchicalShuffle = {
    new HierarchicalShuffle(baseSeed + taskId)
  }
}
