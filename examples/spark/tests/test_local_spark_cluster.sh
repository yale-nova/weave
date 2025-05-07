#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/.."
SCRIPT_DIR="$ROOT_DIR/scripts"

# Arguments
CLUSTER_SIZE="${1:?Cluster size not provided}"
MODE="${2:-optimal}"
MEMORY_PER_MACHINE_GB="${3:-16}"
EPC_PER_MACHINE_GB="${4:-8}"
NUM_MACHINES="${5:-1}"
KILL_AFTER_TEST="${6:-no}"
LAUNCH_DEBUG="${7:-no}"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEST_NAME="test_local_spark_cluster"
LOG_DIR="$ROOT_DIR/logs/${TEST_NAME}_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

MASTER_LOG="$LOG_DIR/master.log"

# Suggest cluster config and load it
CONFIG_OUTPUT=$(bash "$SCRIPT_DIR/suggest_cluster_config.sh" "$MODE" "$CLUSTER_SIZE" "$MEMORY_PER_MACHINE_GB" "$EPC_PER_MACHINE_GB" "$NUM_MACHINES")
eval "$CONFIG_OUTPUT"

# Export environment variables
export SPARK_MASTER_HOST="127.0.0.1"
export SPARK_MASTER_PORT="7077"
export SPARK_WORKER_MEMORY="${SPARK_WORKER_MEMORY_GB}g"
export SPARK_WORKER_CORES="$SPARK_WORKER_CORES"
export SPARK_DRIVER_MEMORY="${SPARK_DRIVER_MEMORY_GB}g"
export SPARK_EXECUTOR_MEMORY="${SPARK_EXECUTOR_MEMORY_GB}g"
export SPARK_GC_OPTS="$SPARK_GC_OPTS"

# Start Spark Master
echo "🚀 Starting Spark Master..."
/opt/spark/sbin/start-master.sh > "$MASTER_LOG" 2>&1 &

# Save Master PID
echo $! > "$LOG_DIR/master.pid"

# Poll for Master readiness
MASTER_READY=0
for i in {1..30}; do
  if curl -s "http://127.0.0.1:8080" | grep -q "Spark Master"; then
    MASTER_READY=1
    break
  fi
  sleep 1
done

if [[ "$MASTER_READY" -eq 0 ]]; then
  echo "❌ Master Web UI did not become ready in time!"
  exit 1
fi

echo "✅ Master Web UI is UP."

# Launch workers
for idx in $(seq 1 "$CLUSTER_SIZE"); do
  WORKER_ID="worker${idx}"
  echo "🚀 Launching Worker $WORKER_ID"
  if [[ "$LAUNCH_DEBUG" == "yes" ]]; then
    bash "$SCRIPT_DIR/launch_worker.sh" "$WORKER_ID" "$LOG_DIR" --debug
  else
    bash "$SCRIPT_DIR/launch_worker.sh" "$WORKER_ID" "$LOG_DIR"
  fi
done

# Poll for first Worker Web UI
WORKER_READY=0
for i in {1..30}; do
  if curl -s "http://127.0.0.1:8081" | grep -q "Worker"; then
    WORKER_READY=1
    break
  fi
  sleep 1
done

if [[ "$WORKER_READY" -eq 0 ]]; then
  echo "❌ Worker Web UI did not become ready in time!"
  exit 1
fi

# Safety check: list JVM processes
JPS_LOG="$LOG_DIR/jps.log"
echo "🔍 JVM Processes (jps output):" | tee "$JPS_LOG"
jps | tee -a "$JPS_LOG"

if [[ "$LAUNCH_DEBUG" == "yes" ]]; then
  # Log final cluster config in debug mode only
  echo "\n✅ Final Cluster Settings (Debug Mode):" | tee -a "$JPS_LOG"
  echo "- Cluster size: $CLUSTER_SIZE" | tee -a "$JPS_LOG"
  echo "- Mode: $MODE" | tee -a "$JPS_LOG"
  echo "- Worker Memory: $SPARK_WORKER_MEMORY" | tee -a "$JPS_LOG"
  echo "- Worker Cores: $SPARK_WORKER_CORES" | tee -a "$JPS_LOG"
  echo "- Executor Memory: $SPARK_EXECUTOR_MEMORY" | tee -a "$JPS_LOG"
  echo "- Driver Memory: $SPARK_DRIVER_MEMORY" | tee -a "$JPS_LOG"
  echo "- GC Options: $SPARK_GC_OPTS" | tee -a "$JPS_LOG"
fi

echo "\n✅ Spark cluster local test finished. Logs saved under $LOG_DIR."
echo "👉 Open http://127.0.0.1:8080 to visually verify Worker registration."

if [[ "$KILL_AFTER_TEST" == "yes" ]]; then
  echo "🛑 Stopping Spark Cluster after test..."
  bash "$SCRIPT_DIR/stop_spark_cluster.sh" "$LOG_DIR"
else
  echo "⚡ Cluster still running. To stop it later, run:"
  echo "bash $SCRIPT_DIR/stop_spark_cluster.sh $LOG_DIR"
fi

