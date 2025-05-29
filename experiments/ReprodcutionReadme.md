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

#### Task 1 - Enron Email Dataset (Small Scale) (Check time < 5 mins, rerun time <10 mins) 

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
Then 
```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/enron_spam_data_cleaned.csv "Date" "Message ID"
```

2- **Restart the cluster in Direct mode** on `weave-master`:
Then 
```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/enron_spam_data_cleaned.csv "Date" "Message ID"
```

#### Map to snapshot data 

Below are selected SGX and Direct trace records for task 1:

| UID                        | Trace Link                                                                                            | Time (s) | GC Time (s) | Overhead | Mode        | SGX |
| -------------------------- | ----------------------------------------------------------------------------------------------------- | -------- | ----------- | -------- | ----------- | --- |
| 20250527\_194608\_af4e760d | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_194608_af4e760d) | 25.28    | 32.68       | 1.14     | spark       | No  |
| 20250527\_194634\_d1df3dd2 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_194634_d1df3dd2) | 22.85    | 34.46       | 1.12     | sparksorted | No  |
| 20250527\_194658\_83e98955 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_194658_83e98955) | 23.75    | 38.13       | 1.24     | weave       | No  |
| 20250527\_194722\_1bb32ae4 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_194722_1bb32ae4) | 23.29    | 38.14       | 1.24     | weavesorted | No  |
| 20250527\_194746\_7a89575c | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_194746_7a89575c) | 42.37    | 71.75       | 2.05     | columnsort  | No  |
| 20250527\_194829\_0d9e9da3 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_194829_0d9e9da3) | 25.77    | 43.16       | 1.34     | snb         | No  |

##### SGX Runs

| UID                        | Trace Link                                                                                         | Time (s) | GC Time (s) | Overhead | Mode        | SGX |
| -------------------------- | -------------------------------------------------------------------------------------------------- | -------- | ----------- | -------- | ----------- | --- |
| 20250527\_123926\_a151e27c | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_123926_a151e27c) | 118.33   | 35.07       | 1.22     | spark       | Yes |
| 20250527\_124307\_3d55a8a5 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_124307_3d55a8a5) | 128.53   | 36.44       | 1.20     | weave       | Yes |
| 20250527\_124713\_46b5f094 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_124713_46b5f094) | 116.90   | 36.63       | 1.16     | sparksorted | Yes |
| 20250527\_125108\_274a628b | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_125108_274a628b) | 127.20   | 39.30       | 1.26     | weavesorted | Yes |
| 20250527\_125354\_cdfcc628 | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_125354_cdfcc628) | 120.80   | 42.47       | 1.42     | snb         | Yes |
| 20250527\_125724\_e7802e6a | [View Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_125724_e7802e6a) | 148.10   | 67.81       | 2.24     | columnsort  | Yes |

---

### Task 2 - Enron Email Dataset (Shuffle-Intensive Execution)

#### Purpose: Evaluating SGX Overhead for Shuffle-Heavy Workloads

This task evaluates SGX overhead under shuffle-intensive execution using the Enron Email dataset. We used 20% of the original data to stress the shuffle path while keeping resource usage within the bounds of a 2-node cluster.

This configuration mimics the execution pattern reflected in Figure 5.1 of the paper, enabling a fair comparison between linear systems (Spark and Weave, in both unsorted and sorted variants) and more complex systems like ColumnSort and SnB. The workload includes sorting and key-grouping operations across a realistic data volume.

* **Expected behavior:** ColumnSort shows **lower relative overhead** due to log-linear complexity and efficient batching. SnB is expected to **fail to complete** (DNF) because its padding-heavy algorithm is not suited to memory-constrained SGX environments.
* **Observed outcome:** As shown in the [plots](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_enron_spam_data_exploded.csv_full_summary.html), the SGX execution time overhead is approximately **3.5×**, lower than Task 1 since longer runtimes dilute SGX startup costs.

This aligns with expectations: the fixed enclave initialization cost becomes less significant in longer workloads. Systems like ColumnSort and SnB thus show more representative overheads than in lightweight tasks.

