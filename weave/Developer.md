## 📘 Weave Shuffle: Developer Guide for Custom MapReduce

This document shows how to use Weave Shuffle’s building blocks to create your own dataflow pipeline (Map → Shuffle → Reduce) using modular components like:

- `PRGShuffle` for oblivious bin assignment
- `HistogramBuilder` for secure sampling
- `SimpleGreedyBinPacking` for balanced redistribution
- `RepeatRealPlanner` for fake record planning
- `TaggedBatchSender` and `WeaveTCPSocketIO` for custom I/O
- `Kryo` or `Protobuf` encoders for serialization

---

## 🔧 Setup

In your `build.sbt`:
```scala
libraryDependencies += "org.apache.spark" %% "spark-core" % "3.2.2" % "provided"
```

Import necessary modules:
```scala
import org.apache.spark.shuffle.weave.randomshuffle.PRGShuffle
import org.apache.spark.shuffle.weave.histogram.HistogramBuilder
import org.apache.spark.shuffle.weave.balancedshuffle.SimpleGreedyBinPacking
import org.apache.spark.shuffle.weave.fakepadding.RepeatRealPlanner
import org.apache.spark.shuffle.weave.io.TaggedBatchSender
import org.apache.spark.shuffle.weave.registry.WeaveRegistry
```

---

## 📜 High-Level Pipeline

```scala
// Config
val numBins = 4
val alpha = 0.1
val beta = 0.2
val seed = 42L

// Input data
val input: Iterator[(String, Int)] = ... // your Map output

// STEP 1 — PRG Shuffle
val prg = new PRGShuffle(seed)
val hist = new HistogramBuilder[String](alpha, seed, "DirectCount")
val prgBins = Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])

input.foreach { case (k, v) =>
  val bin = prg.assignBin(k, numBins)
  prgBins(bin) += ((k, v))
  hist.maybeAdd(k)
}
```

---

## 📊 STEP 2 — Histogram and Bin Packing

```scala
val sampledHist = hist.serialize().real
val binPacker = new SimpleGreedyBinPacking[String](sampledHist, numBins, "hashcode")

val finalBins = Array.fill(numBins)(mutable.Buffer.empty[(String, Int)])
for (bin <- prgBins; (k, v) <- bin) {
  val targetBin = binPacker.assignBin(k)
  finalBins(targetBin) += ((k, v))
}
```

---

## 🌝 STEP 3 — Fake Record Planning

```scala
val d = input.size.toDouble / numBins
val realCounts = finalBins.map(_.size)
val fakePlanner = new RepeatRealPlanner(alpha, beta, numBins, seed)
val fakeCounts = fakePlanner.computeFakeCounts(realCounts, d)
```

---

## 🌐 STEP 4 — Send Real + Fake Records over Network

```scala
val sender = new TaggedBatchSender[String, Int](
  numBins, batchSize = 100, send = (binId, batch) => {
    val (host, port) = WeaveRegistry.lookup(binId).get
    val out = WeaveTCPSocketIO.connectTo(host, port)
    // Use ProtobufBatchEncoder.writeBatch(batch, out) or your own logic
  }
)

// Real
for ((records, binId) <- finalBins.zipWithIndex; (k, v) <- records)
  sender.addReal(binId, k, v)

// Fake
for (i <- 0 until numBins; _ <- 0 until fakeCounts(i)) {
  val fakeK = s"fake_key_$i"
  val fakeV = -999
  sender.addFake(i, fakeK, fakeV)
}
sender.flushAll()
```

---

## 📥 STEP 5 — Receive on Reducers

```scala
val in = WeaveTCPSocketIO.waitForConnection(serverSocket)
val decoded: Iterator[(String, Int, Boolean)] = decoder.decode(numRecords)

val realRecords = decoded.filterNot(_._3).map { case (k, v, _) => (k, v) }
```

---

## ✅ Summary

With these modules, you can:

- Control shuffle strategy (`PRG`, `Hierarchical`)
- Customize privacy (`alpha`, `beta`)
- Use arbitrary networking backends
- Fully integrate into secure Spark extensions or standalone systems

---
