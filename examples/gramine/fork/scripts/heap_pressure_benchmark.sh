#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
NATIVE_CMD="java"
GRAMINE_CMD="gramine-direct java"
JAR_PATH="./fork-jars/ForkTestSuite.jar"
TEST_ID=4  # Only test 4 (Memory & GC Stress)
THREADS=8  # Number of threads to use per test
OUTDIR="./output-data/heap-pressure-benchmark"

# GC configurations to test
GC_TYPES=(
  "-XX:+UseG1GC"
  "-XX:+UseParallelGC"
  "-XX:+UseConcMarkSweepGC"
  "-XX:+UnlockExperimentalVMOptions -XX:+UseZGC"
  "-XX:+UnlockExperimentalVMOptions -XX:+UseShenandoahGC"
)

# Heap sizes to test (in MB)
HEAP_SIZES_MB=(8192 6144 4096 3072 2048 1536 1024 768 512 256)

mkdir -p "$OUTDIR"

SUMMARY_CSV="$OUTDIR/heap_pressure_summary.csv"
echo "gc_type,heap_size_mb,mode,user_time_sec,system_time_sec,cpu_percent,elapsed_time_sec,max_mem_kb,major_pf,minor_pf,vol_ctxt,invol_ctxt,exit_code" > "$SUMMARY_CSV"

run_single_test() {
  local mode=$1  # native or gramine
  local gc_flags=$2
  local heap_mb=$3

  local heap_opt="-Xmx${heap_mb}M"

  local out_prefix="$OUTDIR/${mode}_gc_${gc_flags// /_}_heap${heap_mb}"

  if [[ "$mode" == "native" ]]; then
    RUN_CMD="$NATIVE_CMD"
  else
    RUN_CMD="$GRAMINE_CMD"
  fi

  # If output already exists, skip
  if [[ -f "${out_prefix}_time.txt" ]]; then
    echo "⚡ Skipping $mode $gc_flags $heap_mb MB — already exists."
    return
  fi

  echo "🚀 Running $mode GC=$gc_flags Heap=${heap_mb}MB..."

  /usr/bin/time -v -o "${out_prefix}_time.txt" \
    $RUN_CMD $gc_flags $heap_opt -cp "$JAR_PATH" ForkTestSuite "$TEST_ID" "$THREADS" || true
}

parse_time_output() {
  local file=$1
  local mode=$2
  local gc_type=$3
  local heap_size_mb=$4

  if [[ ! -f "$file" ]]; then
    echo "⚠️ Missing $file"
    return
  fi

  local user_time system_time elapsed_time cpu_percent max_mem major_pf minor_pf vol_ctxt invol_ctxt exit_code

  user_time=$(grep "User time (seconds)" "$file" | awk '{print $5}')
  system_time=$(grep "System time (seconds)" "$file" | awk '{print $5}')
  elapsed_time=$(grep "Elapsed (wall clock) time" "$file" | awk '{print $8}')
  cpu_percent=$(grep "Percent of CPU this job got" "$file" | awk '{print $8}' | tr -d '%')
  max_mem=$(grep "Maximum resident set size" "$file" | awk '{print $6}')
  major_pf=$(grep "Major (requiring I/O) page faults" "$file" | awk '{print $7}')
  minor_pf=$(grep "Minor (reclaiming a frame) page faults" "$file" | awk '{print $7}')
  vol_ctxt=$(grep "Voluntary context switches" "$file" | awk '{print $5}')
  invol_ctxt=$(grep "Involuntary context switches" "$file" | awk '{print $5}')
  exit_code=$(grep "Exit status" "$file" | awk '{print $3}')

  # Handle weird cases
  if [[ -z "$cpu_percent" ]]; then cpu_percent=0; fi

  # Convert elapsed time to seconds
  if [[ "$elapsed_time" == *":"* ]]; then
    IFS=':' read -r min sec <<< "$elapsed_time"
    elapsed_time=$(echo "$min*60 + $sec" | bc)
  fi

  echo "$gc_type,$heap_size_mb,$mode,$user_time,$system_time,$cpu_percent,$elapsed_time,$max_mem,$major_pf,$minor_pf,$vol_ctxt,$invol_ctxt,$exit_code" >> "$SUMMARY_CSV"
}

# === Main Execution ===
for gc_flags in "${GC_TYPES[@]}"; do
  for heap_mb in "${HEAP_SIZES_MB[@]}"; do
    run_single_test native "$gc_flags" "$heap_mb"
    run_single_test gramine "$gc_flags" "$heap_mb"
  done

  for heap_mb in "${HEAP_SIZES_MB[@]}"; do
    parse_time_output "$OUTDIR/native_gc_${gc_flags// /_}_heap${heap_mb}_time.txt" native "$gc_flags" "$heap_mb"
    parse_time_output "$OUTDIR/gramine_gc_${gc_flags// /_}_heap${heap_mb}_time.txt" gramine "$gc_flags" "$heap_mb"
  done

done


# === Post-process Summary ===
echo "\n✅ Full heap pressure benchmarking completed."
echo "Results saved in: $SUMMARY_CSV"

