 
#!/bin/bash

set -euo pipefail

SPARK_HOME=${SPARK_HOME:-/opt/spark}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENCLAVED=false

# Parse optional --enclaved flag
if [[ "${1:-}" == "--enclaved" ]]; then
  ENCLAVED=true
  shift
fi

# Kill any existing master or worker
echo "🔄 Killing existing Spark master/worker processes..."
pkill -f 'org.apache.spark.deploy.master.Master' || true
pkill -f 'org.apache.spark.deploy.worker.Worker' || true
sleep 1

# Get machine resources
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
TOTAL_CORES=$(nproc)

# Compute memory allocations
MASTER_MEM_MB=$(( TOTAL_MEM_MB / 4 ))           # 25% of system memory
WORKER_MEM_MB=$(( TOTAL_MEM_MB * 45 / 100 ))    # 45% of system memory
[[ $MASTER_MEM_MB -gt 1024 ]] || MASTER_MEM_MB=1024

# Reserve 1 core for system, use rest for Spark
AVAILABLE_CORES=$(( TOTAL_CORES - 1 ))
[[ $AVAILABLE_CORES -ge 1 ]] || AVAILABLE_CORES=1
NUM_EXECUTORS=2
CORES_PER_EXECUTOR=$(( AVAILABLE_CORES / NUM_EXECUTORS ))
[[ $CORES_PER_EXECUTOR -ge 1 ]] || CORES_PER_EXECUTOR=1

# Prepare log files
MASTER_LOG="$SCRIPT_DIR/master.log"
WORKER_LOG="$SCRIPT_DIR/worker.log"
rm -f "$MASTER_LOG" "$WORKER_LOG"

# Launch Spark master
MASTER_HOST="127.0.0.1"
MASTER_PORT="7077"
WEBUI_PORT="8080"

echo "🚀 Starting Spark master..."
SPARK_LOCAL_IP=$MASTER_HOST \
$SPARK_HOME/bin/spark-class org.apache.spark.deploy.master.Master \
  --host "$MASTER_HOST" \
  --port "$MASTER_PORT" \
  --webui-port "$WEBUI_PORT" \
  >> "$MASTER_LOG" 2>&1 &

# Launch Spark worker
WORKER_PORT="7078"
WORKER_WEBUI_PORT="8081"
GRAMINE_OPT=""
if [ "$ENCLAVED" == "true" ]; then
  GRAMINE_OPT="--conf spark.executor.gramine.enabled=true"
fi

echo "🚀 Starting Spark worker..."
SPARK_LOCAL_IP=$MASTER_HOST \
$SPARK_HOME/bin/spark-class org.apache.spark.deploy.worker.Worker \
  spark://$MASTER_HOST:$MASTER_PORT \
  --host "$MASTER_HOST" \
  --port "$WORKER_PORT" \
  --webui-port "$WORKER_WEBUI_PORT" \
  $GRAMINE_OPT \
  >> "$WORKER_LOG" 2>&1 &

# Summary
echo "✅ Spark mini-cluster started:"
echo "  Master: $MASTER_MEM_MB MB RAM"
echo "  Worker: $WORKER_MEM_MB MB RAM, $AVAILABLE_CORES cores total ($CORES_PER_EXECUTOR per executor)"
echo "  Enclaved executors: $ENCLAVED"
echo "  Logs: $MASTER_LOG, $WORKER_LOG"