package org.apache.spark.shuffle.weave.io

import org.scalatest.funsuite.AnyFunSuite
import java.util.concurrent.atomic.AtomicInteger
import scala.collection.mutable

class SenderBenchmarksAndTests extends AnyFunSuite {

  test("AsyncTaggedSender should flush all records in unbounded mode") {
    val flushed = mutable.Buffer[String]()
    val total = new AtomicInteger(0)

    val sender = new AsyncTaggedSender[String, String](
      numBins = 2,
      batchSize = 5,
      send = (bin, isFake, records) => {
        flushed.synchronized {
          flushed += s"bin=$bin isFake=$isFake size=${records.size}"
        }
        total.addAndGet(records.size)
      }
    )

    sender.start()
    for (i <- 0 until 20) {
      sender.add(i % 2, isFake = i % 3 == 0, s"k$i", s"v$i")
    }
    Thread.sleep(200)
    sender.shutdown()

    assert(total.get() == 20)
    assert(flushed.exists(_.startsWith("bin=0")))
    assert(flushed.exists(_.startsWith("bin=1")))
  }

  test("TaggedBatchSenderParallel sends batches by tag and bin") {
    val logs = mutable.Buffer[String]()
    val sender = new TaggedBatchSenderParallel[String, String](
      numBins = 2,
      batchSize = 3,
      send = (bin, isFake, records) => logs += s"bin=$bin tag=$isFake size=${records.size}"
    )

    sender.addReal(0, "k1", "v1")
    sender.addReal(0, "k2", "v2")
    sender.addReal(0, "k3", "v3") // flush
    sender.addFake(0, "k4", "v4")
    sender.addFake(0, "k5", "v5")
    sender.addFake(0, "k6", "v6") // flush
    sender.flushAll()

    assert(logs.count(_.contains("bin=0 tag=false")) >= 1)
    assert(logs.count(_.contains("bin=0 tag=true")) >= 1)
  }
}
