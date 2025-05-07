package org.apache.spark.shuffle.weave.histogram

trait HistogramMergeStrategy[K] {
  def merge(
    local: Map[K, Long],
    remotes: Seq[Map[K, Long]]
  ): Map[K, Long]
}
