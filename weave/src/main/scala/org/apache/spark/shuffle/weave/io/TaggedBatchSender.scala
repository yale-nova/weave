package org.apache.spark.shuffle.weave.io

import java.io.OutputStream
import scala.collection.mutable

/**
 * Buffers and sends tagged real/fake records to bins, flushing when full.
 */
class TaggedBatchSender[K, V](
    numBins: Int,
    batchSize: Int,
    send: (Int, Seq[(Boolean, K, V)]) => Unit  // send(binId, records)
) {

  private val buffers: Array[mutable.Buffer[(Boolean, K, V)]] =
    Array.fill(numBins)(mutable.Buffer.empty[(Boolean, K, V)])

  def addReal(bin: Int, k: K, v: V): Unit = add(bin, isFake = false, k, v)
  def addFake(bin: Int, k: K, v: V): Unit = add(bin, isFake = true, k, v)

  private def add(bin: Int, isFake: Boolean, k: K, v: V): Unit = {
    buffers(bin).append((isFake, k, v))
    if (buffers(bin).size >= batchSize) {
      flushBin(bin)
    }
  }

  def flushBin(bin: Int): Unit = {
    val batch = buffers(bin)
    if (batch.nonEmpty) {
      send(bin, batch.toSeq)
      batch.clear()
    }
  }

  def flushAll(): Unit = {
    for (bin <- 0 until numBins) {
      flushBin(bin)
    }
  }
}  
