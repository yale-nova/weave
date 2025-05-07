#!/usr/bin/env bash
set -euo pipefail

# === Setup ===
JAR_PATH="./fork-jars/ForkTestSuite.jar"
SCALA_HELLO_PATH="../scala/jars/HelloWorld.jar"
SCALA_HELLO_DIR="../scala"
OUTPUT_DIR="./output-data/full-gc-benchmark"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_CSV="$OUTPUT_DIR/full_gc_benchmark_summary_${TIMESTAMP}.csv"
BASELINE_CSV="$OUTPUT_DIR/baseline_metrics_${TIMESTAMP}.csv"

mkdir -p "$OUTPUT_DIR"

# Decide Gramine mode
GRAMINE_CMD="gramine-direct"
if [[ "${SGX:-0}" == "1" ]]; then
    GRAMINE_CMD="gramine-sgx"
fi

GC_FLAGS=(
    "-XX:+UseG1GC"
    "-XX:+UseParallelGC"
    "-XX:+UseConcMarkSweepGC"
    "-XX:+UnlockExperimentalVMOptions -XX:+UseZGC"
    "-XX:+UnlockExperimentalVMOptions -XX:+UseShenandoahGC"
)
HEAP_SIZES=(
    "-Xmx512M"
    "-Xmx1G"
    "-Xmx2G"
    "-Xmx4G"
)
TEST_CASES=(1 2 3)
NUM_THREADS=(4 8 16 32 48 64 96 128)

# === Step 1: Measure Gramine HelloWorld baseline metrics ===
BASELINE_RUNS=5
declare -A metric_sums
declare -A metric_sumsq
metrics=("elapsed_time_sec" "user_time_sec" "system_time_sec" "cpu_percent" "max_memory_kb" "major_page_faults" "minor_page_faults" "voluntary_ctxt_switches" "involuntary_ctxt_switches")

for m in "${metrics[@]}"; do
    metric_sums["$m"]=0
    metric_sumsq["$m"]=0
done

function safe_extract() {
    grep "$1" "$2" | cut -d':' -f2 | tr -d ' %' | xargs || echo "0"
}

echo "⏳ Measuring Gramine HelloWorld baseline with full metrics..."

for i in $(seq 1 $BASELINE_RUNS); do
    TIME_FILE="$OUTPUT_DIR/baseline_hello_${i}.txt"

    if [[ ! -f "$TIME_FILE" ]]; then
        ( cd "$SCALA_HELLO_DIR" && /usr/bin/time -v -o "../fork/$TIME_FILE" $GRAMINE_CMD java -Xmx512M -jar "./jars/HelloWorld.jar" > /dev/null ) || true
    fi

    elapsed=$(grep "Elapsed (wall clock) time" "$TIME_FILE" | awk '{print $8}' || echo "0")
    if [[ "$elapsed" == *":"* ]]; then
        min=$(echo "$elapsed" | cut -d':' -f1)
        sec=$(echo "$elapsed" | cut -d':' -f2)
        elapsed_time=$(echo "$min*60 + $sec" | bc)
    else
        elapsed_time="$elapsed"
    fi

    declare -A current_metrics=(
        [elapsed_time_sec]="$elapsed_time"
        [user_time_sec]="$(safe_extract "User time (seconds)" "$TIME_FILE")"
        [system_time_sec]="$(safe_extract "System time (seconds)" "$TIME_FILE")"
        [cpu_percent]="$(safe_extract "Percent of CPU" "$TIME_FILE")"
        [max_memory_kb]="$(safe_extract "Maximum resident set size" "$TIME_FILE")"
        [major_page_faults]="$(safe_extract "Major (requiring I/O) page faults" "$TIME_FILE")"
        [minor_page_faults]="$(safe_extract "Minor (reclaiming a frame) page faults" "$TIME_FILE")"
        [voluntary_ctxt_switches]="$(safe_extract "Voluntary context switches" "$TIME_FILE")"
        [involuntary_ctxt_switches]="$(safe_extract "Involuntary context switches" "$TIME_FILE")"
    )

    for m in "${metrics[@]}"; do
        val=${current_metrics["$m"]:-0}
        metric_sums["$m"]=$(echo "${metric_sums["$m"]} + $val" | bc)
        metric_sumsq["$m"]=$(echo "${metric_sumsq["$m"]} + ($val * $val)" | bc)
    done

done

# Save baseline_metrics.csv
echo "metric,mean,stddev" > "$BASELINE_CSV"
for m in "${metrics[@]}"; do
    mean=$(echo "scale=6; ${metric_sums["$m"]} / $BASELINE_RUNS" | bc)
    sqmean=$(echo "scale=6; ${metric_sumsq["$m"]} / $BASELINE_RUNS" | bc)
    variance=$(echo "scale=6; $sqmean - ($mean * $mean)" | bc || echo "0")
    if (( $(echo "$variance < 0" | bc -l) )); then
        variance="0"
    fi
    stddev=$(echo "scale=6; sqrt($variance)" | bc -l)

    echo "$m,$mean,$stddev" >> "$BASELINE_CSV"

    if [[ "$m" == "elapsed_time_sec" ]]; then
        BASELINE_ELAPSED="$mean"
    fi

