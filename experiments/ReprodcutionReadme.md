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

### Overall SGX/Direct Overhead (Real Time)
- Minimum: **1.59×**
- Average: **3.2×**
- Maximum: **5.46×**
- Weighted Average: **2130.68×**

### Overall SGX/Direct Overhead (Real Time)
- Minimum: **1.59×**
- Average: **3.2×**
- Maximum: **5.46×**
- Weighted Average: **2130.68×**

### SGX/Direct Overhead Per System
| mode        |   avg_overhead |   min_overhead |   max_overhead |
|:------------|---------------:|---------------:|---------------:|
| columnsort  |           2.65 |           1.59 |           3.5  |
| snb         |           4.69 |           4.69 |           4.69 |
| spark       |           3.35 |           1.96 |           4.68 |
| sparksorted |           3.5  |           1.92 |           5.12 |
| weave       |           3.19 |           1.65 |           5.41 |
| weavesorted |           3.02 |           1.59 |           5.46 |

### SGX/Direct Overhead Per Input and System
| input_data                                           |   columnsort |    snb |   spark |   sparksorted |   weave |   weavesorted |
|:-----------------------------------------------------|-------------:|-------:|--------:|--------------:|--------:|--------------:|
| enron_spam_data_cleaned.csv  |         3.5  |   4.69 |    4.68 |          5.12 |    5.41 |          5.46 |
| enron_spam_data_exploded.csv |         3.48 | nan    |    4.15 |          4.63 |    3.58 |          3.38 |
| pokec-relations.csv          |         2.35 | nan    |    3.22 |          3.24 |    2.87 |          2.36 |
| yellow_tripdata_2020.csv     |         2.32 | nan    |    2.75 |          2.62 |    2.41 |          2.32 |
| yellow_tripdata_202\*_wy.csv |         1.59 | nan    |    1.96 |          1.92 |    1.65 |          1.59 |

### Overhead Compared to Spark (Direct)
| input_data                                           | mode        |   overhead_vs_spark |
|:-----------------------------------------------------|:------------|--------------------:|
| enron_spam_data_cleaned.csv  | spark       |                1    |
| enron_spam_data_cleaned.csv  | sparksorted |                0.9  |
| enron_spam_data_cleaned.csv  | weave       |                0.94 |
| enron_spam_data_cleaned.csv  | weavesorted |                0.92 |
| enron_spam_data_cleaned.csv  | columnsort  |                1.68 |
| enron_spam_data_cleaned.csv  | snb         |                1.02 |
| pokec-relations.csv          | spark       |                1    |
| pokec-relations.csv          | sparksorted |                1.08 |
| pokec-relations.csv          | weave       |                1.25 |
| pokec-relations.csv          | weavesorted |                1.6  |
| pokec-relations.csv          | columnsort  |                7.93 |
| pokec-relations.csv          | snb         |              nan    |
| yellow_tripdata_2020.csv     | spark       |                1    |
| yellow_tripdata_2020.csv     | sparksorted |                1.1  |
| yellow_tripdata_2020.csv     | weave       |                1.2  |
| yellow_tripdata_2020.csv     | weavesorted |                1.3  |
| yellow_tripdata_2020.csv     | columnsort  |                5.39 |
| yellow_tripdata_2020.csv     | snb         |              nan    |
| enron_spam_data_exploded.csv | spark       |                1    |
| enron_spam_data_exploded.csv | sparksorted |                1.03 |
| enron_spam_data_exploded.csv | weave       |                1.22 |
| enron_spam_data_exploded.csv | weavesorted |                1.32 |
| enron_spam_data_exploded.csv | columnsort  |                4.34 |
| enron_spam_data_exploded.csv | snb         |              nan    |
| yellow_tripdata_202\*_wy.csv | spark       |                1    |
| yellow_tripdata_202\*_wy.csv | sparksorted |                1.14 |
| yellow_tripdata_202\*_wy.csv | weave       |                1.37 |
| yellow_tripdata_202\*_wy.csv | weavesorted |                1.55 |
| yellow_tripdata_202\*_wy.csv | columnsort  |               11.51 |
| yellow_tripdata_202\*_wy.csv | snb         |              nan    |

### Overhead Compared to Weave (Direct)
| input_data                                           | mode        |   overhead_vs_weave |
|:-----------------------------------------------------|:------------|--------------------:|
| enron_spam_data_cleaned.csv  | spark       |                1.06 |
| enron_spam_data_cleaned.csv  | sparksorted |                0.96 |
| enron_spam_data_cleaned.csv  | weave       |                1    |
| enron_spam_data_cleaned.csv  | weavesorted |                0.98 |
| enron_spam_data_cleaned.csv  | columnsort  |                1.78 |
| enron_spam_data_cleaned.csv  | snb         |                1.09 |
| pokec-relations.csv          | spark       |                0.8  |
| pokec-relations.csv          | sparksorted |                0.86 |
| pokec-relations.csv          | weave       |                1    |
| pokec-relations.csv          | weavesorted |                1.28 |
| pokec-relations.csv          | columnsort  |                6.33 |
| pokec-relations.csv          | snb         |              nan    |
| yellow_tripdata_2020.csv     | spark       |                0.83 |
| yellow_tripdata_2020.csv     | sparksorted |                0.92 |
| yellow_tripdata_2020.csv     | weave       |                1    |
| yellow_tripdata_2020.csv     | weavesorted |                1.08 |
| yellow_tripdata_2020.csv     | columnsort  |                4.49 |
| yellow_tripdata_2020.csv     | snb         |              nan    |
| enron_spam_data_exploded.csv | spark       |                0.82 |
| enron_spam_data_exploded.csv | sparksorted |                0.85 |
| enron_spam_data_exploded.csv | weave       |                1    |
| enron_spam_data_exploded.csv | weavesorted |                1.08 |
| enron_spam_data_exploded.csv | columnsort  |                3.57 |
| enron_spam_data_exploded.csv | snb         |              nan    |
| yellow_tripdata_202\*_wy.csv | spark       |                0.73 |
| yellow_tripdata_202\*_wy.csv | sparksorted |                0.84 |
| yellow_tripdata_202\*_wy.csv | weave       |                1    |
| yellow_tripdata_202\*_wy.csv | weavesorted |                1.14 |
| yellow_tripdata_202\*_wy.csv | columnsort  |                8.43 |
| yellow_tripdata_202\*_wy.csv | snb         |              nan    |

Reproducibility scripts, performance logs, and profiling outputs for both SGX and Direct execution are available. All logs are archived under `sgx_data/` and `direct_data/`, with plotting outputs organized per dataset in `plotting/`.

## Trace Snapshots

Snapshots of Spark UIs and performance metrics across execution rounds for each system and mode are available [here](http://weave.eastus.cloudapp.azure.com:5555/traces/), the data for SGX execution is under [sgx_data](http://weave.eastus.cloudapp.azure.com:5555/traces/sgx_data/), and for direct execution is under [direct_data](http://weave.eastus.cloudapp.azure.com:5555/traces/direct_data/). These include executor timelines, SQL stages, task breakdowns, and GC metrics.

For any assistance or rerun request, please contact the experiment authors or refer to the reproduction scripts provided in the root directory.
