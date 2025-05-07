#!/usr/bin/env bash
set -euo pipefail

JAR_PATH="./fork-jars/ForkTestSuite.jar"
OUTPUT_DIR="./output-data"
CSV_FILE="$OUTPUT_DIR/fork_test_summary.csv"
THREAD_COUNTS=(8 16 32)
TEST_CASES=(1 2 3 4 5)

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.log "$OUTPUT_DIR"/*.txt "$OUTPUT_DIR"/*.csv

# Prepare CSV header
echo "test_case,num_threads,total_time_seconds,max_memory_kb,exit_code" > "$CSV_FILE"

for test_case in "${TEST_CASES[@]}"; do
    for num_threads in "${THREAD_COUNTS[@]}"; do

        echo "🚀 Running test $test_case with $num_threads threads..."

        LOG_FILE="$OUTPUT_DIR/test${test_case}_threads${num_threads}.log"
        TIME_FILE="$OUTPUT_DIR/test${test_case}_threads${num_threads}_time.txt"

        # Run the Java program and measure time/memory
        ( /usr/bin/time -v java -cp "$JAR_PATH" ForkTestSuite "$test_case" "$num_threads" \
            > "$LOG_FILE" 2> "$TIME_FILE" ) || true  # Always continue even if test fails

        # Initialize fallback values
        total_seconds=0
        max_mem=0
        exit_code=0

        # Parse timing and memory safely
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

        # Detect if the log indicates success or failure
        if grep -q "✅" "$LOG_FILE"; then
            exit_code=0
        else
            exit_code=1
        fi

        # Append results to CSV
        echo "$test_case,$num_threads,$total_seconds,$max_mem,$exit_code" >> "$CSV_FILE"

    done
done

echo "✅ All tests completed. Results saved in $CSV_FILE and $OUTPUT_DIR/"

