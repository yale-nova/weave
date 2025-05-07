🧵# spark-weave-shuffle🧵

**spark-weave-shuffle** is a high-performance, streaming, balanced, and secure replacement for the default Spark shuffle mechanism.
It is based on the **Weave** shuffle design, aiming to provide:

- **Streaming shuffle**: Early, pipelined data movement during Map phase
- **Balanced reducer assignment**: Histogram-based bin-packing
- **Decentralized fake padding**: Privacy-preserving shuffling without central coordination
- **Batch-tagged sending**: Efficient real/fake batch encoding with minimal metadata overhead

This project is part of a larger effort coordinated with [spool](https://github.com/yourusername/spool),
which handles cluster launch and optimization for Spark clusters running Weave shuffle.

---

## 📚 Paper Context

This repository implements the shuffle layer described in our paper,
**Weave** (OSDI'25).

Weave addresses three key goals simultaneously:

- **Streaming Shuffle**: Enabling early data movement during Map phase to overlap compute and communication.
- **Load Balancing**: Using a two-phase (random shuffle + histogram bin-packing) scheme to evenly distribute keys across reducers.
- **Privacy Protection**: Inserting decentralized fake records (noise) to hide input distributions without central coordination.

The Weave shuffle approach is **secure**, **scalable**, and **efficient**, suitable for large clusters and privacy-sensitive workloads.

---

## 🛠️ Implementation Optimizations

The spark-weave-shuffle implementation includes several optimizations beyond the basic paper design:

- **Batch-Tagged Sending**: Real and fake records are grouped into fixed-size batches (e.g., 100 records per batch) with a single tag per batch, dramatically reducing per-record metadata overhead.
- **Early Streaming Random Shuffle**: Shuffle output is streamed during the Map phase, overlapping shuffle transmission and Map task execution.
- **Configurable Parameters**: All key system parameters (batch size, fake padding ratio, alpha sampling rate, etc.) are tunable via SparkConf.
- **Modular Sender/Reader Architecture**: Clean separation of sending and reading strategies (currently supporting TaggedBatchSender/TaggedBatchReader for high throughput).
- **TCP-Based Transport (Phase 1)**: A simple TCP socket transport is used for initial scalability testing, with planned migration to Spark's BlockManager for full production deployment.
- **Profiling Hooks**: Integrated timers and counters allow phase-by-phase performance breakdowns (Map, Shuffle, Reduce) to be recorded automatically.

These optimizations make Weave not just theoretically secure, but practically efficient for large-scale real-world Spark workloads.

---

## ✨ Main Features

- Streaming random shuffle during Map phase
- In-place histogram building during Map
- Bin-packing key assignment for balanced reducers
- Decentralized fake record generation using binomial sampling
- Batched real/fake tagging per flush (minimal CPU and network overhead)
- Fully configuration-driven via SparkConf (no hardcoded parameters)

---

## 📦 Project Structure

```
src/
  main/
    scala/
      org/
        apache/
          spark/
            shuffle/
              weave/
                config/        # Shuffle configuration (batch size, beta, etc.)
                randomshuffle/ # PRG and Hierarchical random shufflers
                histogram/     # Histogram sampling and merging
                balancedshuffle/ # Bin-packing and fake padding planner
                sender/        # TaggedBatchSender
                reader/        # TaggedBatchReader
                utils/         # Profiling and Binomial Sampler
              WeaveShuffleManager.scala
              WeaveShuffleWriter.scala
              WeaveShuffleReader.scala
```

---

## 🚀 Quick Start

```bash
git clone https://github.com/yourusername/spark-weave-shuffle.git
cd spark-weave-shuffle
sbt compile
```

Run with Spark:

```bash
spark-submit \
  --conf spark.shuffle.manager=org.apache.spark.shuffle.weave.WeaveShuffleManager \
  --conf spark.weave.batchSize=100 \
  --conf spark.weave.globalSeed=1337 \
  --conf spark.weave.alpha=0.01 \
  --conf spark.weave.delta=0.05 \
  --conf spark.weave.beta=0.1 \
  --conf spark.weave.shuffleMode=TaggedBatch \
  ...
```

---

## 📈 Current Status

- TCP-based shuffle transport (simple testing mode)
- Full tagged batch sending and reading
- Local and small cluster scalability tests in progress
- Future: Switch to BlockManager-based shuffle for production deployments

---

## 📚 Related Projects

- [spool](https://github.com/MattSlm/spark-spool.git): Spark cluster launcher optimized for weave-shuffle-based evaluations.
