## 🔁 Reproducible Execution of Spark Workloads with Weave Shuffle

This repository provides a unified interface for executing Spark workloads using the **Weave custom shuffle manager**, orchestrated through the **Spool framework**. The workflow supports deterministic dataset scaling, Spark job submission, enclave context isolation, and profiling—ensuring a reproducible, containerized evaluation environment suitable for both development and artifact evaluation.

---

# 📦 Weave + Spool: Getting Started

Weave is a secure shuffle engine for Apache Spark that integrates with SGX enclaves using Gramine. This repository packages three independent Weave components and a patched version of Spark, all inside a single Docker-based environment.

Spool orchestrates context creation and transparent enclave management for Weave.

---

## 🧰 Prerequisites

- An x86_64 machine (⚠️ ARM is not supported due to Gramine's ISA requirements)
- Docker installed
- Ubuntu 20.04+ or compatible
- At least 8GB RAM recommended

---

## 🚀 Quick Start

## 🐳 Docker Image

We provide a prebuilt Docker image to simplify running Weave and Spool:

```bash
docker pull solei/spark-spool-direct


### ✅ 1. Run the HelloWorld demo

Inside the container or host VM:

```bash
/workdir/weave_helloworld.sh
```

This script:
- Starts an encrypted Spark master
- Launches one local Spark worker
- Runs a sample WordCount job with Weave on `input.txt`

Output will show standard Spark logs and Weave-specific messages.

---

## 🧪 Manual Verification (Recommended)

### ✅ Step 1: Start Spark Master (unenclaved)

```bash
/opt/spark/bin/spark-class \
  org.apache.spark.deploy.master.Master \
  --host 127.0.0.1 \
  --port 7077 \
  --webui-port 8080
```

> Note: Master is intentionally unenclaved. Weave assumes job metadata is not sensitive.

---

### ✅ Step 2: Start Spark Worker

```bash
/opt/spark/bin/spark-class \
  org.apache.spark.deploy.worker.Worker \
  spark://127.0.0.1:7077 \
  --host 127.0.0.1 \
  --webui-port 8081 \
  --cores 2 \
  --memory 4g
```

Adjust `--memory` as needed for your system.

---

### ✅ Step 3: Submit SparkPi job

```bash
/opt/spark/bin/spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master spark://127.0.0.1:7077 \
  /opt/spark/examples/jars/spark-examples_2.12-3.2.2.jar \
  100
```

✨ This job triggers Weave to:
- Compile a Gramine manifest
- Create a secure context
- Launch encrypted executors

---

## 🔐 Encryption and Executor Contexts

- Spark encryption settings are defined in `/opt/spark/conf/spark-defaults.conf`
- Weave adds encryption at the executor layer via SGX enclaves
- Spool manages:
  - Global worker context: `/opt/spark/enclave`
  - Per-executor context: `/opt/spark/work/<app-id>/<executor-id>`

---

## 🛠 Dependency Recovery

If you encounter errors like:

```
NoClassDefFoundError: scala/PartialFunction
NoClassDefFoundError: org/apache/log4j/spi/Filter
```

Run this to restore build-time JARs:

```bash
cp /opt/private-repos/weave-artifacts-auto/docker/spool/scripts/*.sh /opt/
cd /opt
./parse-system-deps.sh
./install-deps-from-lock.sh
```

If jars are still missing, use:
```bash
/workspace/patch-jars.sh
```

This script recursively finds all missing `.jar` files and copies them into `/opt/spark/jars`.

---

## 🔁 Weave Shuffle Tests

These tests run synthetic 1M-record workloads to benchmark various shuffle strategies:

### ➤ Associative Shuffle

```bash
spark-submit \
  --class org.apache.spark.shuffle.weave.WeaveShufflePerfAssoTest \
  ~/weave-serial/target/scala-2.12/spark-weave-shuffle_2.12-0.1.0.jar
```

> ⏱️ Output: *200 keys shuffled in ~1.4s*

---

### ➤ Non-Associative Shuffle (Sorting)

```bash
spark-submit \
  --class org.apache.spark.shuffle.weave.WeaveShufflePerfTest \
  ~/weave-serial/target/scala-2.12/spark-weave-shuffle_2.12-0.1.0.jar
```

> ⏱️ Output: *~3M records shuffled in ~2.0s*

---

### ➤ Column Sort Benchmark

```bash
spark-submit \
  --class org.apache.spark.shuffle.baseline.TestColumnSort \
  ~/weave-serial/target/scala-2.12/spark-weave-shuffle_2.12-0.1.0.jar
```

> ⏱️ Output: *1M sorted records in ~9.2s*

---

## 📘 Upcoming Integration Tests

- 🔠 Word Count on Project Gutenberg books
- 📧 Enron Email Dataset secure shuffle
- 📊 MelbourneShuffle & ColumnJoin benchmarks

---

## 📎 Notes

- All Spark workers are plaintext-aware; only executors run in SGX.
- Weave automates manifest generation, enclave compilation, and launch.
- `spark.executor.gramine.enabled=true` triggers encrypted execution.


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

