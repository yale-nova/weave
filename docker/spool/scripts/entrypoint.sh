#!/usr/bin/env bash
set -e

echo "🚀 Entrypoint started."

# === SGX Detection ===
if [[ -c /dev/sgx_enclave || -c /dev/isgx ]]; then
    echo "🛡️ SGX device detected. Running in Gramine-SGX mode."
    export GRAMINE_MODE="sgx"
else
    echo "💻 No SGX device found. Running in Gramine-Direct mode."
    export GRAMINE_MODE="direct"
fi

# === CA Certificates Check ===
check_ca_certificates() {
    if ! update-ca-certificates --fresh >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

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

# === Start Main Process ===
echo "🏁 Starting main process: $@"
exec "$@"