Visual inspection confirms these patterns. Hue and hatch styles are consistent across systems—Spark, SparkSorted, Weave, WeaveSorted, ColumnSort, and SnB.

[![Task 2 Overhead Plot](https://github.com/MattSlm/weave-artifacts/raw/main/images/task2_overheads.png)](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_enron_spam_data_exploded.csv_full_summary.html)

### Rerun Instructions (You can also check the data without rerunning --recommended--)

To rerun the experiments and reproduce the SGX overhead plots for the Enron dataset:

1. **Start the cluster in SGX mode** on `weave-master`:

```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/enron_spam_data_exploded.csv "Word" "Subject"
```

2- **Restart the cluster in Direct mode** on `weave-master`:
Then 
```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/enron_spam_data_exploded.csv "Word" "Subject"
```

#### Map to snapshot data 

Below are selected SGX and Direct trace records for task 2:

| UID                        | Trace Link                                                                                        | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------------- | ----------- | ----------- |
| 20250527\_184406\_2c6e6f03 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184406_2c6e6f03) | Spark       | 146.62      |
| 20250527\_184633\_b3d89194 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184633_b3d89194) | SparkSorted | 169.23      |
| 20250527\_184923\_02e0ddf8 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_184923_02e0ddf8) | Weave       | 154.07      |
| 20250527\_185158\_ac32bc70 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_185158_ac32bc70) | WeaveSorted | 157.54      |
| 20250527\_185436\_87710cc1 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_185436_87710cc1) | ColumnSort  | 534.46      |
| 20250527\_190331\_25f9a8e5 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_190331_25f9a8e5) | SnB         | DNF         |

### Trace Table: Direct Mode

| UID                        | Trace Link                                                                                              | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------------------- | ----------- | ----------- |
| 20250527\_212714\_999e53f3 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_212714_999e53f3) | Spark       | 35.35       |
| 20250527\_212749\_228194bb | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_212749_228194bb) | SparkSorted | 36.52       |
| 20250527\_212827\_34c53d48 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_212827_34c53d48) | Weave       | 43.03       |
| 20250527\_212910\_90125bf9 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_212910_90125bf9) | WeaveSorted | 46.63       |
| 20250527\_212957\_ce38846a | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_212957_ce38846a) | ColumnSort  | 153.51      |
| 20250527\_213232\_5664296f | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_213232_5664296f) | SnB         | DNF         |


### Task 3 - Yellow taxi dataset (NYTaxi)

#### Purpose: Evaluating SGX Overhead for Shuffle-Heavy Workloads

This task evaluates SGX overhead under shuffle-intensive execution using the NY Taxi dataset (2020). We used ~20% of the original data to stress the shuffle path while keeping resource usage within the bounds of a 2-node cluster.

This configuration mimics the execution pattern reflected in Figure 5.1 of the paper, enabling a fair comparison between linear systems (Spark and Weave, in both unsorted and sorted variants) and more complex systems like ColumnSort and SnB. The workload includes sorting and key-grouping operations across a realistic data volume.

* **Expected behavior:** The Number of input rows is much higher for this dataset, compared to Task 2. We expect longer running times, We expect Weave overhead to be close to 1x (0%) for shuffling. Since sampling creates very accurate distributions for the low cardinality data in the Key column and balances the loads between executors, which compensates for the time spent in histogram consolidation and the fake padding shuffling. We also expect the execution to be faster in SGX compared to the direct vs the SGX experiments of Task 2, i.e., lower SGX overheads are expected. 

* **Observed outcome:** As shown in the [plots](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_yellow_tripdata_2020.csv_full_summary.html), the SGX execution time overhead is roughly **2.3×**, lower than Task 2 since longer runtimes dilute SGX startup costs.

We can also see that the execution time overhead of ColumnSort increases, compared to Task 1 and Task 2. Mainly, because this dataset has more Map output rows, which complicates the sorting. 

This aligns with expectations: the fixed enclave initialization cost becomes less significant in longer workloads. Systems like ColumnSort and SnB thus show more representative overheads than in lightweight tasks.

