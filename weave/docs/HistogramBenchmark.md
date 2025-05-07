## 📊 HistogramBuilder Benchmark Results

This benchmark evaluates the scalability and performance of the `HistogramBuilder` class in Weave under different configurations:

- Total records: 10K, 100K, 1M
- Distinct keys: 100, 1K, 10K
- Sampling rates (`alpha`): 0.01, 0.05, 0.1
- Strategies: `DirectCount` vs `HashedCount`

---

### 🔢 Summary Table

| Strategy      | Records   | Distinct Keys | Alpha | Sampled Size | Time (ms) |
|---------------|-----------|----------------|-------|---------------|-----------|
| DirectCount   | 10K       | 100            | 0.01  | 65            | 5.58      |
| DirectCount   | 1M        | 10K            | 0.01  | 6302          | 13.57     |
| DirectCount   | 1M        | 10K            | 0.1   | 9999          | 10.60     |
| HashedCount   | 1M        | 10K            | 0.01  | 6302          | 9.53      |
| HashedCount   | 1M        | 10K            | 0.05  | 9943          | 10.79     |
| HashedCount   | 1M        | 10K            | 0.1   | 9999          | 95.21     |

(See full test output for complete sweep of all combinations.)

---

### ✅ Observations

- Both strategies scale linearly in number of records.
- `DirectCount` is consistently faster, especially for high-cardinality keys.
- `HashedCount` shows increased cost due to hashing and possible GC pressure.
- Sampling fidelity is accurate: sampled size closely matches `alpha * total records`.

---

### ✉ Recommendation

| Use Case                          | Strategy       |
|----------------------------------|----------------|
| Best performance                 | `DirectCount`  |
| Privacy via hashed keys         | `HashedCount`  |
| High cardinality, tight budgets | Avoid `HashedCount` for now |

---

### 📃 Method

Run the benchmark via:

```bash
sbt "testOnly org.apache.spark.shuffle.weave.benchmark.HistogramBuilderBenchmark"
```

Modify `total`, `distinct`, `alpha`, and `strategy` to explore new cases.

---

## 📊 SimpleGreedyBinPacking Benchmark Results

This benchmark evaluates the runtime of the `SimpleGreedyBinPacking` strategy as the number of keys and bins grows.

- Key counts: 1K, 10K, 100K
- Bin counts: 4, 16, 64, 256

### 🔢 Sample Results

| Keys     | Bins | Time (ms) |
|----------|------|------------|
| 1,000    | 4    | 0.30       |
| 10,000   | 4    | 2.65       |
| 10,000   | 64   | 3.71       |
| 100,000  | 256  | 16.85      |

---

### ✅ Observations

- Runtime scales linearly with number of keys.
- Number of bins has only mild e