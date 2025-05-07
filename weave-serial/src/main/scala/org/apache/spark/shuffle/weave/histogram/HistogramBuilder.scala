package org.apache.spark.shuffle.weave.histogram

import scala.collection.mutable
import scala.util.Random

class HistogramBuilder[K](
    alpha: Double,
    seed: Long,
    histogramStrategy: String
) {
  private val rng = new Random(seed)
  private val counts = mutable.HashMap.empty[K, Long]
  private val fakeRecords = mutable.ListBuffer.empty[(K, Long)]

  // Key transformation logic
  private val transformKey: K => K = histogramStrategy match {
    case "DirectCount" => identity
    case "HashedCount" => (k: K) => hashAsKey(k)
    case other => throw new IllegalArgumentException(s"Unknown histogramStrategy: $other")
  }

  private def hashAsKey(k: K): K = {
    val hash = k.hashCode().toString
    hash.asInstanceOf[K] // ⚠ Assumes K = String
  }

  def maybeAdd(key: K): Unit = {
    if (rng.nextDouble() < alpha) {
      val mappedKey = transformKey(key)
      if (counts.contains(mappedKey)) {
        fakeRecords += (mappedKey -> 1L)
      } else {
        counts.update(mappedKey, 1L)
      }
    }
  }

  def snapshot(): Map[K, Long] = counts.toMap

  def serialize(): SerializedHistogram[K] = {
    SerializedHistogram(
      real = counts.toMap,
      fake = fakeRecords.toList
    )
  }

  def merge(other: SerializedHistogram[K]): Unit = {
    other.real.foreach { case (k, v) =>
      counts.update(k, counts.getOrElse(k, 0L) + v)
    }
    fakeRecords ++= other.fake
  }

  def clear(): Unit = {
    counts.clear()
    fakeRecords.clear()
  }
}

case class SerializedHistogram[K](
  real: Map[K, Long],
  fake: List[(K, Long)]
)
