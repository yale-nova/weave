## This file is not complete. Will get completed with the access requirements and full guidelines by May 24th. 

We are reproducing our traces on the cluster for reviewers.

You can access the cluster WebUI [here](http://sparkui-eastus.eastus.cloudapp.azure.com:8080/) for the direct cluster, and [here](http://weave.eastus.cloudapp.azure.com:8888/) for the mini SGX cluster with two nodes. 

List of experiments: 

### Cluster access checklist 

First, please check your access to the cluster with the following links, and also the SSH credentials we posted in HotCRP.

1- Access to Spark Web UIs

SGX WebUI is at [here](http://weave.eastus.cloudapp.azure.com:8888/)

Direct WebUI is at [here](http://spark-ui.eastus.cloudapp.azure.com:8080/)


#### Spark WebUI 

#### Plotting UI

#### Spark (Submitting new workloads) 

### 1- SGX HelloWorld 

#### Experiment setup 

#### Plots 

#### Discussion and analysis 

##### SGX Overheads 

#### Traces

### 2- Figure 5.1. Section One: Enron Email Dataset. **Check Time <30mins**. 


#### Experiment setup 

#### Plots 

#### Discussion and analysis 

#### Traces

### 3- Figure 5.1. Section Two: NY Taxi Dataset. **Check Time <30mins**. 

#### Experiment setup 

#### Plots 

#### Discussion and analysis 

#### Traces


### 4- Figure 5.1. Section Three: Pokec Social Network Dataset. **Check Time <30mins**. 

#### Experiment setup 

#### Plots 

#### Discussion and analysis 

#### Traces


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
