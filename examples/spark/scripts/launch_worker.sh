#!/bin/bash
set -euo pipefail

WORKER_ID="${1:?Worker ID not provided}"
LOG_DIR="${2:?Log directory not provided}"
DEBUG_MODE="${3:-no}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

SPARK_MASTER_URL="spark://127.0.0.1:7077"
WORKER_LOG="$LOG_DIR/worker_${WORKER_ID}.log"
PID_FILE="$LOG_DIR/worker_${WORKER_ID}.pid"

echo "🚀 Launching Spark Worker $WORKER_ID..."

# Build Java command
JAVA_CMD=(
  java
  $SPARK_GC_OPTS
  -cp "$ROOT_DIR/minimal-jars/*"
  org.apache.spark.deploy.worker.Worker
  "$SPARK_MASTER_URL"
)

# If debug mode, print extensive logs
if [[ "$DEBUG_MODE" == "--debug" ]]; then
  echo "🔍 Debug Mode Active for Worker $WORKER_ID"
  echo "🔹 Working Directory: $(pwd)"
  echo "🔹 Java Command:"
  printf "  %q" "${JAVA_CMD[@]}"
  echo ""
  echo "🔹 Environment Variables:"
  echo "  SPARK_WORKER_MEMORY=$SPARK_WORKER_MEMORY"
  echo "  SPARK_WORKER_CORES=$SPARK_WORKER_CORES"
  echo "  SPARK_DRIVER_MEMORY=$SPARK_DRIVER_MEMORY"
  echo "  SPARK_EXECUTOR_MEMORY=$SPARK_EXECUTOR_MEMORY"
  echo "  SPARK_GC_OPTS=$SPARK_GC_OPTS"
fi

# Launch Worker
( "${JAVA_CMD[@]}" > "$WORKER_LOG" 2>&1 & )

WORKER_PID=$!
echo "$WORKER_PID" > "$PID_FILE"
echo "✅ Worker $WORKER_ID started with PID $WORKER_PID, logs at $WORKER_LOG"

