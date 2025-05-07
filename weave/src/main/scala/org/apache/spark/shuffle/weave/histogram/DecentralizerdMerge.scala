package org.apache.spark.shuffle.weave.histogram

object DecentralizedMerge {
  def merge[K](local: Map[K, Long], remotes: Seq[Map[K, Long]]): Map[K, Long] = {
    val merged = scala.collection.mutable.HashMap[K, Long]()

    local.foreach { case (k, v) =>
      merged.update(k, merged.getOrElse(k, 0L) + v)
    }

    remotes.foreach { hist =>
      hist.foreach { case (k, v) =>
        merged.update(k, merged.getOrElse(k, 0L) + v)
      }
    }

    merged.toMap
  }
}
