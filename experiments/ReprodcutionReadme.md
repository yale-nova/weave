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


### How to run a simple job?  (Time: less than <10 mins)
We have provided the full trace of both SGX, and direct experiments on this two-node cluster [online](http://weave.eastus.cloudapp.azure.com:5555/traces/). Feel free to skip this step, as it is similar to our demo. 

We use a script named "./run_spark_job_task_logging.sh" to run a Spark job on this cluster and collect all required metrics. 
A call to that function looks like this 

./run_spark_job_task_logging.sh   --conf spark.executor.memory=6g   --conf spark.executor.gramine.enabled=true   --conf spark.driver.host=10.0.0.5   --conf spark.driver.port=35339   --conf "spark.executor.extraJavaOptions=-Dscratch.dir=/opt/spark/enclave/data/scratch -Dweave.scratch.container=weave-scratch -Dweave.scratch.storage=sparkstorage32271"   --conf "spark.driver.extraJavaOptions=-Dscratch.dir=/opt/spark/enclave/data/scratch -Dweave.scratch.container=weave-scratch -Dweave.scratch.storage=sparkstorage32271 -Dlog4j.debug -Dlog4j.configuration=file:/opt/spark/conf/log4j.properties"   --conf "spark.hadoop.fs.azure.account.auth.type.sparkstorage32271.dfs.core.windows.net=SharedKey"   --conf "spark.hadoop.fs.azure.account.key.sparkstorage32271.dfs.core.windows.net=(??????)"   --deploy-mode client   --class org.apache.spark.shuffle.examples.SparkChunkedShuffleApp   /opt/spark/jars/spark-weave-shuffle_2.12-0.1.0.jar   "/opt/spark/enclave/data/enron_spam_data_cleaned.csv"   weave   --key_cols Date   --value_cols "Message ID" > snb_out.txt 2>&1

This command shuffles the raw Enron dataset, with its Date column as key and its "Message ID" column as value. 


Note, we have hidden the storage key in the command above. You can check the same functionality using  run_weave.sh in /home/azureuser/workspace/scripts. Which has this configuration inside. 

For a modest job that exists quickly and saves time, you can use the same Enron job as above and call.


root@weave-master:/home/azureuser/workspace/scripts# ./run_weave.sh /opt/spark/enclave/data/enron_spam_data_cleaned.csv "Date" "Message ID"

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

Our run for this, available at http://weave.eastus.cloudapp.azure.com:8888/, took 4.2 minutes in total. 2.1 mins for Spark, and 1.9 mins for Weave. Sample task outputs are like below 

root@weave-master:/home/azureuser/workspace/scripts# cat task_out_weave.txt 

📁 Saving results to: sgx_results/20250528_180945_83e98955
pass through: org.apache.spark.shuffle.examples.SparkChunkedShuffleApp
pass through: weave
pass through: --key_cols
pass through: Date
pass through: --value_cols
pass through: Message ID
🔧 Detected exec_scheme: SGX
🚀 Running Spark job...
📦 Task: --conf spark.executor.memory=6g --conf spark.executor.gramine.enabled=true --conf spark.driver.host=10.0.0.5 --conf spark.driver.port=35339 --conf spark.executor.extraJavaOptions=-Dscratch.dir=/opt/spark/enclave/data -Dweave.scratch.container=weave-scratch -Dweave.scratch.storage=sparkstorage32271 --conf spark.driver.extraJavaOptions=-Dscratch.dir=/opt/spark/enclave/data -Dlog4j.debug -Dlog4j.configuration=file:/opt/spark/conf/log4j.properties -Dweave.scratch.container=weave-scratch -Dweave.scratch.storage=sparkstorage32271 --conf spark.hadoop.fs.azure.account.auth.type.sparkstorage32271.dfs.core.windows.net=SharedKey --conf spark.hadoop.fs.azure.account.key.sparkstorage32271.dfs.core.windows.net=Private --deploy-mode client --class org.apache.spark.shuffle.examples.SparkChunkedShuffleApp /opt/spark/jars/spark-weave-shuffle_2.12-0.1.0.jar /opt/spark/enclave/data/enron_spam_data_cleaned.csv weave --key_cols Date --value_cols Message ID
🕒 Started at: 2025-05-28 18:09:45
real,129.43
user,38.29
sys,1.26

✅ Spark job completed in 129 seconds
🔍 Parsing Spark logs...
✅ All CSVs generated!

📦 Artifacts saved to: sgx_results/20250528_180945_83e98955
🧾 Log files: output.log, output.err
📄 Time CSV: sgx_results/20250528_180945_83e98955/time_metrics.csv
🧠 Metadata: sgx_results/20250528_180945_83e98955/metadata.json

The runner script automatically generates the full trace under the directory sgx_results. 

We have shared all created files for direct extrapolation experiments at http://weave.eastus.cloudapp.azure.com:5555/traces/direcct_data/, and sgx extrapolation experiments at http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/. 

Moreover, for all of the experiments that we share here, we have captured a static snapshot of Spark UI at http://weave.eastus.cloudapp.azure.com:5555/webuis/ 

You can find the Spark WebUI for SGX extrapolation specifically at http://weave.eastus.cloudapp.azure.com:5555/webuis/sgx_webui_snapshot/ for direct results on the same two nodes used for extrapolation at http://weave.eastus.cloudapp.azure.com:5555/webuis/direct_webui_snapshot/



### Scripts we provide for independent reproduction of our results 

## Numerical Analysis

### Overall SGX Overhead Across All Systems

### Overall SGX/Direct Overhead (Real Time)
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

