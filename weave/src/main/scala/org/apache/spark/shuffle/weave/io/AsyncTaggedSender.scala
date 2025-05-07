package org.apache.spark.shuffle.weave.io

import java.util.concurrent.{ConcurrentLinkedQueue, Executors, TimeUnit}
import scala.collection.mutable

class AsyncTaggedSender[K, V](
    numBins: Int,
    batchSize: Int,
    send: (Int, Boolean, Seq[(K, V)]) => Unit,
    pollIntervalMs: Int = 50
) {

  private case class TaggedRecord(bin: Int, isFake: Boolean, k: K, v: V)
  private val queue = new ConcurrentLinkedQueue[TaggedRecord]()
  private val worker = Executors.newSingleThreadExecutor()
  @volatile private var running = true

  def add(bin: Int, isFake: Boolean, k: K, v: V): Unit = {
    queue.add(TaggedRecord(bin, isFake, k, v))
  }

  def start(): Unit = {
    worker.submit(new Runnable {
      override def run(): Unit = drainLoop()
    })
  }

  private def drainLoop(): Unit = {
    val grouped = mutable.Map.empty[(Int, Boolean), mutable.Buffer[(K, V)]]

    while (running || !queue.isEmpty) {
      val batchStartTime = System.nanoTime()

      // Drain up to batchSize
      var drained = 0
      while (drained < batchSize && !queue.isEmpty) {
        val rec = queue.poll()
        if (rec != null) {
          val key = (rec.bin, rec.isFake)
          val buf = grouped.getOrElseUpdate(key, mutable.Buffer())
          buf.append((rec.k, rec.v))
          drained += 1
        }
      }

      // Send full groups
      for (((bin, isFake), buf) <- grouped) {
        if (buf.nonEmpty) {
          send(bin, isFake, buf.toSeq)
          buf.clear()
        }
      }

      val elapsed = System.nanoTime() - batchStartTime
      if (drained == 0) {
        Thread.sleep(pollIntervalMs)
      }
    }
  }

  def shutdown(): Unit = {
    running = false
    worker.shutdown()
    worker.awaitTermination(30, TimeUnit.SECONDS)
  }
}  
