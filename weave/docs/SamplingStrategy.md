## 🎲 Binomial Sampling Strategy: `spark.weave.binomialMode`

Weave uses binomial sampling in the fake padding planner to determine how many fake records to emit per reducer.

You can control the sampling strategy via:

```conf
spark.weave.binomialMode = exact | normal | library
```

### Available Modes

| Mode     | Description                                                                 | Accuracy    | Speed     |
|----------|-----------------------------------------------------------------------------|-------------|-----------|
| `exact`  | Performs 1 RNG per trial: slow but mathematically exact                     | ✅ Perfect   | ❌ Slow    |
| `normal` | Approximates `Binomial(n, p)` using a Gaussian distribution                 | ⚠️ High      | ✅ Fast     |
| `library`| Uses [Apache Commons Math](https://commons.apache.org/proper/commons-math/) for fast and statistically robust draws | ✅ Excellent | ⚡ Fastest |

---

### 🔬 Benchmark Results (1000 samples, n = 1,000,000, p = 0.5)

| Mode     | Time Taken | Min     | Max     | Average   |
|----------|------------|---------|---------|-----------|
| `exact`  | 11,070 ms  | 498,387 | 501,641 | 500,016.18 |
| `normal` | 0.99 ms    | 498,346 | 501,428 | 499,997.97 |
| `library`| 32.15 ms   | 498,513 | 501,555 | 499,986.28 |

> All modes are statistically valid. `normal` and `library` are 300–10,000× faster than `exact` for large n.

---

### ✅ Recommendation

| Use Case                  | Recommended Mode |
|---------------------------|------------------|
| Debugging / small n       | `exact`          |
| Large-scale workloads     | `normal`         |
| Accuracy-sensitive padding| `library`        |

Set your mode in `spark-defaults.conf`:

```conf
spark.weave.binomialMode = normal
```

---

### 🧪 Test it yourself

Run:

```bash
sbt "testOnly org.apache.spark.shuffle.weave.utils.BinomialSamplerBenchmark"
```

to reproduce the benchmark.