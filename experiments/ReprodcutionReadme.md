# SGX Experiment Summary

## Description

This README provides a comprehensive summary and analysis of the execution time overheads observed across various data processing systems (Spark, SparkSorted, Weave, WeaveSorted, SNB, ColumnSort) when running on SGX (Secure Enclave) versus Direct execution. The experiments were conducted on several datasets including:

* `yellow_tripdata_2020_wy.csv`
* `yellow_tripdata_20212025.csv`
* `enron_spam_data_exploded.csv`
* `enron_spam_data_cleaned.csv`
* `pokec-relations.csv`

Each system and execution mode combination was profiled for real execution time, user CPU time, and total runtime. This document includes numerical comparisons and overhead calculations for each dataset and system.

## Numerical Analysis

### Overall SGX Overhead Across All Systems

| Metric | Overhead |
| ------ | -------- |
| Min    | 1.59×    |
| Mean   | 3.20×    |
| Max    | 5.46×    |

### SGX Overhead (SGX/Direct) Per System

| System      | Min   | Mean  | Max   |
| ----------- | ----- | ----- | ----- |
| ColumnSort  | 1.59× | 2.65× | 3.50× |
| SNB         | 4.69× | 4.69× | 4.69× |
| Spark       | 1.96× | 3.35× | 4.68× |
| SparkSorted | 1.92× | 3.50× | 5.12× |
| Weave       | 1.65× | 3.19× | 5.41× |
| WeaveSorted | 1.59× | 3.02× | 5.46× |

### Execution Time Overhead (Direct Mode) vs Spark and Weave

| System      | vs Spark (Min / Mean / Max) | vs Weave (Min / Mean / Max) |
| ----------- | --------------------------- | --------------------------- |
| ColumnSort  | 1.68 / 6.17 / 11.51         | 1.78 / 4.92 / 8.43          |
| SNB         | 1.02 / 1.02 / 1.02          | 1.09 / 1.09 / 1.09          |
| Spark       | 1.00 / 1.00 / 1.00          | 0.73 / 0.85 / 1.06          |
| SparkSorted | 0.90 / 1.05 / 1.14          | 0.84 / 0.88 / 0.96          |
| Weave       | 0.94 / 1.20 / 1.37          | 1.00 / 1.00 / 1.00          |
| WeaveSorted | 0.92 / 1.34 / 1.60          | 0.98 / 1.11 / 1.28          |

## Availability

Reproducibility scripts, performance logs, and profiling outputs for both SGX and Direct execution are available. All logs are archived under `sgx_data/` and `direct_data/`, with plotting outputs organized per dataset in `plotting/`.

## Trace Snapshots

Snapshots of Spark UIs and performance metrics across execution rounds for each system and mode are available [here](http://weave.eastus.cloudapp.azure.com:5555/traces/, the data for SGX execution is under [sgx_data](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/), and for direct execution is under [direct_data](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/). These include executor timelines, SQL stages, task breakdowns, and GC metrics.

For any assistance or rerun request, please contact the experiment authors or refer to the reproduction scripts provided in the root directory.
