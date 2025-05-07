# trace_minimal_jars.sh — Minimal Spark JARs Tracing

This script traces which `.jar` files a Spark worker **actually uses** during the execution of a simple Spark job. It helps estimate whether trimming Spark's jars could meaningfully reduce memory usage or disk space.

---

## ✨ How It Works
- Launches a standalone Spark Master.
- Starts a Spark Worker under `strace` to log `.jar` file accesses.
- Submits a test job:
  - **`simple` mode**: Basic RDD job (e.g., `parallelize` and `count`).
  - **`examples` mode**: SparkPi and SparkLR examples from `spark-examples`.
- Collects all `.jar` paths opened by the Worker.
- Computes minimal used `.jar` size vs total `.jar` size.

---

## 📊 Observations (on current installation)

| Metric | Observed |
|:---|:---|
| Total `/opt/spark/jars` size | ~287MB |
| Minimal jars traced (simple job) | ~287MB |
| Size reduction potential | ❌ Almost 0% |

**Reality:**
- Even a **very basic RDD operation** triggered access to almost **all jars**.
- The Spark setup you use is already a **minimal Spark installation** (~287MB).
- Therefore, **no real trimming is achievable** here.

---

## ❓ Why Almost No Reduction?

- Spark loads a broad range of jars **at startup**:
  - Core libraries (RDD, networking, memory management)
  - Configuration libraries (Jackson, Commons-IO, Hadoop client jars)
  - Shuffle, RPC, and serialization dependencies
  - Even Kubernetes-related jars are eagerly loaded

- Thus, **most jars are accessed regardless of the job size**.

- In a "full" Spark installation (~500MB–600MB), trimming could potentially save 40%.
- **In your ~287MB Spark**, the distribution is already stripped down — no further optimization.

---

## 🔢 How to Run

```bash
# Inside the Spark example repo
cd /opt/git/weave-artifacts/examples/spark

# Run minimal RDD-based tracing
./scripts/trace_minimal_jars.sh simple

# Or run SparkPi and SparkLR examples
./scripts/trace_minimal_jars.sh examples
```

**Output Directory:**
```
logs/launch_weave_master_<timestamp>/
```

Files generated:
- `minimal_jars.txt` → Jars accessed during job
- `worker.out`, `worker.err` → Worker logs
- `strace_worker.log` → `strace` tracing output

---

## 📊 Final Analysis

| Case | Outcome |
|:---|:---|
| Full Spark installation (500MB–600MB) | Jar tracing might save ~40% |
| Minimal Spark (~287MB as in your setup) | No meaningful reduction possible |

### ✅ Conclusion
- In your system, **no practical benefit** from trimming jars.
- The Spark package is **already minimal and efficient**.
- **No extra optimization effort needed.**

---

## 🖉 Professional Note
> Always verify trimming effectiveness **after tracing**.  
> Minimal RDD jobs provide the clearest baseline.