done

echo "✅ Baseline metrics saved in $BASELINE_CSV"
echo "✅ Baseline mean elapsed time: $BASELINE_ELAPSED sec"

# === Step 2: Run ForkTestSuite natively and under Gramine ===
echo "test_case,num_threads,gc_type,heap_size_mb,"\
"native_user_time_sec,native_system_time_sec,native_cpu_percent,native_elapsed_time_sec,"\
"native_max_mem_kb,native_major_pf,native_minor_pf,native_vol_ctxt,native_invol_ctxt,"\
"gramine_user_time_sec,gramine_system_time_sec,gramine_cpu_percent,gramine_elapsed_time_sec,"\
"gramine_adj_elapsed_sec,gramine_max_mem_kb,gramine_major_pf,gramine_minor_pf,gramine_vol_ctxt,gramine_invol_ctxt,"\
"exit_code_native,exit_code_gramine" > "$SUMMARY_CSV"

function parse_metrics() {
    local file="$1"

    elapsed=$(grep "Elapsed (wall clock) time" "$file" | awk '{print $8}' || echo "0")
    if [[ "$elapsed" == *":"* ]]; then
        min=$(echo "$elapsed" | cut -d':' -f1)
        sec=$(echo "$elapsed" | cut -d':' -f2)
        elapsed=$(echo "$min*60 + $sec" | bc)
    fi

    user_time=$(safe_extract "User time (seconds)" "$file")
    system_time=$(safe_extract "System time (seconds)" "$file")
    cpu_percent=$(safe_extract "Percent of CPU" "$file")
    max_mem=$(safe_extract "Maximum resident set size" "$file")
    major_pf=$(safe_extract "Major (requiring I/O) page faults" "$file")
    minor_pf=$(safe_extract "Minor (reclaiming a frame) page faults" "$file")
    vol_ctxt=$(safe_extract "Voluntary context switches" "$file")
    invol_ctxt=$(safe_extract "Involuntary context switches" "$file")

    echo "$user_time,$system_time,$cpu_percent,$elapsed,$max_mem,$major_pf,$minor_pf,$vol_ctxt,$invol_ctxt"
}

for test_case in "${TEST_CASES[@]}"; do
for threads in "${NUM_THREADS[@]}"; do
for gc_flag in "${GC_FLAGS[@]}"; do
for heap_size in "${HEAP_SIZES[@]}"; do

    gc_name=$(echo "$gc_flag" | sed 's/[-+: ]/_/g')
    heap_value=$(echo "$heap_size" | tr -dc '0-9')

    echo "🚀 Running Test=$test_case Threads=$threads GC=$gc_name Heap=${heap_value}MB..."

    NATIVE_TIME_FILE="$OUTPUT_DIR/native_gc${gc_name}_heap${heap_value}_test${test_case}_threads${threads}.txt"
    GRAMINE_TIME_FILE="$OUTPUT_DIR/gramine_gc${gc_name}_heap${heap_value}_test${test_case}_threads${threads}.txt"

    if [[ ! -f "$NATIVE_TIME_FILE" ]]; then
        { /usr/bin/time -v -o "$NATIVE_TIME_FILE" java $gc_flag $heap_size -jar "$JAR_PATH" "$test_case" "$threads" > /dev/null; } || true
    fi
    native_exit=$?

    if [[ ! -f "$GRAMINE_TIME_FILE" ]]; then
        { /usr/bin/time -v -o "$GRAMINE_TIME_FILE" $GRAMINE_CMD java $gc_flag $heap_size -jar "$JAR_PATH" "$test_case" "$threads" > /dev/null; } || true
    fi
    gramine_exit=$?

    native_metrics=$(parse_metrics "$NATIVE_TIME_FILE")
    gramine_metrics=$(parse_metrics "$GRAMINE_TIME_FILE")

    gramine_elapsed=$(echo "$gramine_metrics" | cut -d',' -f4)
    gramine_adj_elapsed=$(echo "$gramine_elapsed - $BASELINE_ELAPSED" | bc)

    echo "$test_case,$threads,$gc_name,$heap_value,"$native_metrics","$gramine_metrics","$gramine_adj_elapsed",$native_exit,$gramine_exit" >> "$SUMMARY_CSV"


done
done
done
done

echo "✅ Full GC benchmarking completed!"
echo "  - Summary CSV saved at: $SUMMARY_CSV"
echo "  - Baseline metrics saved at: $BASELINE_CSV"
