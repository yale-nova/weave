#!/bin/bash
set -euo pipefail

# ==============================
# ✅ Launch Weave Spark Master (correct PID, optimal memory, clean)
# ==============================

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SPARK_HOME="/opt/spark"
SPARK_CONF_DIR="$ROOT_DIR/conf"
SPARK_LOG_DIR="$SPARK_HOME/logs"

# Arguments
CLUSTER_SIZE="${1:?Cluster size not provided}"
MODE="${2:-optimal}"
MEMORY_PER_MACHINE_GB="${3:-16}"
EPC_PER_MACHINE_GB="${4:-8}"
NUM_MACHINES="${5:-1}"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEST_NAME="launch_weave_master"
LOG_DIR="$ROOT_DIR/logs/${TEST_NAME}_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

MASTER_LOG="$LOG_DIR/master.out"

# Suggest cluster config
CONFIG_OUTPUT=$(bash "$SCRIPT_DIR/suggest_cluster_config.sh" "$MODE" "$CLUSTER_SIZE" "$MEMORY_PER_MACHINE_GB" "$EPC_PER_MACHINE_GB" "$NUM_MACHINES")
eval "$CONFIG_OUTPUT"

# Export environment variables
export SPARK_CONF_DIR
export SPARK_LOG_DIR
export SPARK_MASTER_HOST="127.0.0.1"
export SPARK_MASTER_PORT="7077"
export SPARK_WORKER_MEMORY="${SPARK_WORKER_MEMORY_GB}g"
export SPARK_WORKER_CORES="$SPARK_WORKER_CORES"
export SPARK_DRIVER_MEMORY="${SPARK_DRIVER_MEMORY_GB}g"
export SPARK_EXECUTOR_MEMORY="${SPARK_EXECUTOR_MEMORY_GB}g"
export SPARK_GC_OPTS="$SPARK_GC_OPTS"

# Clean old logs if any
rm -f "$SPARK_LOG_DIR/spark-*-org.apache.spark.deploy.master.Master-*.out"
rm -f "$SPARK_LOG_DIR/spark-*-Master-*.pid"

# Launch Spark Master
echo "🚀 Launching Spark Master using start-master.sh..."
"$SPARK_HOME/sbin/start-master.sh" > "$MASTER_LOG" 2>&1 &

# Sleep briefly to allow Master process to start
sleep 2

# Find real Master PID
MASTER_PID_FILE=$(find "$SPARK_LOG_DIR" -name 'spark-*-Master-*.pid' | head -n 1)

if [[ -n "$MASTER_PID_FILE" && -f "$MASTER_PID_FILE" ]]; then
  MASTER_PID=$(cat "$MASTER_PID_FILE")
  echo "$MASTER_PID" > "$LOG_DIR/weave-master.pid"
  echo "✅ Spark Master launched successfully (PID: $MASTER_PID)"
  echo "    Logs: $MASTER_LOG"
else
  echo "❌ Failed to find Spark Master PID! Check logs: $MASTER_LOG"
  exit 1
fi

exit 0

