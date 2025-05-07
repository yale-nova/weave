package org.apache.spark.shuffle.weave.randomshuffle

trait RandomShuffleStrategy {
  def assignBin[K](key: K, numBins: Int): Int
}
