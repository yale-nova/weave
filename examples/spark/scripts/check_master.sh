#!/bin/bash
set -euo pipefail

# ==============================
# ✅ Full Spark Master Health Check Script (Fixed for new JVM settings)
# ==============================

PID="${1:?Missing Master PID}"
SPARK_MASTER_HOST="${2:?Missing Spark Master Host}"
SPARK_MASTER_PORT="${3:?Missing Spark Master Port}"
SPARK_MASTER_WEBUI_PORT="${4:?Missing Spark Master WebUI Port}"

echo "🔎 Checking Spark Master Health (PID=$PID, HOST=$SPARK_MASTER_HOST, PORT=$SPARK_MASTER_PORT)"

# === 1. Check if PID is running ===
if ! ps -p "$PID" > /dev/null; then
    echo "❌ Process with PID $PID is not running!"
    exit 1
fi
echo "✅ JVM process is alive (PID=$PID)"

# === 2. Check JVM memory and GC settings ===
JVM_CMDLINE=$(ps -p "$PID" -o args=)

# Only check for -Xmx and -XX:+UseParallelGC (NOT -Xms anymore)
if ! echo "$JVM_CMDLINE" | grep -q '\-Xmx[0-9]\+[mMgG]'; then
    echo "❌ JVM maximum heap (-Xmx) setting missing!"
    exit 1
fi

if ! echo "$JVM_CMDLINE" | grep -q '\-XX:+UseParallelGC'; then
    echo "❌ JVM GC setting (-XX:+UseParallelGC) missing!"
    exit 1
fi

if ! echo "$JVM_CMDLINE" | grep -q '\-XX:+UseParallelOldGC'; then
    echo "❌ JVM GC setting (-XX:+UseParallelOldGC) missing!"
    exit 1
fi

echo "✅ JVM memory and GC settings are present"

# === 3. Check JVM log4j configuration ===
if ! echo "$JVM_CMDLINE" | grep -q "log4j.configuration"; then
    echo "❌ JVM missing log4j configuration!"
    exit 1
fi
echo "✅ JVM log4j configuration is set"

# === 4. Check critical environment variables ===
ENV_FILE="/proc/$PID/environ"

for VAR in SPARK_LOG_DIR SPARK_LOG_LEVEL SPARK_MASTER_PORT SPARK_MASTER_WEBUI_PORT; do
    if ! tr '\0' '\n' < "$ENV_FILE" | grep -q "^$VAR="; then
        echo "❌ Missing environment variable: $VAR"
        exit 1
    fi
done
echo "✅ Critical environment variables are present"

# === 5. Check Spark Master REST API ===
MASTER_JSON=$(curl -s --max-time 5 "http://${SPARK_MASTER_HOST}:${SPARK_MASTER_WEBUI_PORT}/json/" || true)

if [[ -z "$MASTER_JSON" ]]; then
    echo "❌ Spark Master API did not respond!"
    exit 1
fi

EXPECTED_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
ACTUAL_URL=$(echo "$MASTER_JSON" | grep -oP '"url"\s*:\s*"\K[^"]+' || true)
STATUS=$(echo "$MASTER_JSON" | grep -oP '"status"\s*:\s*"\K[^"]+' || true)

if [[ "$ACTUAL_URL" != "$EXPECTED_URL" ]]; then
    echo "❌ Spark URL mismatch!"
    echo "    Expected: $EXPECTED_URL"
    echo "    Got:      $ACTUAL_URL"
    exit 1
fi

if [[ "$STATUS" != "ALIVE" ]]; then
    echo "❌ Spark Master status not ALIVE!"
    echo "    Status: $STATUS"
    exit 1
fi

echo "✅ Spark Master API reports correct URL and ALIVE status"
echo "🏁 Spark Master sanity check PASSED!"
exit 0

