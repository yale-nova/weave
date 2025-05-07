#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Configuring Spark node..."

# Install Spark if needed
bash "$SCRIPT_DIR/install_spark.sh"

# Slim Spark jars if needed
bash "$SCRIPT_DIR/trim_spark_jars.sh"

echo "✅ Spark node is fully configured and ready!"

