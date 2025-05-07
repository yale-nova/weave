#!/usr/bin/env bash

set -e

echo "🚀 Entrypoint started."

# Function to check if ca-certificates is correctly configured
check_ca_certificates() {
    if ! update-ca-certificates --fresh >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Try to fix ca-certificates if needed
echo "🔍 Checking ca-certificates setup..."
if ! check_ca_certificates; then
    echo "⚠️  Detected broken ca-certificates. Attempting repair..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ Cannot fix ca-certificates without root privileges."
    else
        apt-get update && \
        apt-get install --reinstall -y ca-certificates && \
        update-ca-certificates --fresh || \
        echo "❌ Failed to repair ca-certificates"
    fi
else
    echo "✅ ca-certificates looks good."
fi

echo "🏁 Starting main process: $@"
exec "$@"

