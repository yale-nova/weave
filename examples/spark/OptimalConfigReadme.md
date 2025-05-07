# Spark Cluster Optimal Configuration Guide

This document explains how our `suggest_cluster_config.sh` script works for automatically configuring a Spark standalone cluster based on machine memory, EPC memory (SGX enclave memory), number of nodes, and desired cluster size.

---

## Modes Supported

### 1. Simple Mode

- Fast, rough configuration.
- Heap size = (EPC per worker) - 1GB margin.
- Worker memory = Heap + 1GB for JVM/system overhead.
- Parallel GC enabled.
- Assumes small setups or quick tests.

**Usage:**
```bash
bash scripts/suggest_cluster_config.sh simple <cluster_size> <memory_per_machine_gb> <epc_per_machine_gb> <number_of_machines>
```

---

### 2. Optimal Mode (Production Recommended)

- Based on Spark production guidelines, benchmarked EPC memory behavior, and real-world deployment practices.
- Executor memory selected based on cluster size (typical deployments):
  | Cluster Size | Target Executor Memory |
  |:-------------|:------------------------|
  | <=10 nodes   | 6GB                      |
  | <=50 nodes   | 12GB                     |
  | >50 nodes    | 24GB                     |

- Capped by EPC constraints to fit inside enclave memory.
- Driver memory scaled similarly based on cluster size:
  | Cluster Size | Target Driver Memory |
  |:-------------|:---------------------|
  | <=10 nodes   | 4GB                  |
  | <=50 nodes   | 8GB                  |
  | >50 nodes    | 12GB                 |

- Parallel GC enabled for fast multithreaded garbage collection.
- Memory overhead calculated as 10% of executor memory.

**Usage:**
```bash
bash scripts/suggest_cluster_config.sh optimal <cluster_size> <memory_per_machine_gb> <epc_per_machine_gb> <number_of_machines>
```

---

## Example

Suppose you have:
- 1 machine
- 16GB total memory
- 8GB EPC memory
- 1 desired worker

Run:
```bash
bash scripts/suggest_cluster_config.sh optimal 1 16 8 1
```

Expected output:
```
SPARK_EXECUTOR_MEMORY_GB=6
SPARK_EXECUTOR_MEMORY_OVERHEAD_GB=1
SPARK_WORKER_MEMORY_GB=7
SPARK_WORKER_CORES=2
SPARK_DRIVER_MEMORY_GB=4
SPARK_DRIVER_MEMORY_OVERHEAD_GB=1
PARALLEL_GC_OPTS='-XX:+UseParallelGC -XX:+UseParallelOldGC'
```

---

## GC Recommendation Rationale

We set `-XX:+UseParallelGC` by default in optimal mode based on extensive benchmarks conducted in `weave-artifacts/examples/gramine/fork/BenchmarkReadme.md`, specifically:

- ParallelGC showed the best performance for JVM heap sizes inside Gramine enclaves.
- It minimized Gramine syscall overhead and memory inflation.
- Other GCs (G1GC, CMS) caused worse performance inside Gramine.

Key observations from the benchmark:
- ParallelGC showed consistently fastest startup and lowest memory inflation.
- Stable memory usage with `-Xms=Xmx` setting to fix heap size.

---

## References

- [Apache Spark Official Configuration Guide](https://spark.apache.org/docs/latest/configuration.html)
- [Apache Spark Official Tuning Guide](https://spark.apache.org/docs/latest/tuning.html)
- [Databricks Executor Memory Tuning Guide](https://kb.databricks.com/clusters/spark-executor-memory)
- [IBM Guide: Spark Memory and CPU Options](https://www.ibm.com/docs/en/zpas/1.1.0?topic=spark-configuring-memory-cpu-options)
- [Medium: Deep Dive into Spark Memory Management](https://medium.com/@nethaji.bhuma/spark-memory-allocation-management-ebf9129750cb)
- [Internal Benchmark: weave-artifacts/examples/gramine/fork/BenchmarkReadme.md]

---

## Important Notes

- The optimal configuration strictly enforces EPC memory fitting to avoid EPC page faults.
- Master memory consumption (driver) is separated from worker EPC considerations.
- You should monitor actual heap usage and resident set size (RSS) during real deployment.

---

(Generated based on real-world benchmarks and research in April 2025.)


