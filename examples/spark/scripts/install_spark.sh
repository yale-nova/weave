#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SPARK_VERSION="3.2.2"
SPARK_HADOOP_VERSION="hadoop3.2"
SPARK_DIR="/opt/spark"
SPARK_TGZ="spark-${SPARK_VERSION}-bin-${SPARK_HADOOP_VERSION}.tgz"
SPARK_DOWNLOAD_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"

# Helper to check Spark installation
spark_already_installed() {
    [[ -d "$SPARK_DIR" ]] && \
    [[ -x "$SPARK_DIR/bin/spark-submit" ]] && \
    [[ -f "$SPARK_DIR/jars/spark-core_2.12-${SPARK_VERSION}.jar" ]]
}

if spark_already_installed; then
    echo "✅ Spark already installed at $SPARK_DIR. Skipping installation."
else
    echo "⚡ Installing Spark $SPARK_VERSION..."

    sudo apt update
    sudo apt install -y openjdk-11-jdk scala wget

    cd /opt
    wget "$SPARK_DOWNLOAD_URL"
    tar -xvzf "$SPARK_TGZ"

    # Dynamically find extracted folder
    EXTRACTED_DIR="spark-${SPARK_VERSION}-bin-${SPARK_HADOOP_VERSION}"
    echo "📦 Extracted folder: $EXTRACTED_DIR"

    mv "/opt/$EXTRACTED_DIR" "$SPARK_DIR"
    rm -f "$SPARK_TGZ"

    echo "✅ Spark moved to /opt/spark."
fi

echo ""
echo "⚡ To set up environment variables, run:"
echo "    export SPARK_HOME=/opt/spark"
echo "    export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin"
echo ""

