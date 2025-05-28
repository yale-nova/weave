# SGX Experiment Summary

## Description

This README provides a comprehensive summary and analysis of the execution time overheads observed across various data processing systems (Spark, SparkSorted, Weave, WeaveSorted, SNB, ColumnSort) when running on SGX (Secure Enclave) versus Direct execution. The experiments were conducted on several datasets, including:

* `yellow_tripdata_2020_wy.csv`
* `yellow_tripdata_20212025.csv`
* `enron_spam_data_exploded.csv`
* `enron_spam_data_cleaned.csv`
* `pokec-relations.csv`

Each system and execution mode combination was profiled for real execution time, user CPU time, and total runtime. This document includes numerical comparisons and overhead calculations for each dataset and system.


## Setup 

## Setup

**Master node:** One Azure D3s VM (4 cores, 8 GB memory)  
**Worker nodes:** Two Azure DC3s VMs (8 cores, 16 GB memory) with EMM-enabled SGXv2 (EPC support)

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

3- Weave does have two manifests, java.manifest.template available at [the config snapshot](http://weave.eastus.cloudapp.azure.com:5555/config_snapshot/), which configures the PAL loader for Gramine  direct mode (Syscall proxying only), and a SGX manifest, also available at [the config snapshot](http://weave.eastus.cloudapp.azure.com:5555/config_snapshot/), java.manifest.sgx-template, which is used when SGX is available on the machine. 


> **Note:** Some systems may flag these logs due to their file naming format. They are safe to open—use a text editor like Vim for best results.




 
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

