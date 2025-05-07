#!/bin/bash
set -euo pipefail

SPARK_WRAPPER="./spark-direct-class"
MONITOR_SCRIPT="./monitor_spark_worker.sh"
METRIC_LOG="./worker_metrics.log"

CLASS_TO_RUN="${1:?Missing Spark class}"
shift
SPARK_ARGS=("$@")

# === Step 1: Launch Spark class in background ===
$SPARK_WRAPPER "$CLASS_TO_RUN" "${SPARK_ARGS[@]}" &
SPARK_PID=$!

echo "🟢 Launched Spark class '$CLASS_TO_RUN' with PID $SPARK_PID" >&2

# === Step 2: Start monitoring ===
$MONITOR_SCRIPT "$SPARK_PID" "$METRIC_LOG" &
MONITOR_PID=$!

sleep 10 

# === Step 3: Wait for Spark to finish ===
wait $SPARK_PID
EXIT_CODE=$?

echo "🛑 Spark class exited with code $EXIT_CODE" >&2

# === Step 4: Wait for monitor and parse ===
wait $MONITOR_PID || true

if [[ -f "$METRIC_LOG" ]]; then
    echo -e "\n📊 === Metrics Report ==="
    ./parse_worker_metrics.sh "$METRIC_LOG"
else
    echo "❌ Metrics log not found." >&2
fi

exit $EXIT_CODE
