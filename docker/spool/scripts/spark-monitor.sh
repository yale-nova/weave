#!/bin/bash

# Create log dir if not exists
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

# Output file
LOG_FILE="$LOG_DIR/spark_monitor_$(date '+%Y%m%d_%H%M%S').log"

# Print header
echo "Timestamp,PID,CPU%,MEM%,RSS(MB),VSZ(MB),Net_RX(KB),Net_TX(KB),CMD" >> "$LOG_FILE"

# Get initial network stats
function get_net_bytes {
  cat /proc/net/dev | awk '/eth|ens|eno/ {rx += $2; tx += $10} END {print rx, tx}'
}

read PREV_RX PREV_TX < <(get_net_bytes)

# Monitor loop
while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  # Per-process memory and CPU usage
  ps -eo pid,pcpu,pmem,rss,vsz,comm,args | grep java | grep -v grep | while read -r PID CPU MEM RSS VSZ COMM CMD; do
    # Read new network stats
    read CUR_RX CUR_TX < <(get_net_bytes)
    RX_KB=$(( (CUR_RX - PREV_RX) / 1024 ))
    TX_KB=$(( (CUR_TX - PREV_TX) / 1024 ))

    echo "$TIMESTAMP,$PID,$CPU,$MEM,$((RSS/1024)),$((VSZ/1024)),$RX_KB,$TX_KB,\"$CMD\"" >> "$LOG_FILE"
  done

  # Update previous network counters
  read PREV_RX PREV_TX < <(get_net_bytes)

  sleep 5  # adjust the interval as needed
done

