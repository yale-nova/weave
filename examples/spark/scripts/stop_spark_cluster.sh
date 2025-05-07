#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

DEFAULT_LOG_DIR="$ROOT_DIR/logs"
LOG_DIR="${1:-$DEFAULT_LOG_DIR}"

TIMEOUT_SECONDS=10

PIDS_TO_KILL=()

echo "🛑 Stopping Spark Cluster (Master + Worker(s))..."

# Find Master
MASTER_PID=$(jps | grep -i Master | awk '{print $1}' || true)
if [[ -n "${MASTER_PID:-}" ]]; then
  echo "✅ Found Spark Master (PID $MASTER_PID)"
  PIDS_TO_KILL+=("$MASTER_PID")
else
  echo "⚠️  No Spark Master process found."
fi

# Find Worker PIDs
for pidfile in "$LOG_DIR"/worker_*.pid; do
  if [[ -f "$pidfile" ]]; then
    WORKER_PID=$(cat "$pidfile")
    if kill -0 "$WORKER_PID" 2>/dev/null; then
      echo "✅ Found Spark Worker (PID $WORKER_PID) from $pidfile"
      PIDS_TO_KILL+=("$WORKER_PID")
    else
      echo "⚠️  Worker PID $WORKER_PID not running (from $pidfile)"
    fi
  fi
done

# Kill collected PIDs
if [[ ${#PIDS_TO_KILL[@]} -gt 0 ]]; then
  for pid in "${PIDS_TO_KILL[@]}"; do
    echo "🔪 Sending SIGTERM to PID $pid"
    kill "$pid" || true
  done

  # Poll for exit
  for pid in "${PIDS_TO_KILL[@]}"; do
    DEAD=0
    for i in $(seq 1 "$TIMEOUT_SECONDS"); do
      if ! kill -0 "$pid" 2>/dev/null; then
        DEAD=1
        break
      fi
      sleep 1
    done

    if [[ "$DEAD" -eq 1 ]]; then
      echo "✅ PID $pid exited cleanly."
    else
      echo "❌ PID $pid did not exit. Sending SIGKILL..."
      kill -9 "$pid" || true
    fi
  done
else
  echo "✅ Nothing to stop."
fi

# Clean up PID files
rm -f "$LOG_DIR"/worker_*.pid || true

echo "✅ Spark cluster stopped."