Visual inspection confirms these patterns. Hue and hatch styles are consistent across systems—Spark, SparkSorted, Weave, WeaveSorted, ColumnSort, and SnB.

[![Task 3 Overheads Plot](https://github.com/MattSlm/weave-artifacts/raw/main/images/task3_overheads.png)](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_yellow_tripdata_2020.csv_full_summary.html)

### Rerun Instructions (You can also check the data without rerunning --recommended--)

To rerun the experiments and reproduce the SGX overhead plots for the Yellow Taxi dataset:

1. **Start the cluster in SGX mode** on `weave-master`:

```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/yellow_tripdata_2020.csv "PULocationID" "DOLocationID"
```

2- **Restart the cluster in Direct mode** on `weave-master`:
Then 
```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/yellow_tripdata_2020.csv "PULocationID" "DOLocationID"
```

#### Map to snapshot data 

Below are selected SGX and Direct trace records for task 3:

### Trace Table: SGX Mode

| UID                        | Trace Link                                                                                              | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------------------- | ----------- | ----------- 
| 20250527\_134932\_d15b2988 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_134932_d15b2988) | Spark | 206.38 |
| 20250527\_135259\_872b3042 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_135259_872b3042) | SparkSorted | 216.62 |
| 20250527\_135636\_b24e7275 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_135636_b24e7275) | Weave | 217.36 |
| 20250527\_140014\_3a98b933 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_140014_3a98b933) | WeaveSorted | 226.1 |
| 20250527\_140401\_c32ab899 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_140401_c32ab899) | ColumnSort | 937.76 |
| 20250527\_141939\_79884dd8 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/20250527_141939_79884dd8) | SnB | DNF |

### Trace Table: Direct Mode

| UID                        | Trace Link                                                                                              | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------------------- | ----------- | ----------- 
| 20250527\_203708\_d15b2988 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_203708_d15b2988) | Spark | 75.06 |
| 20250527\_203823\_872b3042 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_203823_872b3042) | SparkSorted | 82.73 |
| 20250527\_203947\_b24e7275 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_203947_b24e7275) | Weave | 90.13 |
| 20250527\_204117\_3a98b933 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_204117_3a98b933) | WeaveSorted | 97.52 |
| 20250527\_204255\_c32ab899 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_204255_c32ab899) | ColumnSort | 404.42 |
| 20250527\_204941\_79884dd8 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/20250527_204941_79884dd8) | SnB | DNF |


### Task 4 - Pokec Social Data (Page Rank Round 1)

#### Purpose: Evaluating SGX Overhead for Shuffle-Heavy Workloads

This task evaluates SGX overhead under shuffle-intensive execution using the Pokec Social Network Dataset. We used 100% of the original data to stress the shuffle path while keeping resource usage within the bounds of a 2-node cluster. Since this data has massive number of rows, but lower data size per row, the task succeeds on 2 nodes. 

This configuration mimics **the dataset size reflected in Figure 5.1 of the paper**, enabling a fair comparison **between all systems**. 

* **Expected behavior:** The Number of input rows is much higher for this dataset, compared to Task 1, and 2, and even 3. We expect longer running times, We expect Weave overhead to increase for shuffling. Since sampling creates more imbalanced distributions for the **high cardinality data** in the Src column. We also expect the execution to be faster in SGX compared to the direct vs the SGX experiments of Tasks 1, 2, and 3, i.e., lower SGX overheads are expected. 

* **Observed outcome:** As shown in the [plots](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_pokec-relations.csv_full_summary.html), the SGX execution time overhead is between **2.4×** to **3.2×**. In the same ballpark as task 3. 

We can also see that the execution time overhead of ColumnSort increases compared to Task 1, Task 2, and Task 3. Mainly, because this dataset has more Map output rows, which complicates the sorting. 

This aligns with expectations: for these scales of data, the log-linear overhead of ColumnSort starts to dominate the execution times and therefore the gap between the schemes increases. 

