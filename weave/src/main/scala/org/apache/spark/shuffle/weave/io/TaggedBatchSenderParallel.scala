package org.apache.spark.shuffle.weave.io

import java.io.OutputStream
import scala.collection.mutable

/**
 * TaggedBatchSenderParallel maintains separate real/fake buffers per bin.
 * Flush order and parallelism is configurable externally.
 */
class TaggedBatchSenderParallel[K, V](
    numBins: Int,
    batchSize: Int,
    send: (Int, Boolean, Seq[(K, V)]) => Unit  // send(binId, isFake, records)
) {

  private val realBuffers: Array[mutable.Buffer[(K, V)]] =
    Array.fill(numBins)(mutable.Buffer.empty[(K, V)])

  private val fakeBuffers: Array[mutable.Buffer[(K, V)]] =
    Array.fill(numBins)(mutable.Buffer.empty[(K, V)])

  def addReal(bin: Int, k: K, v: V): Unit = {
    realBuffers(bin).append((k, v))
    if (realBuffers(bin).size >= batchSize) flushBin(bin, isFake = false)
  }

  def addFake(bin: Int, k: K, v: V): Unit = {
    fakeBuffers(bin).append((k, v))
    if (fakeBuffers(bin).size >= batchSize) flushBin(bin, isFake = true)
  }

  def flushBin(bin: Int, isFake: Boolean): Unit = {
    val buffer = if (isFake) fakeBuffers(bin) else realBuffers(bin)
    if (buffer.nonEmpty) {
      send(bin, isFake, buffer.toSeq)
      //buffer.clear()
    }
  }

  def flushAll(): Unit = {
    for (bin <- 0 until numBins) {
      flushBin(bin, isFake = false)
      flushBin(bin, isFake = true)
    }
  }
}
