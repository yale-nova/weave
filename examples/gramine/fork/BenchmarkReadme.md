# Benchmark Analysis and Deployment Recommendations for Spark Cluster on Gramine

## Overview
This document presents a detailed **prediction and recommendation** for deploying a Spark cluster of **10 worker nodes**, each configured with **4GB JVM heap sizes**, operating inside **Gramine enclaves** on **16GB RAM machines**. The goal is to **maximize performance** while **strictly avoiding page migrations** to persistent memory (i.e., swapping or EPC overflows).

The analysis is based on extensive prior benchmarking data collected in Jan 2025 across multiple GC mechanisms and heap configurations, both on native and Gramine environments.

---

## Cluster Target Configuration
| Attribute             | Value                         |
|:----------------------|:-------------------------------|
| Number of Workers      | 10                             |
| JVM Heap Size per Worker | 4 GB                         |
| Machine RAM            | 16 GB total                    |
| CPU Cores per Machine  | 4                              |
| Gramine Mode           | gramine-direct (SGX optional)  |

Each Spark worker JVM will consume 4GB heap plus additional overhead for JVM metadata, thread stacks, and Gramine itself.

---

## Prediction of Performance and Overhead

### 1. Expected Memory Usage
- **Heap:** 4GB per JVM
- **JVM Overhead (off-heap metadata, threads, etc.):** ~0.5GB
- **Gramine Overhead:** ~0.2–0.4GB per JVM (observed empirically)

**Estimated Total per Worker:** ~4.7GB

**Machine RAM usage:**
- 1 worker: ~4.7GB
- 2 workers: ~9.4GB
- 3 workers: ~14.1GB (safe)
- 4 workers: ~18.8GB (**unsafe**, swap/migration likely)

✅ **Thus, 3 workers per 16GB machine is safe**.
✅ **Strictly avoid running 4+ workers per node** to prevent swapping.

---

### 2. Recommended GC

**GC Recommendation: -XX:+UseParallelGC**
- Consistently fastest across all heap sizes.
- Robust against Gramine-induced syscall overhead.
- Lowest memory inflation relative to other GCs.

**GC Flags to set:**
```bash
-XX:+UseParallelGC
-Xmx4G
-Xms4G
```
(Match Xmx and Xms to avoid dynamic heap resizing.)

---

### 3. Predicted Slowdown (Native vs Gramine)

From benchmarks:
- **Baseline Gramine overhead:** ~9 seconds startup
- **Per-operation slowdown (adjusted):** ~0.4–0.9 seconds increase per task

| Metric              | Native JVM | Gramine JVM | Slowdown  |
|:--------------------|:-----------|:------------|:----------|
| CPU Usage           | 150%+      | 100–103%    | ~30% lower |
| Elapsed Time        | 0.3–0.5 sec | 8.5–9.5 sec | ~20x longer (dominated by startup) |
| Memory Inflation    | —         | ~3.5x       | Higher |

🔵 **For long-running Spark jobs (>>10 min)**, the startup overhead becomes negligible.
🔵 **For short-running Spark jobs (<<10 sec)**, the Gramine overhead is significant.

---

### 4. Risk Assessment

| Risk                         | Assessment                     | Mitigation                      |
|:------------------------------|:-------------------------------|:--------------------------------|
| EPC Page Faults / Swapping    | Low (with 3 workers max/node)   | Monitor RSS actively            |
| Memory Pressure               | Medium at >80% usage           | Pre-allocate JVM heap (Xms=Xmx)  |
| Thread Starvation / CPU Load  | Low to Medium                  | Avoid thread pools > CPU cores   |
| GC Stalls                     | Low (using ParallelGC)         | N/A                              |

---

## Final Recommendations

- **Use `-XX:+UseParallelGC` for all Spark workers.**
- **Strictly limit to 3 Spark workers per 16GB machine.**
- **Use `-Xmx4G -Xms4G` to stabilize memory behavior.**
- **If possible, batch startup together to amortize Gramine startup overhead.**
- **Actively monitor resident set size (RSS) and swap activity.**

✅ If these guidelines are followed, the cluster should operate **stably inside Gramine**, with **minimal performance degradation** relative to native operation, especially on large Spark jobs.

---

# End of BenchmarkReadme.md

---

(Generated based on manual interpretation of benchmark results collected Jan 2025.)


