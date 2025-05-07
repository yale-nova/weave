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

