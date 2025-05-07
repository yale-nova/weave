#!/bin/bash
set -euo pipefail

# === CONFIG ===
SPARK_HOME=${SPARK_HOME:-/opt/spark}
SPARK_CONF_DIR="${SPARK_HOME}/conf"
SPARK_JARS_DIR="${SPARK_HOME}/jars"
SCALA_VERSION=2.12
CLASS_TO_RUN="${1:?Missing Spark class (e.g., org.apache.spark.deploy.worker.Worker)}"
shift
SPARK_ARGS=("$@")

# === Compute 80% of system memory in MB ===
TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MB=$((TOTAL_KB / 1024))
USE_MB=$((TOTAL_MB * 80 / 100))

# JVM memory options
XMX="${USE_MB}m"
XMS="${USE_MB}m"
XSS="512k"
METASPACE="128m"
DIRECT_MEM="256m"

# === Logging ===
echo "🧠 Total System Memory: ${TOTAL_MB} MB" >&2
echo "📦 Using 80% for JVM: ${USE_MB} MB" >&2
echo "⚙️ JVM Flags:" >&2
echo "   -Xmx$XMX" >&2
echo "   -Xms$XMS" >&2
echo "   -Xss$XSS" >&2
echo "   -XX:MaxMetaspaceSize=$METASPACE" >&2
echo "   -XX:MaxDirectMemorySize=$DIRECT_MEM" >&2
echo "🚀 Launching Class: $CLASS_TO_RUN" >&2
echo "   With args: ${SPARK_ARGS[*]}" >&2

# === Final Java command ===
JAVA_BIN=${JAVA_HOME:-/usr}/bin/java
exec "$JAVA_BIN" \
  -Xmx$XMX \
  -Xms$XMS \
  -XX:MaxMetaspaceSize=$METASPACE \
  -XX:MaxDirectMemorySize=$DIRECT_MEM \
  -Xss$XSS \
  -cp "$SPARK_CONF_DIR:$SPARK_JARS_DIR/*" \
  "$CLASS_TO_RUN" \
  "${SPARK_ARGS[@]}"

