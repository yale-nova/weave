package org.apache.spark.shuffle.weave.balancedshuffle

trait BalancedShuffleStrategy[K] {
  def assignBin(key: K): Int
}
