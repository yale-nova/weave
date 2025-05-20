#!/bin/bash

set -euo pipefail

WORKER_PID=$1
METRIC_LOG=${2:-"/workspace/metrics_spark_worker.log"}

echo "📈 Monitoring Spark worker PID=$WORKER_PID, logging to $METRIC_LOG..."

# Get initial brk boundaries from /proc/$PID/maps
get_brk_bounds() {
  awk '$6 == "[heap]" {print $1}' "/proc/$WORKER_PID/maps"
}

while kill -0 "$WORKER_PID" 2>/dev/null; do
  {
    echo "========== [$(date)] =========="
    
    echo "🧠 [Heap + Native Memory]"
    grep -E "VmPeak|VmRSS|VmSize|VmData|VmStk|VmExe|VmLib|VmSwap" "/proc/$WORKER_PID/status" || echo "N/A"

    echo "🔍 [brk heap range]"
    get_brk_bounds || echo "heap mapping not found"

    echo "🔗 [File Descriptors]"
    FD_COUNT=$(ls /proc/$WORKER_PID/fd 2>/dev/null | wc -l)
    echo "Open FDs: $FD_COUNT"
    cat "/proc/$WORKER_PID/limits" | grep "Max open files" || true

    echo "🧵 [Threads]"
    THREAD_COUNT=$(ls /proc/$WORKER_PID/task | wc -l)
    echo "Thread Count: $THREAD_COUNT"
    for TID in /proc/$WORKER_PID/task/*; do
      LIMIT_LINE=$(grep 'Max stack size' "$TID/limits" | head -1)
      echo "Thread ${TID##*/}: $LIMIT_LINE"
    done

    echo "👥 [Child Processes]"
    ps --ppid $WORKER_PID -o pid,cmd --no-headers || echo "None"

    echo
  } >> "$METRIC_LOG"

  sleep 5
done

echo "✅ Worker process $WORKER_PID exited. Monitoring stopped."
