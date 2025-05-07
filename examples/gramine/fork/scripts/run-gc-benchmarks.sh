#!/usr/bin/env bash
set -euo pipefail

JAR_PATH="./fork-jars/ForkTestSuite.jar"
OUTPUT_DIR="./output-data/gc-benchmarks"
CSV_FILE="$OUTPUT_DIR/gc_benchmark_summary.csv"
THREAD_COUNTS=(16 32)
GC_FLAGS=(
    "-XX:+UseG1GC"
    "-XX:+UseParallelGC"
    "-XX:+UnlockExperimentalVMOptions -XX:+UseZGC"
)
TEST_CASE=4

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.log "$OUTPUT_DIR"/*.txt "$OUTPUT_DIR"/*.csv

# CSV header
echo "gc_type,num_threads,total_time_seconds,max_memory_kb,cpu_usage_percent,major_page_faults,minor_page_faults,exit_code" > "$CSV_FILE"

for gc_flag in "${GC_FLAGS[@]}"; do
    for num_threads in "${THREAD_COUNTS[@]}"; do

        gc_name=$(echo "$gc_flag" | sed 's/[-+:]//g')

        echo "🚀 Running test case $TEST_CASE with $num_threads threads under $gc_name..."

        LOG_FILE="$OUTPUT_DIR/test${TEST_CASE}_${gc_name}_${num_threads}threads.log"
        TIME_FILE="$OUTPUT_DIR/test${TEST_CASE}_${gc_name}_${num_threads}threads_time.txt"

        { /usr/bin/time -v -o "$TIME_FILE" java $gc_flag -cp "$JAR_PATH" ForkTestSuite "$TEST_CASE" "$num_threads" > "$LOG_FILE"; } || true
        exit_code=$?

        total_seconds=0
        max_mem=0
        cpu_usage=0
        major_pf=0
        minor_pf=0

        if grep -q "Elapsed (wall clock) time" "$TIME_FILE"; then
            total_time=$(grep "Elapsed (wall clock) time" "$TIME_FILE" | awk '{print $8}')
            if [[ "$total_time" == *":"* ]]; then
                min=$(echo "$total_time" | cut -d':' -f1)
                sec=$(echo "$total_time" | cut -d':' -f2)
                total_seconds=$(echo "$min*60 + $sec" | bc)
            else
                total_seconds="$total_time"
            fi
        fi

        if grep -q "Maximum resident set size" "$TIME_FILE"; then
            max_mem=$(grep "Maximum resident set size" "$TIME_FILE" | awk '{print $6}')
        fi

        if grep -q "Percent of CPU this job got" "$TIME_FILE"; then
            cpu_usage=$(grep "Percent of CPU this job got" "$TIME_FILE" | awk '{print $8}' | tr -d '%')
        fi

        if grep -q "Major (requiring I/O) page faults" "$TIME_FILE"; then
            major_pf=$(grep "Major (requiring I/O) page faults" "$TIME_FILE" | awk '{print $6}')
        fi

        if grep -q "Minor (reclaiming a frame) page faults" "$TIME_FILE"; then
            minor_pf=$(grep "Minor (reclaiming a frame) page faults" "$TIME_FILE" | awk '{print $7}')
        fi

        echo "$gc_name,$num_threads,$total_seconds,$max_mem,$cpu_usage,$major_pf,$minor_pf,$exit_code" >> "$CSV_FILE"

    done
done

echo "✅ GC Benchmarking completed. Results in $CSV_FILE and $OUTPUT_DIR/"

