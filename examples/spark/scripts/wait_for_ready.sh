#!/bin/bash
set -euo pipefail
#set -x  # Enable line-by-line debugging

# ==============================
# ✅ Wait for Spark Service Readiness (CLEAN FINAL VERSION)
# ==============================

PID="${1:?Process PID not provided}"
TARGET_IP="${2:?Target IP not provided}"
SERVICE_PORT="${3:?Service TCP port not provided}"
WEBUI_PORT="${4:-}"
ROLE="${5:?Expected JVM role not provided}"

MAX_ATTEMPTS=30
SLEEP_BETWEEN=1

echo "🛡 Waiting for service (PID=$PID, Role=$ROLE) at $TARGET_IP TCP port $SERVICE_PORT"

# -----------------------------------
# 🧹 Step 1: Check JVM Process Role
# -----------------------------------
ATTEMPT=0
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    echo "⏳ [RoleCheck Attempt $ATTEMPT] Checking JVM role..."
    
    JPS_OUTPUT=$(jps || true)
    echo "$JPS_OUTPUT"

    # Kill conflicting Masters
    if [[ "$ROLE" == "Master" ]]; then
        echo "🔎 Checking for conflicting Masters..."
        while read -r jps_pid jps_role; do
            if [[ "$jps_role" == "Master" && "$jps_pid" != "$PID" ]]; then
                echo "⚡ Killing conflicting Master PID=$jps_pid"
                kill -9 "$jps_pid" || true
            fi
        done <<< "$JPS_OUTPUT"
    fi

    # Validate PID and role
    if echo "$JPS_OUTPUT" | awk -v pid="$PID" -v role="$ROLE" '$1==pid && $2==role' | grep -q "$ROLE"; then
        echo "✅ PID=$PID Role=$ROLE confirmed!"
        break
    else
        echo "❌ PID=$PID with Role=$ROLE not found yet."
    fi

    sleep "$SLEEP_BETWEEN"
    ATTEMPT=$((ATTEMPT + 1))
done

if [[ $ATTEMPT -eq $MAX_ATTEMPTS ]]; then
    echo "❌ Failed to validate PID and Role after $MAX_ATTEMPTS attempts."
    exit 1
fi

# -----------------------------------
# 🛜 Step 2: Check TCP Port Listening
# -----------------------------------
ATTEMPT=0
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    echo "⏳ [TCPCheck Attempt $ATTEMPT] Checking TCP port $SERVICE_PORT..."

    SS_OUTPUT=$(ss -ltn || true)
    echo "$SS_OUTPUT"

    if echo "$SS_OUTPUT" | grep -E "\]:$SERVICE_PORT|:$SERVICE_PORT" > /dev/null 2>&1; then
        echo "✅ TCP port $SERVICE_PORT is LISTENING!"
        break
    else
        echo "❌ TCP port $SERVICE_PORT not ready yet."
    fi

    sleep "$SLEEP_BETWEEN"
    ATTEMPT=$((ATTEMPT + 1))
done

if [[ $ATTEMPT -eq $MAX_ATTEMPTS ]]; then
    echo "❌ TCP port $SERVICE_PORT is NOT listening after $MAX_ATTEMPTS attempts."
    exit 1
fi

# -----------------------------------
# 🌐 Step 3: Check WebUI (HTTP only)
# -----------------------------------
if [[ -n "$WEBUI_PORT" ]]; then
    ATTEMPT=0
    while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
        echo "⏳ [WebUICheck Attempt $ATTEMPT] Checking WebUI http://$TARGET_IP:$WEBUI_PORT..."

        CURL_OUTPUT=$(curl -s --max-time 2 "http://$TARGET_IP:$WEBUI_PORT" || true)

        if echo "$CURL_OUTPUT" | grep -qi "spark"; then
            echo "✅ WebUI HTTP is responding!"
            break
        else
            echo "❌ WebUI not ready yet."
        fi

        sleep "$SLEEP_BETWEEN"
        ATTEMPT=$((ATTEMPT + 1))
    done

    if [[ $ATTEMPT -eq $MAX_ATTEMPTS ]]; then
        echo "⚠️ WebUI not ready after $((MAX_ATTEMPTS * SLEEP_BETWEEN)) seconds."
        # Not fatal: Spark may still be healthy without WebUI
    fi
fi

# -----------------------------------
# 🎉 Success
# -----------------------------------
echo "🏁 Spark $ROLE is fully ready!"
exit 0

