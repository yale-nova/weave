package org.apache.spark.shuffle.weave.registry

import scala.collection.concurrent.TrieMap

/**
 * Shared reducer address registry (used from driver, broadcast to mappers).
 */
object WeaveRegistry {

  private val registry = TrieMap.empty[Int, (String, Int)] // partitionId -> (host, port)

  def register(partitionId: Int, host: String, port: Int): Unit = {
    registry.put(partitionId, (host, port))
  }

  def lookup(partitionId: Int): Option[(String, Int)] = {
    registry.get(partitionId)
  }

  def all(): Map[Int, (String, Int)] = registry.readOnlySnapshot().toMap

  def clear(): Unit = registry.clear()
}
