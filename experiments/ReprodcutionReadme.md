# SGX Experiment Summary

## Description

This README provides a comprehensive summary and analysis of the execution time overheads observed across various data processing systems (Spark, SparkSorted, Weave, WeaveSorted, SNB, ColumnSort) when running on SGX (Secure Enclave) versus Direct execution. The experiments were conducted on several datasets, including:

* `yellow_tripdata_2020_wy.csv`
* `yellow_tripdata_20212025.csv`
* `enron_spam_data_exploded.csv`
* `enron_spam_data_cleaned.csv`
* `pokec-relations.csv`

Each system and execution mode combination was profiled for real execution time, user CPU time, and total runtime. This document includes numerical comparisons and overhead calculations for each dataset and system.


## Setup (Time to check < 5mins)

**Master node:** One Azure D3s VM (4 cores, 8 GB memory) 

**Worker nodes:** Two Azure DC3s VMs (8 cores, 16 GB memory) with EMM-enabled SGXv2 (EPC support)

```bash
ssh weave-master
ssh edmm-test-vm
ssh edmm-test-vm2
```

You can check SGX availability on the `edmm` VMs with the `is-sgx-available` utility. Here's an example output (this step is optional):

```bash
root@edmm-test-vm:~# is-sgx-available
SGX supported by CPU: true
SGX1 (ECREATE, EENTER, ...): true
SGX2 (EAUG, EACCEPT, EMODPR, ...): true
Flexible Launch Control (IA32_SGXPUBKEYHASH{0..3} MSRs): true
SGX extensions for virtualizers (EINCVIRTCHILD, EDECVIRTCHILD, ESETCONTEXT): false
Extensions for concurrent memory management (ETRACKC, ELDBC, ELDUC, ERDINFO): false
EDECCSSA instruction: false
CET enclave attributes support (See Table 37-5 in the SDM): false
Key separation and sharing (KSS) support (CONFIGID, CONFIGSVN, ISVEXTPRODID, ISVFAMILYID report fields): true
AEX-Notify: true
Max enclave size (32-bit): 0x80000000
Max enclave size (64-bit): 0x100000000000000
EPC size: 0x800000000
SGX driver loaded: true
AESMD installed: true
SGX PSW/libsgx installed: true
#PF/#GP information in EXINFO in MISC region of SSA supported: true
#CP information in EXINFO in MISC region of SSA supported: false
```


Weave adopts a novel design in which Spark executors are deployed inside SGX enclaves. Since executors only exchange encrypted data blocks with other components—and both the size and timing of these blocks are data-independent—this design helps ensure strong confidentiality guarantees. In contrast, the Spark master and worker daemons run outside the enclave (non-EPC).

Job submission is handled via a single `spark-submit` call. Worker nodes dynamically create SGX-based executors based on runtime demand and the configured SGX capability of the CPU. The Spark and Weave configurations are carefully tuned to preserve confidentiality and compatibility.