Visual inspection confirms these patterns. Hue and hatch styles are consistent across systems—Spark, SparkSorted, Weave, WeaveSorted, ColumnSort, and SnB.

[![Task 4 Overheads Plot](https://github.com/MattSlm/weave-artifacts/raw/main/images/task4_plots.png)](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_pokec-relations.csv_full_summary.html)


### Rerun Instructions (You can also check the data without rerunning --recommended--)

To rerun the experiments and reproduce the SGX overhead plots for the Pokec social network dataset:

1. **Start the cluster in SGX mode** on `weave-master`:

```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/pokec-relations.csv "src" "dst"
```

2- **Restart the cluster in Direct mode** on `weave-master`:
Then 
```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/pokec-relations.csv "src" "dst"
```

### Trace Table: SGX Mode

| UID                        | Trace Link                                                                                 | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------ | ----------- | ----------- |
| 20250527\_130133\_20d9c113 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250527_130133_20d9c113) | Spark       | 187.73      |
| 20250527\_130441\_b79073d1 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250527_130441_b79073d1) | SparkSorted | 203.03      |
| 20250527\_130804\_fa48a70e | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250527_130804_fa48a70e) | Weave       | 209.59      |
| 20250527\_131135\_ab3a36c7 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250527_131135_ab3a36c7) | WeaveSorted | 220.48      |
| 20250527\_131515\_1195cab2 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250527_131515_1195cab2) | ColumnSort  | 1084.86     |
| 20250527\_133321\_6bbcb0e4 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250527_133321_6bbcb0e4) | SnB         | DNF         |


##### Task 4 - Pokec Dataset (Direct Mode)

| UID                        | Trace Link                                                                                       | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------------ | ----------- | ----------- |
| 20250527\_195100\_20d9c113 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_195100_20d9c113) | Spark       | 58.23       |
| 20250527\_195159\_b79073d1 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_195159_b79073d1) | SparkSorted | 62.75       |
| 20250527\_195302\_fa48a70e | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_195302_fa48a70e) | Weave       | 72.93       |
| 20250527\_195415\_ab3a36c7 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_195415_ab3a36c7) | WeaveSorted | 93.33       |
| 20250527\_195549\_1195cab2 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_195549_1195cab2) | ColumnSort  | 461.96      |
| 20250527\_200332\_6bbcb0e4 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_200332_6bbcb0e4) | SnB         | DNF         |


### Task 5 – Yellow Taxi Dataset (5-Year Scalability Pressure Test on 2-Node Cluster)

#### Purpose: Evaluating SGX Overhead for Large-Scale Workloads

This **final** task measures SGX overhead in shuffle-intensive workloads using the full-scale **Yellow Taxi Dataset (5 years)**. We stress both **memory** and **compute** by using the entire dataset without sampling. This setup mimics the **dataset size from Figure 5.1 of the paper**, ensuring consistent scalability evaluation across all execution modes.

### Expectations

* This dataset contains a large number of input rows, leading to **longer runtimes**.
* SGX overhead should **decrease** relative to earlier tasks due to the amortization of enclave startup costs.
* ColumnSort is expected to run **slowest**, while **Weave overhead** is expected to remain **low**.
* The **low-cardinality** of `PULocationID` helps balance shuffles.
* Weave's efficiency should be evident through **lower overhead ratios** in SGX vs. non-SGX runs.

### Observations

