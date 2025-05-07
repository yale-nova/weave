package org.apache.spark.shuffle.weave.randomshuffle

import java.util.Random

class PRGShuffle(seed: Long) extends RandomShuffleStrategy {
  private val rng = new Random(seed)

  override def assignBin[K](key: K, numBins: Int): Int = {
    rng.nextInt(numBins)
  }
}

object PRGShuffle {
  def apply(taskId: Int, baseSeed: Long): PRGShuffle = {
    new PRGShuffle(baseSeed + taskId)
  }
}
