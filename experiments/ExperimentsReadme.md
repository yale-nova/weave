## 🔁 Reproducible Execution of Spark Workloads with Weave Shuffle

This repository provides a unified interface for executing Spark workloads using the **Weave custom shuffle manager**, orchestrated through the **Spool framework**. The workflow supports deterministic dataset scaling, Spark job submission, enclave context isolation, and profiling—ensuring a reproducible, containerized evaluation environment suitable for both development and artifact evaluation.

---


### Getting Started ### 
Please, use the script to run a HelloWorld example with Weave that performs WordCount on the Enron Email dataset. 

```bash
chmod +x run_weave_wordcount.sh
./run_weave_wordcount.sh
```

### 🛠 Script Overview: `run_spark_with_weave.sh`

Location: `examples/scripts/run_spark_with_weave.sh`

This script performs the following tasks:

1. **Dataset sampling or scaling**, implemented as a Spark map-only job.
2. **Spark job execution**, launched via the `spool` interface.
3. **Integration of Weave** as a pluggable shuffle backend.
4. **Optional profiling instrumentation**, activated via `--profiling`.

---

### 📆 Usage

```bash
bash examples/scripts/run_spark_with_weave.sh <job> <scale>
```

| Parameter  | Description                                                                 |
|------------|-----------------------------------------------------------------------------|
| `<job>`    | Spark job to execute. Options: `hist`, `median`, `pagerank`, `terasort`, `invertedindex`. |
| `<scale>`  | Sampling multiplier (float). For example: `0.1` = 10% sample, `1.0` = full dataset, `2.0` = duplication. |

---

### ✅ Prerequisites

Ensure the following steps are completed prior to running the script:

1. **Compile the experiment fat JAR**:

    ```bash
    make build-fatjar
    ```

2. **Download and preprocess the input datasets**:

    ```bash
    make datasets
    ```

3. **Confirm `spool` CLI availability**, either:

    - Within a container configured with Spool as the entrypoint, or
    - By sourcing it locally:

      ```bash
      source /opt/spool/spool.sh
      ```

---

### 🚀 Example Workflows

#### Histogram on 10% of the Enron dataset

```bash
bash examples/scripts/run_spark_with_weave.sh hist 0.1
```

#### PageRank on the full NYC Taxi dataset

```bash
bash examples/scripts/run_spark_with_weave.sh pagerank 1.0
```

---

### 📁 Output Directory Structure

All outputs—including Spark results and profiling data—are written to:

```
examples/output/<job>_<scale>/
```

For instance:

```
examples/output/hist_0.1/
  ├── part-00000           # Spark output partition
  └── weave_profile.json   # Profiling information (if enabled)
```

---

### 🧠 Implementation Notes

- Dataset scaling is performed using the Spark-based `SamplingJob.scala`, preserving reproducibility within Spool contexts.
- Each job is executed within an isolated **Spool context**, facilitating enclave-specific configurations and manifest generation.
- All workloads default to **Direct mode** execution. SGX support can be enabled through Spool's configuration flags.

---

### 📌 Supported Workloads

All jobs are defined in `SparkMapReduceJobs.scala` and follow a clean one-map-one-reduce pattern:

- **Histogram Count** (`hist`)
- **Median Calculation by Key** (`median`)
- **PageRank** (`pagerank`)
- **TeraSort** (`terasort`)
- **Inverted Index Construction** (`invertedindex`)

Each workload is fully instrumented for Weave-based profiling and designed for minimal configuration overhead.

---


