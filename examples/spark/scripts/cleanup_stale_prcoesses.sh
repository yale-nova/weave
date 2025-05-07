#!/bin/bash
set -euo pipefail

# ==============================
# ✅ Clean up Spark Processes Script (Safe & Correct Version)
# ==============================

# Arguments
TEST_CASE="${1:?Missing required test case name! Usage: ./cleanup_stale_processes.sh <test_case_name>}"
LOGS_BASE_DIR="./logs"
CLEANUP_LOG="$LOGS_BASE_DIR/cleanup_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOGS_BASE_DIR"

echo "🔍 Starting cleanup (Test case: $TEST_CASE)..."
echo "Cleanup started at $(date)" > "$CLEANUP_LOG"

# Find matching log directories (test case may have multiple time-tagged runs)
MATCHED_DIRS=$(find "$LOGS_BASE_DIR" -type d -name "*$TEST_CASE*" || true)

if [[ -z "$MATCHED_DIRS" ]]; then
    echo "❌ No matching log directories found for test case: $TEST_CASE"
    exit 1
fi

# Find and kill PIDs
FOUND_ANY=0
for pid_file in $(find $MATCHED_DIRS -type f -name "*.pid" 2>/dev/null || true); do
    FOUND_ANY=1
    PID=$(cat "$pid_file" || true)
    if [[ -z "$PID" ]]; then
        echo "⚠️ Empty PID file: $pid_file" >> "$CLEANUP_LOG"
        continue
    fi

    echo "🔍 Found PID file: $pid_file (PID: $PID)" >> "$CLEANUP_LOG"

    if ps -p "$PID" > /dev/null 2>&1; then
        PROCESS_INFO=$(ps -p "$PID" -o cmd= || echo "Not found")
        echo "  ➡️  Killing PID $PID ($PROCESS_INFO)..." >> "$CLEANUP_LOG"
        kill "$PID"
        sleep 2
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "  ⚠️ PID $PID did not terminate. Forcing kill..." >> "$CLEANUP_LOG"
            kill -9 "$PID"
            sleep 1
            if ps -p "$PID" > /dev/null 2>&1; then
                echo "  ❌ Failed to kill PID $PID even after force kill!" >> "$CLEANUP_LOG"
            else
                echo "  ✅ PID $PID force-killed." >> "$CLEANUP_LOG"
            fi
        else
            echo "  ✅ PID $PID gracefully terminated." >> "$CLEANUP_LOG"
        fi
    else
        echo "  ⚠️ No running process found for PID $PID (may have exited)." >> "$CLEANUP_LOG"
    fi

    # Clean up PID file
    rm -f "$pid_file"
done

if [[ "$FOUND_ANY" -eq 0 ]]; then
    echo "⚠️ No PID files found for test case: $TEST_CASE" >> "$CLEANUP_LOG"
fi

echo "✅ Cleanup completed at $(date)" >> "$CLEANUP_LOG"
echo "✅ Cleanup done! Log saved at $CLEANUP_LOG"

