# Fork and GC Stress Tests under Gramine

This subdirectory contains custom **fork** and **GC performance** stress tests written in **Scala** and **Java**, designed to benchmark:
- Threading scalability
- Forking behavior
- Memory allocation
- JVM Garbage Collection (GC) performance
- Gramine overhead and compatibility

---

## 📁 Structure

| Directory | Purpose |
|:---|:---|
| `src/fork/scala/` | Scala source codes for fork stress testing |
| `fork-jars/` | Built fat JARs |
| `scripts/` | Scripts to build, run, and benchmark tests |
| `output-data/` | Logs, benchmarks, profiling outputs |

---

## 🧪 Benchmark Methodology

- **ForkTestSuite.jar** runs several multi-threaded and forking workloads.
- Tested under both:
  - **Native** JVM
  - **Gramine** (gramine-direct or gramine-sgx)
- Different **GC mechanisms**: G1GC, ParallelGC, ConcMarkSweepGC, ZGC, ShenandoahGC.
- Different **heap sizes**: 512MB, 1GB, 2GB, 4GB.
- Metrics captured:
  - Total elapsed time
  - CPU usage
  - Maximum memory usage
  - Major and minor page faults
  - Context switches
  - Exit codes

---

## 📊 Summary of Baseline Overhead

**Empty HelloWorld (Gramine) Metrics:**

| Metric | Mean | StdDev |
|:---|:---|:---|
| Elapsed Time (sec) | 8.928 | 0.467 |
| User Time (sec) | 8.386 | 0.430 |
| System Time (sec) | 0.784 | 0 |
| CPU % | 102.4 | 0.48 |
| Max RSS (kB) | 212,734 | 727 |
| Major Page Faults | 142,218 | 0 |
| Minor Page Faults | 10,512 | 399 |
| Voluntary Ctxt Switches | 1,528 | 83 |
| Involuntary Ctxt Switches | 83.4 | 7.1 |

---

## 📈 GC Performance Highlights

- **Native JVM** achieves <500ms execution time.
- **Gramine JVM** incurs:
  - ~8.9s startup overhead (enclave loading, library provisioning)
  - Some additional runtime overhead depending on GC.
- **ParallelGC** and **ShenandoahGC** provide the best scalability under Gramine.
- **ZGC** suffers from performance fluctuations and high page faults.

---

## ⚙️ Important Notes

- Experimental GCs like **ZGC** and **ShenandoahGC** require enabling experimental JVM flags.
- Gramine incurs **massive major page faults** due to EPC lazy acceptance and memory management differences.
- Context switching costs are visible for larger thread pools.

---

## 🚀 How to Rebuild and Re-run

```bash
# Build fat jars
cd fork/
make

# Run full native + Gramine GC benchmarking (skip existing results automatically)
./scripts/full-run-benchmarks.sh
✅ Last update: April 2025
