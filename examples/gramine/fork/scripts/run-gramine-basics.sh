#!/usr/bin/env bash
set -euo pipefail

JAR_PATH="./fork-jars/ForkTestSuite.jar"
OUTPUT_DIR="./output-data/gramine-basic"
CSV_FILE="$OUTPUT_DIR/gramine_basic_summary.csv"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.log "$OUTPUT_DIR"/*.txt "$OUTPUT_DIR"/*.csv

# Configurations to test
GC_FLAGS=(
    "-XX:+UseG1GC"
    "-XX:+UseParallelGC"
)
HEAP_SIZES=(
    "-Xmx512M"
    "-Xmx1G"
)
TEST_CASE=1   # Lightest test: Thread Pool Stress
NUM_THREADS=8 # Small number of threads to start

# CSV header
echo "gc_type,heap_size_mb,total_time_seconds,max_memory_kb,exit_code" > "$CSV_FILE"

for gc_flag in "${GC_FLAGS[@]}"; do
    for heap_size in "${HEAP_SIZES[@]}"; do

        gc_name=$(echo "$gc_flag" | sed 's/[-+:]//g')
        heap_value=$(echo "$heap_size" | tr -dc '0-9')

        echo "🚀 Running Gramine with GC=$gc_name Heap=$heap_value MB..."

        LOG_FILE="$OUTPUT_DIR/test_gc${gc_name}_heap${heap_value}.log"
        TIME_FILE="$OUTPUT_DIR/test_gc${gc_name}_heap${heap_value}_time.txt"

        # Build Gramine manifest (assuming already exists) and run
        { /usr/bin/time -v -o "$TIME_FILE" gramine-sgx bash -c "java $gc_flag $heap_size -cp $JAR_PATH ForkTestSuite $TEST_CASE $NUM_THREADS" > "$LOG_FILE"; } || true
        exit_code=$?

        total_seconds=0
        max_mem=0

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

        echo "$gc_name,$heap_value,$total_seconds,$max_mem,$exit_code" >> "$CSV_FILE"

    done
done

echo "✅ Basic Gramine testing completed. Results saved in $CSV_FILE and $OUTPUT_DIR/"

