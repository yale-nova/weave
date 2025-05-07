#!/bin/bash
set -euo pipefail

# ========================================
# ✅ Trace Minimal Spark JAR Dependencies (Final Clean Version)
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SPARK_HOME="/opt/spark"

# Parse mode flag: "examples" or "simple"
MODE="${1:-examples}"

# --- 0. Find latest Master log dir ---
LATEST_CONF_DIR=$(find "$ROOT_DIR/conf" -type d -name "test_launch_weave_master*" | sort | tail -n 1)
if [[ -z "$LATEST_CONF_DIR" ]]; then
  echo "❌ Could not find a recent Spark Master conf. Launch Master first."
  exit 1
fi
source "$LATEST_CONF_DIR/spark-env.sh"

TIMESTAMP=$(basename "$LATEST_CONF_DIR" | sed 's/test_launch_weave_master_//')
LOG_DIR="$ROOT_DIR/logs/launch_weave_master_$TIMESTAMP"
mkdir -p "$LOG_DIR"

STRACE_LOG="$LOG_DIR/strace_worker.log"
WORKER_OUT="$LOG_DIR/worker.out"
WORKER_ERR="$LOG_DIR/worker.err"
MINIMAL_JARS_LIST="$LOG_DIR/minimal_jars.txt"

# --- 1. Launch Spark Master if not running ---
if ! pgrep -f org.apache.spark.deploy.master.Master > /dev/null; then
  echo "🚀 Launching Spark Master for tracing..."
  bash "$SCRIPT_DIR/launch_master.sh" 1 optimal 16 8 1 INFO 127.0.0.1 &
  sleep 5
fi

# --- 2. Start Spark Worker under strace ---
echo "🔍 Starting Spark Worker under strace..."
strace -f -e trace=openat -o "$STRACE_LOG" \
  "$SPARK_HOME/bin/spark-class" org.apache.spark.deploy.worker.Worker "spark://127.0.0.1:7077" \
  >"$WORKER_OUT" 2>"$WORKER_ERR" &
WORKER_PID=$!
sleep 10

# --- 3. Submit jobs based on MODE ---
echo "🤝 Submitting test Spark jobs (mode: $MODE)..."

if [[ "$MODE" == "examples" ]]; then
  $SPARK_HOME/bin/spark-submit --master spark://127.0.0.1:7077 \
    --class org.apache.spark.examples.SparkPi \
    "$SPARK_HOME/examples/jars/spark-examples_2.12-3.2.2.jar" 5 \
    > "$LOG_DIR/spark-submit-pi.out" 2> "$LOG_DIR/spark-submit-pi.err" || echo "⚠️  SparkPi failed."

  $SPARK_HOME/bin/spark-submit --master spark://127.0.0.1:7077 \
    --class org.apache.spark.examples.SparkLR \
    "$SPARK_HOME/examples/jars/spark-examples_2.12-3.2.2.jar" 5 \
    > "$LOG_DIR/spark-submit-lr.out" 2> "$LOG_DIR/spark-submit-lr.err" || echo "⚠️  SparkLR failed."
else
  # Simple job: basic RDD operation
  echo "from pyspark import SparkContext; sc = SparkContext(); sc.parallelize(range(1000)).count(); sc.stop()" > "$LOG_DIR/simple_job.py"
  $SPARK_HOME/bin/spark-submit --master spark://127.0.0.1:7077 \
    "$LOG_DIR/simple_job.py" \
    > "$LOG_DIR/spark-submit-simple.out" 2> "$LOG_DIR/spark-submit-simple.err" || echo "⚠️  Simple job failed."
fi

sleep 5

# --- 4. Cleanup Worker and Master ---
kill "$WORKER_PID" || true
sleep 2
pkill -f org.apache.spark.deploy.master.Master || true

# --- 5. Extract opened jar files (excluding user app jars) ---
echo "🔍 Extracting minimal jars from trace..."
grep ".jar\"" "$STRACE_LOG" | awk -F '"' '{print $2}' | grep "/opt/spark/jars/" | \
  sort | uniq > "$MINIMAL_JARS_LIST"

# --- 6. Size summary ---
echo "📊 Computing jar size..."
TOTAL_MINIMAL_SIZE=$(awk '{s+=$1} END {print s}' <(xargs -a "$MINIMAL_JARS_LIST" du -b | awk '{print $1}'))
TOTAL_ALL_SIZE=$(du -sb "$SPARK_HOME/jars" | awk '{print $1}')
TOTAL_MINIMAL_MB=$((TOTAL_MINIMAL_SIZE/1024/1024))
TOTAL_ALL_MB=$((TOTAL_ALL_SIZE/1024/1024))

# --- 7. Print final summary ---
echo "---- [Minimal Jars List] ----"
cat "$MINIMAL_JARS_LIST"
echo "-----------------------------"
echo "✨ Total size of used jars: ${TOTAL_MINIMAL_MB} MB"
echo "📦 Total size of all Spark jars: ${TOTAL_ALL_MB} MB"

if (( TOTAL_MINIMAL_MB >= TOTAL_ALL_MB - 10 )); then
  echo "⚠️ Warning: Minimal jars almost equal to full jars. (Maybe job too heavy?)"
fi

echo "🎉 Tracing completed successfully!"
exit 0

