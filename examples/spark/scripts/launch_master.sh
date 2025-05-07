#!/bin/bash
set -euo pipefail

# ==============================
# ✅ Launch Spark Master (Upgraded for Dynamic Test Configs)
# ==============================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SPARK_HOME="/opt/spark"
SPARK_LOG_DIR="$ROOT_DIR/logs"

# === Arguments ===
CLUSTER_SIZE="${1:?Missing cluster size}"
MODE="${2:-optimal}"
MEMORY_PER_MACHINE_GB="${3:-16}"
EPC_PER_MACHINE_GB="${4:-8}"
NUM_MACHINES="${5:-1}"
LOG_LEVEL="${6:-INFO}"
MASTER_HOST="${7:-127.0.0.1}"

# === Create time-stamped run directory ===
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RUN_LOG_DIR="$SPARK_LOG_DIR/launch_weave_master_$TIMESTAMP"
mkdir -p "$RUN_LOG_DIR"

# === 1. Setup dynamic environment and config ===
bash "$SCRIPT_DIR/set_suggested_config.sh" "$RUN_LOG_DIR" "$LOG_LEVEL" "$CLUSTER_SIZE" "$MODE" "$MEMORY_PER_MACHINE_GB" "$EPC_PER_MACHINE_GB" "$NUM_MACHINES" "$MASTER_HOST"

# Dynamically locate the correct spark-env.sh
CONF_SUBDIR_NAME="test_$(basename "$RUN_LOG_DIR")"
DYNAMIC_SPARK_ENV="$ROOT_DIR/conf/$CONF_SUBDIR_NAME/spark-env.sh"

if [[ ! -f "$DYNAMIC_SPARK_ENV" ]]; then
    echo "❌ ERROR: Expected spark-env.sh not found: $DYNAMIC_SPARK_ENV"
    exit 1
fi

# === 2. Launch Spark Master ===
echo "🚀 Launching Spark Master..."
source "$DYNAMIC_SPARK_ENV"

"$SPARK_HOME/bin/spark-class" org.apache.spark.deploy.master.Master > "$RUN_LOG_DIR/master.out" 2>&1 &
MASTER_PID=$!

# ✨ Save PID to log directory
echo "$MASTER_PID" > "$RUN_LOG_DIR/master.pid"

echo "🛡 Started Spark Master with PID $MASTER_PID (saved in $RUN_LOG_DIR/master.pid)"

# === 3. Double-check launched PID (from logs) ===
sleep 2  # Allow logs to flush
if grep -q "Started daemon with process name" "$RUN_LOG_DIR/master.out"; then
    LOG_REPORTED_PID=$(grep "Started daemon with process name" "$RUN_LOG_DIR/master.out" | grep -oP '\d+(?=@)')
    if [[ "$LOG_REPORTED_PID" != "$MASTER_PID" ]]; then
        echo "❌ PID mismatch: Launch PID=$MASTER_PID, Master reported PID=$LOG_REPORTED_PID"
        exit 1
    fi
    echo "✅ PID match confirmed: $MASTER_PID"
else
    echo "⚠️ Could not find 'Started daemon' line in logs (continuing anyway)"
fi

# === 4. Wait for full service readiness ===
bash "$SCRIPT_DIR/wait_for_ready.sh" "$MASTER_PID" "$SPARK_MASTER_HOST" "$SPARK_MASTER_PORT" "$SPARK_MASTER_WEBUI_PORT" "Master"

# === 5. JVM + Spark health checks ===
bash "$SCRIPT_DIR/check_master.sh" "$MASTER_PID" "$SPARK_MASTER_HOST" "$SPARK_MASTER_PORT" "$SPARK_MASTER_WEBUI_PORT"

echo "✅ Spark Master fully launched and validated!"

