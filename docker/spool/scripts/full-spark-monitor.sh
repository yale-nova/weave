#!/bin/bash

### ========== CONFIG ==========
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
START_TIME=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/spark_monitor_$START_TIME.csv"
MONITOR_INTERVAL=5  # seconds

### ========== UTILITY FUNCS ==========
function get_net_bytes {
  cat /proc/net/dev | awk '/eth|ens|eno/ {rx+=$2; tx+=$10} END {print rx, tx}'
}

function log_header {
  echo "Timestamp,PID,CPU%,MEM%,RSS(MB),VSZ(MB),FDs,Net_RX(KB),Net_TX(KB),CMD" >> "$LOG_FILE"
}

function log_metrics {
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  ps -eo pid,pcpu,pmem,rss,vsz,comm,args | grep java | grep -v grep | while read -r PID CPU MEM RSS VSZ COMM CMD; do
    # Count file descriptors
    FDS=$(ls /proc/"$PID"/fd 2>/dev/null | wc -l)

    # Read current network usage
    read CUR_RX CUR_TX < <(get_net_bytes)
    RX_KB=$(( (CUR_RX - PREV_RX) / 1024 ))
    TX_KB=$(( (CUR_TX - PREV_TX) / 1024 ))

    echo "$TIMESTAMP,$PID,$CPU,$MEM,$((RSS/1024)),$((VSZ/1024)),$FDS,$RX_KB,$TX_KB,\"$CMD\"" >> "$LOG_FILE"
  done

  # Update network counters
  read PREV_RX PREV_TX < <(get_net_bytes)
}

function clean_exit {
  echo "🛑 Monitoring stopped."
  exit 0
}

trap clean_exit SIGINT SIGTERM

### ========== MAIN LOGIC ==========

log_header
read PREV_RX PREV_TX < <(get_net_bytes)

# Launch the Spark job and capture PID
echo "🚀 Starting Spark job..."
"$@" &
SPARK_PID=$!

echo "📊 Monitoring spark-submit (PID $SPARK_PID)... Output at: $LOG_FILE"

# Monitor loop — runs until spark-submit exits
while kill -0 "$SPARK_PID" 2>/dev/null; do
  log_metrics
  sleep "$MONITOR_INTERVAL"
done

echo "✅ Spark job completed. Final logs saved to: $LOG_FILE"