For reference, we’ve archived a snapshot of the exact configuration used in this experiment:  
👉 [spark-defaults.conf](http://weave.eastus.cloudapp.azure.com:5555/config_snapshot/)

We enable detailed logging (see `log4j.properties`) to collect runtime traces and verify security properties. The exact SGX manifest used in this setup is also saved in the same directory.

### Notes on SGX Manifests

1. We invested substantial time debugging and tuning the SGX manifests to ensure compatibility and optimal performance. Our experiments indicate that existing solutions (e.g., Intel PPML) either fail to run Spark correctly or introduce security flaws. For instance, Intel PPML bypasses Gramine’s syscall proxying by passing parts of `glibc` into the enclave to work around its `vfork` limitations—this undermines the security guarantees of enclave isolation.

2. You can independently verify our claims about data security—at rest, in transit, and during processing—by inspecting the Spark configuration. Encryption and authentication are enabled across the board. Additionally, the execution traces confirm the enforcement of these protections. For example:  
👉 [Sample SGX run log](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250528_103550_6d184e89/)

Download the output or error log files to inspect Spark driver logs and event history.

3. Weave uses two distinct manifest templates: `java.manifest.template`, which configures the PAL loader for Gramine's direct mode (syscall proxying only), and `java.manifest.sgx-template`, which is used when SGX is available on the machine. Both templates are available at the [config snapshot](http://weave.eastus.cloudapp.azure.com:5555/config_snapshot/).

Download the output or error log files to inspect Spark driver logs and event history.

4. Weave configures the manifest and execution mode dynamically. The use of Gramine executors is defined in the Spark configuration (e.g., `spark-defaults.conf`). SGX and EDMM modes are set via environment variables on the worker nodes, as discussed in step 2. When an executor is requested, the worker compiles the appropriate manifest and launches the enclave in SGX or direct mode based on the current settings.

Weave accomplishes this by patching Spark to use a modified `CoarseGrainedExecutor`, which calls a wrapper script: [`$SPARK_HOME/bin/executor-class`](http://weave.eastus.cloudapp.azure.com:5555/config_snapshot/). This script also adapts the JVM heap settings to respect SGX memory boundaries. You can inspect the implementation in our repository or directly on the provisioned VMs.


> **Note:** Some systems may flag these logs due to their file naming format. They are safe to open—use a text editor like Vim for best results.
 

### How to start the cluster?  (Time: <10mins)
## Step 2 -- See SGX + Weave in Action 

### How to Start the Cluster? (Time: <5mins)

You can skip this step and simply check if the cluster is already running via the SGX master WebUI:
👉 [Our SGX master WebUI](http://weave.eastus.cloudapp.azure.com:8888/)

We’ve converted the Weave master and worker nodes into `systemctl` services for easier management. To restart the cluster master:

```bash
ssh weave-master
sudo -i 
source ./helloworld-helpers/env.ssh-spark.sh
sudo systemctl restart spark-master
```

To restart the executors on the first worker VM:

```bash
ssh edmm-test-vm
sudo -i 
SGX=1 EDMM=1 DEBUG=0 PROXY_PDEBUG=0 /home/azureuser/scripts/restart-spark-service-with-env.sh
```

Repeat the same on the second VM:

```bash
ssh edmm-test-vm2
sudo -i 
SGX=1 EDMM=1 DEBUG=0 PROXY_PDEBUG=0 /home/azureuser/scripts/restart-spark-service-with-env.sh
```

After restarting, you can confirm that the cluster is up and running again by refreshing the WebUI.

### How to Run a Simple Job? (Time: less than 10 mins)

We have provided the full trace of both SGX and direct experiments on this two-node cluster:
👉 [Experiment Traces](http://weave.eastus.cloudapp.azure.com:5555/traces/)

You can skip this setup step and [jump to Output Explanation](#output-explanation) —it’s similar to the demo.

We use the `./run_spark_job_task_logging.sh` script to run Spark jobs and collect metrics. Here is an example usage:

```bash
./run_spark_job_task_logging.sh \
  --conf spark.executor.memory=6g \
  --conf spark.executor.gramine.enabled=true \
  --conf spark.driver.host=10.0.0.5 \
  --conf spark.driver.port=35339 \
  --conf "spark.executor.extraJavaOptions=-Dscratch.dir=/opt/spark/enclave/data/scratch -Dweave.scratch.container=weave-scratch -Dweave.scratch.storage=sparkstorage32271" \
  --conf "spark.driver.extraJavaOptions=-Dscratch.dir=/opt/spark/enclave/data/scratch -Dweave.scratch.container=weave-scratch -Dweave.scratch.storage=sparkstorage32271 -Dlog4j.debug -Dlog4j.configuration=file:/opt/spark/conf/log4j.properties" \
  --conf "spark.hadoop.fs.azure.account.auth.type.sparkstorage32271.dfs.core.windows.net=SharedKey" \
  --conf "spark.hadoop.fs.azure.account.key.sparkstorage32271.dfs.core.windows.net=(??????)" \
  --deploy-mode client \
  --class org.apache.spark.shuffle.examples.SparkChunkedShuffleApp \
  /opt/spark/jars/spark-weave-shuffle_2.12-0.1.0.jar \
  "/opt/spark/enclave/data/enron_spam_data_cleaned.csv" \
  weave \
  --key_cols Date \
  --value_cols "Message ID" > snb_out.txt 2>&1
```

This command shuffles the Enron dataset using the `Date` column as key and `Message ID` as value.

Note: The storage key is hidden in the example. To try the same job, use `run_weave.sh`:

```bash
./run_weave.sh /opt/spark/enclave/data/enron_spam_data_cleaned.csv "Date" "Message ID"
```

The script automatically executes jobs in both Spark and Weave modes, generating results like:

```
==============================
🌀 Running mode: spark
==============================
📄 Log saved to: task_out_spark.txt
📂 SGX Result Directory: sgx_results/20250528_180748_af4e760d
✅ spark succeeded! Found: sgx_results/20250528_180748_af4e760d/stage_info.csv

==============================
🌀 Running mode: weave
==============================
📄 Log saved to: task_out_weave.txt
📂 SGX Result Directory: sgx_results/20250528_180945_83e98955
✅ weave succeeded! Found: sgx_results/20250528_180945_83e98955/stage_info.csv
root@weave-master:/home/azureuser/workspace/scripts# cat task_out_weave.txt 

```

Timing:

* Spark: \~2.1 mins
* Weave: \~1.9 mins

Result traces are stored under `sgx_results/`. Example metadata:

```bash
cat sgx_results/20250528_180945_83e98955/metadata.json
```

This metadata helps verify the authenticity of shared results:
👉 [SGX traces](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/)
👉 [Direct traces](http://weave.eastus.cloudapp.azure.com:5555/traces/direcct_data/)

We also saved static Spark UI snapshots:
👉 [All UIs](http://weave.eastus.cloudapp.azure.com:5555/webuis/)
👉 [SGX UI](http://weave.eastus.cloudapp.azure.com:5555/webuis/sgx_webui_snapshot/)
👉 [Direct UI](http://weave.eastus.cloudapp.azure.com:5555/webuis/direct_webui_snapshot/)

#### Output Explanation:

* 📦 `Artifacts saved to:` — Full run directory (e.g., `sgx_results/20250528_180945_83e98955`)
* 🧾 `output.log`, `output.err` — Full logs from `spark-submit` (used to validate features like authentication)
* 📄 `time_metrics.csv` — Real/user/sys timing per run
* 🧠 `metadata.json` — Full Spark command, mode, and parameters


## Scripts We Provide for Independent Reproduction of Our Results

> **Note:** Please skip this section, and [Jump to Trace Verification Data](#data-we-provide-for-verifying-that-traces-we-shared-are-correct) unless strictly necessary. Running the experiments via these scripts is fragile and requires close supervision. The configuration overhead and setup time are significant.

1. **To create the Spark cluster (non-SGX, container-based setup)**:

```bash
root@weave-master:/home/azureuser/workspace/scripts# ./create_hybrid_bound_aks_cluster.sh
```

2. **To relaunch the Spark cluster (Kubernetes mode for 10-node non-SGX experiments)**:

```bash
root@weave-master:/home/azureuser/workspace/scripts# ./launch-hybrid-spark-clusters.sh
```

3. **To run experiments** (must be executed on `weave-master` for SGX, or `spark-master-0` for Kube-based clusters):

```bash
./run_all.sh
```

4. **To fetch and collect experiment traces from all nodes**: 

   * For Kubernetes:

     ```bash
     ./scripts/fetch_experiment_logs_k8s.sh 22 spark
     ```

     Fetches the last 22 experiment logs from all worker nodes in the `spark` namespace.

   * For VM-based clusters:

     ```bash
     ./scripts/fetch_experiment_logs.sh "edmm-test-vm,edmm-test-vm2" 6
     ```

     Collects logs from the last 6 experiments across the specified worker VMs.

### Data we provide for verifying that the traces we shared are correct (Time to check for validity of the results <10 mins)

In addition to the data referenced earlier in the setup section, we provide detailed logs and structured outputs for each experiment.

For example:
👉 [Weave shuffling on Enron Email Dataset with SGX](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/metadata.json)

* **Master log**:
  [master\_logs/](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/master_logs/)
* **Executor logs (2 workers)**:
  [executor\_logs/](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/executor_logs/)
* **Event log**:
  [event\_log/](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/event_log/)

Additionally, we provide CSVs that summarize job and task timing:

* `stage_info.csv`
* `task_specs.csv`

📈 **Example stage info:**

```
2027-05-25 18:49:31	6.0	0	ResultStage
2027-05-25 18:50:37	72.0	1	ShuffleMapStage
...
```

📊 **Example task specs:**

```
timestamp	elapsed_sec	task_id	stage_id	task_number	executor_id	host
2027-05-25 18:50:20	55.0	0	0.0	0.0	1	10.0.0.6
...
```

These files are part of each trace directory, enabling validation of our execution logs and experiment freshness.

You may also validate that Weave + Spool was used during execution by inspecting the executor error logs.

For example:

```bash
wget http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/executor_logs/edmm-test-vm_err.log
cat edmm-test-vm_err.log
```

Excerpt from the log:

```
25/05/27 18:49:26 INFO Worker: Asked to launch executor app-20250527184926-0020/0 for SparkChunkedHistCountApp
25/05/27 18:49:26 INFO ExecutorRunner: 🏁 [ExecutorRunner] Starting executor runner for app: app-20250527184926-0020, execId: 0
25/05/27 18:49:26 INFO ExecutorRunner: 🔨 Original JVM launch command: /usr/lib/jvm/java-11-openjdk-amd64/bin/java -cp /opt/spark/conf/:/opt/spark/jars/* -Xmx6144M -Dspark.network.crypto.enabled=true -Dspark.network.crypto.keyFactoryAlgorithm=PBKDF2WithHmacSHA1 ...
25/05/27 18:49:26 INFO ExecutorRunner: 🧵 Final wrapped command: **[1;31m/opt/spark/bin/spark-executor-class[0m** /usr/lib/jvm/java-11-openjdk-amd64/bin/java -cp /opt/spark/conf/:/opt/spark/jars/* -Xmx6144M -Dspark.network.crypto.enabled=true -Dspark.network.crypto.keyFactoryAlgorithm=PBKDF2WithHmacSHA1 ...CoarseGrainedExecutorBackend --driver-url spark://CoarseGrainedScheduler@10.0.0.5:35339 --executor-id 0 --hostname 10.0.0.4 --cores 8 --app-id app-20250527184926-0020 --worker-url spark://Worker@10.0.0.4:43259
25/05/27 18:49:26 INFO ExecutorRunner: 🚀 Launching command: **[1;31m"/opt/spark/bin/spark-executor-class"[0m" "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" "-cp" "/opt/spark/conf/:/opt/spark/jars/*" ...
```


The presence of `spark-executor-class` confirms the use of the Weave-patched execution wrapper.


The presence of `spark-executor-class` confirms the use of the Weave patched execution wrapper.

Additionally, loader logs include the **final command** launched by the executor wrapper, which invokes either the SGX Gramine PAL loader (`gramine-sgx`) or the Gramine direct mode loader depending on configuration.

These logs are available under the `app_data` directory. For example, for the WordCount application:
👉 [app_data/](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/app_data/)

Inspect the application log for **Worker 0, Executor 0** by downloading the log from:  
👉 [worker_1/0/](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/app_data/worker_1/0/)

Sample output:
```

\[spark-executor-class] 🚀 Launching with: gramine-sgx, SGX=1, EDMM=1
25/05/27 18:49:40 INFO CoarseGrainedExecutorBackend: Started daemon with process name: 1\@edmm-test-vm

```

These logs also contain authentication details and the hashes of the used manifests. You can cross-reference these hashes with the actual manifest files, which are copied into the same snapshot directory:
👉 [java.manifest, java.manifest.sgx](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8/app_data/worker_1/0/)

Weave treats each `app_data` directory as the **protected enclave workspace** for executors. The working directory is configured under `$SPARK_HOME/work/${app_id}` to ensure isolation and reproducibility.

## Snapshots of Spark WEB-UIs (Optional Step)

We have collected snapshots of WebUIs that you can use to additionally verify the reported numbers from direct and SGX runs. Although it might be difficult to manually map Spark APP-IDs to specific workloads, you can use the `metadata.json` files from each experiment’s trace directory to locate the correct APP-ID.

- 👉 [Direct cluster WebUI](http://weave.eastus.cloudapp.azure.com:5555/webuis/direct-webui-snapshot/)
- 👉 [SGX cluster WebUI](http://weave.eastus.cloudapp.azure.com:5555/webuis/sgx_webui_snapshot/10.0.0.5%3A8888/)
- 👉 [Kubernetes cluster WebUI](http://weave.eastus.cloudapp.azure.com:5555/webuis/kube_cluster_webui/)

Up to this point, we have described the cluster setup and logging infrastructure.


## Plots of the fresh experiment reruns 
Before presenting the structure and semantics of the collected traces, we first introduce the plots generated for each experiment.

We have placed all generated plots under the [plotting subdirectory](http://weave.eastus.cloudapp.azure.com:5555/plotting/) of the WebUI. These interactive Plotly charts allow you to inspect exact values by hovering over data points.

For example, [this summary page](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_yellow_tripdata_202%5C%2A_wy.csv_full_summary.html) visualizes the overhead of WordCount and Sort across multiple schemes:

- Spark (Insecure)
- Spark + Sort (Insecure shuffling + range partitioning that enables the execution of queries that need the data to be range-based distributed)
- Weave
- Weave + Sort
- ColumnSort (Opaques main component)
- SnB (Shuffle and balance)

A screenshot of one of these plots is provided in the document for reference.

[![Sample Plot](https://github.com/MattSlm/weave-artifacts/raw/main/images/sample_plot.png)](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_yellow_tripdata_202%5C%2A_wy.csv_full_summary.html)  
  
We use the same hatch and hue patterns as the paper to ensure consistent visual comparison.

#### 🔍 Highlight: Important Note on the Plot Above

> ⚠️ **Please note:** The execution time shown for Weave in the plot above corresponds to the time before an OOM failure occurred.
>
> Additionally, SnB values may appear as `NaN` in the plot. This is due to the `time` command not producing valid outputs in those runs.
>
> Every plot we provide includes a **raw numerical data table** at the bottom of the corresponding HTML page. For the above figure, the underlying data table can be found in:
>
> 👉 [sgx_data_full_experiment_summary.csv](http://weave.eastus.cloudapp.azure.com:5555/extracted_datasets/sgx_data_full_experiment_summary.csv)
>
> If needed, you can cross-reference plot bars to source data by checking the corresponding extracted CSVs in:  
> 👉 [http://weave.eastus.cloudapp.azure.com:5555/extracted_datasets/](http://weave.eastus.cloudapp.azure.com:5555/extracted_datasets/)


## Performance Challenges and Optimizations for SGX Execution 

**Feel free to skip this section, which describes Weave optimizations to use SGX + Gramine.** Jump to the [next experiment section](#overall-sgx-overhead-across-all-systems)

Deploying Spark on SGX, even with the help of a LibOS like Gramine, has proven to be a challenging task. SGXv1 requires static memory preallocation and thread reservation, which is incompatible with Spark's dynamic and resource-intensive behavior, including RPC threads, GC threads, and shuffle workers. As a result, running Spark on SGXv1 is not only inefficient (often incurring more than 10× overhead), but also unpredictable and error-prone.

Batch-oriented systems like ColumnSort and SnB frequently experience GC faults or out-of-memory errors under SGXv1. Additionally, Java-based systems like Hadoop and HDFS rely heavily on OS-level calls and subprocess spawning, which are discouraged or disallowed by Gramine’s secure configuration. These limitations often cause Spark components to crash fatally due to unhandled exceptions or missing fallback routines.

Previous solutions [circumvented these issues by launching enclaves through](https://github.com/intel/BigDL/blob/main/ppml/base/bash.manifest.template) `bash`, but this approach consumes excessive EPC memory, reserving \~50% of enclave memory for bash, leaving little room for actual executor computation.

Weave addresses these challenges with several key design and configuration changes: 

1. **Use of SGXv2 with dynamic memory management**, allowing more flexible allocation and significantly improving enclave utilization.
2. **Executor-centric enclave model**: We spawn long-lived SGX executors while keeping workers outside the enclave. This contrasts with prior models that placed Spark workers inside SGX and launched executors as subprocesses.
3. **Minimal enclave entrypoint**: We directly set the entrypoint of the enclave to Spark’s `CoarseGrainedExecutorBackend`, avoiding intermediary shells or wrappers.
4. **Optimized SGX manifest parameters**: Including JVM stack/heap sizes, GC algorithm and thread settings, max enclave size, and the number of preallocated thread slots.

These optimizations collectively reduce SGX overhead to between **1.8× and 3.2×** on average. In practice, they make Weave’s execution time and resource efficiency comparable to that of direct Gramine execution, while maintaining strict isolation and integrity.

We present these insights here to provide context for the extrapolated SGX performance plots and to explain the system-level design decisions that enable Weave to run efficiently under SGX.

In addition to the challenges above, we encountered several recurring issues that had to be addressed to make Weave express deterministic behavior under SGX:

* Clock synchronization issues in Gramine that impacted coordination across nodes.
* `vfork` and `clone` [behavior inconsistencies](https://github.com/gramineproject/graphene/issues/2672) leading to subtle runtime bugs.
* Unresolved Hadoop local storage bugs that consistently broke execution; we now circumvent these by using Azure storage exclusively.

### Extrapolation experiment design (Time: <25mins)

#### Data and scale 

Our experiment with SGX shows that the overhead under normal working conditions is fairly consistent. Across all systems, serial execution times (e.g., I/O and communication) are much smaller than parallel compute times. Therefore, we expect that executing 20% of the data on 2 workers gives comparable SGX overhead to full-scale execution on 10 workers.

We also observed that the longer a task takes, the **lower** its SGX overhead becomes. To estimate performance overheads more precisely, we compute the **weighted average SGX overhead**, using native (non-SGX) execution times as weights. This ensures longer tasks have more influence on the reported overhead.

Looking at the data and plots, this trend is consistent: execution overhead decreases as execution time increases.

We evaluated this across several scales and workloads using the original experiment configurations. This includes 20% of the data on 2 workers, scaling up to full datasets on 10 nodes. We used the original Key/Value columns described in the paper, and tested on:

* [NYC Taxi dataset](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
* [Enron Email dataset](https://www.kaggle.com/datasets/wcukierski/enron-email-dataset)
* [Pokec Social Network dataset](https://snap.stanford.edu/data/soc-Pokec.html)

All datasets are stored either in Azure Blob Storage or a shared NFS mount accessible at `weave-master:/opt/spark/enclave/data`.


#### Notes on Interpreting SGX Execution Behavior

Our extended analysis revealed several additional insights to help interpret execution behavior and explain certain anomalies seen in trace data:

1. **Unusually high execution overhead almost always indicates memory exhaustion**. This may happen due to under-provisioned heap settings, unbounded GC behavior, or lack of dynamic memory support.

2. **ColumnSort exhibits deterministic performance when batching is used**, thanks to a design that adjusts batch size based on JVM memory. Batches are flushed to Azure Blob Storage as needed, reducing pressure on heap memory. This has enabled long-running SGX jobs (e.g., >2 hours) to execute without issues on multiple executors.

3. **In contrast, SNB requires strict padding for correctness**, as defined in [Algorithm 1 of the paper](https://people.eecs.berkeley.edu/~raluca/cs261-f15/readings/MSR-TR-2015-70.pdf). Its padding depends inversely on the logarithm of the batch size. For typical batch sizes (0.01 to 0.001 of the original data), this results in 6×–10× padding overhead. This makes batching ineffective and causes SNB to fail to complete (DNF) in SGX and direct modes frequently.

These details are important when evaluating the raw execution traces. We have structured our system to make performance behavior both understandable and reproducible, and the experiments described above form the basis for extrapolating meaningful SGX overhead figures.


### Tasks (Check time 30 mins, rerun time up to 7hrs)

#### Task 1 - Enron Email Dataset (Small Scale)

##### Purpose: Computing SGX Startup Overheads

* **Input Data:** `weave-master:/opt/spark/enclave/data/enron_spam_data_cleaned.csv`
* **Plots:** [Execution Summary Plot](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_enron_spam_data_cleaned.csv_full_summary.html)
* **CSV Source:** `direct_data_experiment_summary.csv` and `sgx_data_experiment_summary.csv` — available [here](http://weave.eastus.cloudapp.azure.com:5555/extracted_datasets/)

##### Analysis

This task was designed to analyze SGX startup overheads. Since the task is computationally lightweight, its runtime is dominated by startup costs, primarily influenced by the Java heap size (4GB) per executor.

As shown in the plots and numerical data, the real execution time overhead for SGX is approximately **5×**. This is expected given the static memory allocation and initialization latency of SGX enclaves.

Notably, systems like ColumnSort and SnB exhibit slightly **lower** relative overheads in this scenario because their execution duration dilutes the impact of fixed startup time, revealing more realistic runtime behavior.

You can inspect these patterns visually in the sample plot linked above. Hue at hatches maps are in the plotting UI. Columns are Spark, Spark+Sort, Weave, Weave+Sort, ColumnSort, and SnB, respectively. 


<p align="center">
  <img src="https://github.com/MattSlm/weave-artifacts/raw/main/images/task1_sgx_overhead.png?raw=true" width="45%">
  <img src="https://github.com/MattSlm/weave-artifacts/raw/main/images/task1_spark_overhead.png?raw=true" width="45%">
</p>

### Rerun Instructions (You can also check the data without rerunning)

To rerun the experiments and reproduce the SGX overhead plots for the Enron dataset:

1. **Start the cluster in SGX mode** on `weave-master`:

```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/enron_spam_data_cleaned.csv "Date" "Message ID"
```

### Map to snapshot data 

Below are selected SGX trace records for the Enron Email dataset experiment:

| UID                     | Trace Link                                                                                         | Real | User | Sys | Input CSV Path                                                   |
|------------------------|----------------------------------------------------------------------------------------------------|---------------------|-------------|----------|------------------------------------------------------------------|
| 20250527_123926_a151e27c | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_123926_a151e27c) | 118.33              | 35.07       | 1.22     | `/opt/spark/enclave/data/enron_spam_data_cleaned.csv`           |
| 20250527_124307_3d55a8a5 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_124307_3d55a8a5) | 128.53              | 36.44       | 1.20     | `/opt/spark/enclave/data/enron_spam_data_cleaned.csv`           |
| 20250527_124713_46b5f094 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_124713_46b5f094) | 116.90              | 36.63       | 1.16     | `/opt/spark/enclave/data/enron_spam_data_cleaned.csv`           |
| 20250527_125108_274a628b | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_125108_274a628b) | 127.20              | 39.30       | 1.26     | `/opt/spark/enclave/data/enron_spam_data_cleaned.csv`           |


Task 2 - 

Task 3 - 

Task 4 - 

Task 5 - 

Task 6 - Full scale NY Taxi Dataset (Sort and Wordcount) 
Traces: 
Plots: 

#### Runtimes 

#### Map to the shared traces 

#### Reproduction Guide 

### Overall SGX Overhead Across All Systems

- Minimum: **1.59×**
- Average: **3.2×**
- Maximum: **5.46×**
- Weighted Average: **2130.68×**

### Overall SGX/Direct Overhead (Real Time)
- Minimum: **1.59×**
- Average: **3.2×**
- Maximum: **5.46×**
- Weighted Average: **2.06×**

### SGX/Direct Overhead Per System
| mode        |   avg_overhead |   min_overhead |   max_overhead |   weighted_avg_overhead |
|:------------|---------------:|---------------:|---------------:|------------------------:|
| columnsort  |           2.65 |           1.59 |           3.5  |                    1.87 |
| snb         |           4.69 |           4.69 |           4.69 |                    4.69 |
| spark       |           3.35 |           1.96 |           4.68 |                    2.63 |
| sparksorted |           3.5  |           1.92 |           5.12 |                    2.6  |
| weave       |           3.19 |           1.65 |           5.41 |                    2.27 |
| weavesorted |           3.02 |           1.59 |           5.46 |                    2.11 |

### Overhead Dist Compared to Spark (Direct/SGX)
| mode        |   avg_vs_spark_direct |   min_vs_spark_direct |   max_vs_spark_direct |   avg_vs_spark_sgx |   min_vs_spark_sgx |   max_vs_spark_sgx |
|:------------|----------------------:|----------------------:|----------------------:|-------------------:|-------------------:|-------------------:|
| columnsort  |                  6.17 |                  1.68 |                 11.51 |               4.91 |               1.25 |               9.32 |
| snb         |                  1.02 |                  1.02 |                  1.02 |               1.02 |               1.02 |               1.02 |
| spark       |                  1    |                  1    |                  1    |               1    |               1    |               1    |
| sparksorted |                  1.05 |                  0.9  |                  1.14 |               1.08 |               0.99 |               1.15 |
| weave       |                  1.2  |                  0.94 |                  1.37 |               1.09 |               1.05 |               1.15 |
| weavesorted |                  1.34 |                  0.92 |                  1.6  |               1.13 |               1.07 |               1.26 |

### Overhead Dist Compared to Weave (Direct/SGX)
| mode        |   avg_vs_weave_direct |   min_vs_weave_direct |   max_vs_weave_direct |   avg_vs_weave_sgx |   min_vs_weave_sgx |   max_vs_weave_sgx |
|:------------|----------------------:|----------------------:|----------------------:|-------------------:|-------------------:|-------------------:|
| columnsort  |                  4.92 |                  1.78 |                  8.43 |               4.45 |               1.15 |               8.12 |
| snb         |                  1.09 |                  1.09 |                  1.09 |               0.94 |               0.94 |               0.94 |
| spark       |                  0.85 |                  0.73 |                  1.06 |               0.92 |               0.87 |               0.95 |
| sparksorted |                  0.89 |                  0.84 |                  0.96 |               0.99 |               0.91 |               1.1  |
| weave       |                  1    |                  1    |                  1    |               1    |               1    |               1    |
| weavesorted |                  1.11 |                  0.98 |                  1.28 |               1.04 |               0.99 |               1.09 |

Reproducibility scripts, performance logs, and profiling outputs for both SGX and Direct execution are available. All logs are archived under `sgx_data/` and `direct_data/`, with plotting outputs organized per dataset in `plotting/`.


## Behavioral Consistency Across Modes

To measure the similarity of system performance between SGX and Direct execution modes, we computed the Wasserstein distance between the per-system overhead distributions. Weave consistently shows the smallest Wasserstein distance between its SGX and Direct mode overheads, indicating its behavior is most stable regardless of the execution environment. This metric, with a distance of 0.14, supports the claim that Weave’s performance characteristics remain consistent and predictable under SGX.

## Time-Dependent SGX Overhead Trend

One notable trend is that SGX overhead sharply decreases with longer execution durations. Shorter jobs are disproportionately affected by the fixed costs associated with SGX, such as page fault handling, JVM initialization, and secure memory allocation. However, these overheads become negligible in larger workloads. On average, the SGX overhead converges toward a stable multiplier of **\~2x**, highlighting the practical scalability of enclave-based systems when amortized over time.

## Trace Snapshots

Snapshots of Spark UIs and performance metrics across execution rounds for each system and mode are available [here](http://weave.eastus.cloudapp.azure.com:5555/traces/), the data for SGX execution is under [sgx_data](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/), and for direct execution is under [direct_data](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/). These include executor timelines, SQL stages, task breakdowns, and GC metrics.

For any assistance or rerun request, please contact the experiment authors or refer to the reproduction scripts provided in the root directory.