As seen in the [summary plots](http://weave.eastus.cloudapp.azure.com:5555/plotting/extrapolate_experiment_full_summary/_opt_spark_enclave_data_yellow_tripdata_202%5C%2A_wy.csv_full_summary.html):

* SGX overhead ranges between **1.5× to 2.1×**.
* ColumnSort has a runtime overhead of **8.5×**, while Weave shows a much lower **1.13×** overhead.
* This confirms the reproducibility of results reported in Section 5.1 of the manuscript.
* Hue and hatch styles in plots consistently distinguish between systems: Spark, SparkSorted, Weave, WeaveSorted, ColumnSort, and SnB.

![Task 5 Overheads Plot](https://github.com/MattSlm/weave-artifacts/raw/main/images/task5_plots.png)

---

### Rerun Instructions (Optional – Logs Available for Verification)

To reproduce Task 5 results:

1. **Run in SGX Mode:**

```bash
SGX=1 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/yellow_tripdata_202\*_wy.csv "PULocationID" "DOLocationID"
```

2. **Run in Direct Mode:**

```bash
SGX=0 ./start_cluster.sh
./run_all_modes.sh /opt/spark/enclave/data/yellow_tripdata_202\*_wy.csv "PULocationID" "DOLocationID"
```

---

##### Task 5 - Yellow Taxi (Trace Summary - Direct Mode)

| UID                        | Trace Link                                                                                       | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------------ | ----------- | ----------- |
| 20250527\_232011\_c8b333a0 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_232011_c8b333a0) | Spark       | 221.54      |
| 20250527\_232354\_15c6c5c9 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_232354_15c6c5c9) | SparkSorted | 252.84      |
| 20250527\_232807\_e7a1e600 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_232807_e7a1e600) | Weave       | 302.49      |
| 20250527\_233310\_6d184e89 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_233310_6d184e89) | WeaveSorted | 344.06      |
| 20250527\_233855\_794b83f5 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250527_233855_794b83f5) | ColumnSort  | 2549.51     |
| 20250528\_002126\_4f61e266 | [Direct Trace](http://weave.eastus.cloudapp.azure.com:5555/direct_data/20250528_002126_4f61e266) | SnB         | DNF         |

##### Task 5 - Yellow Taxi (Trace Summary - SGX Mode)

| UID                        | Trace Link                                                                                 | Mode        | Runtime (s) |
| -------------------------- | ------------------------------------------------------------------------------------------ | ----------- | ----------- |
| 20250528\_101209\_c8b333a0 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250528_101209_c8b333a0) | Spark       | 434.78      |
| 20250528\_101925\_15c6c5c9 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250528_101925_15c6c5c9) | SparkSorted | 484.82      |
| 20250528\_102730\_e7a1e600 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250528_102730_e7a1e600) | Weave       | 499.1       |
| 20250528\_103550\_6d184e89 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250528_103550_6d184e89) | WeaveSorted | 545.77      |
| 20250528\_104456\_794b83f5 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250528_104456_794b83f5) | ColumnSort  | 4052.8      |
| 20250528\_115230\_4f61e266 | [SGX Trace](http://weave.eastus.cloudapp.azure.com:5555/sgx_data/20250528_115230_4f61e266) | SnB         | DNF         |


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


### Behavioral Consistency Across Modes

To measure the similarity of system performance between SGX and Direct execution modes, we computed the Wasserstein distance between the per-system overhead distributions. Weave consistently shows the smallest Wasserstein distance between its SGX and Direct mode overheads, indicating its behavior is most stable regardless of the execution environment. This metric, with a distance of **0.14**, supports the claim that Weave’s performance characteristics **remain consistent and predictable under SGX**.

### Time-Dependent SGX Overhead Trend

One notable trend is that SGX overhead sharply decreases with longer execution durations. Shorter jobs are disproportionately affected by the fixed costs associated with SGX, such as page fault handling, JVM initialization, and secure memory allocation. However, these overheads become negligible in larger workloads. On average, the SGX overhead converges toward a stable multiplier of **\~2x**, highlighting the practical scalability of enclave-based systems when amortized over time.


## Experiment 2: Reproduction of the shuffling overheads of all schemes in Figure 5.1 

### Shuffling Enron Email Dataset.

### Shuffling NY Taxi Dataset 

### Shuffling Pokec Dataset (First round of pagerank)

## Trace Snapshots

Snapshots of Spark UIs and performance metrics across execution rounds for each system and mode are available [here](http://weave.eastus.cloudapp.azure.com:5555/traces/), the data for SGX execution is under [sgx_data](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/), and for direct execution is under [direct_data](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/). These include executor timelines, SQL stages, task breakdowns, and GC metrics.

For any assistance or rerun request, please contact the experiment authors or refer to the reproduction scripts provided in the root directory.

