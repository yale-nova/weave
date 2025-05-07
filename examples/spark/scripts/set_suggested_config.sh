#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SPARK_HOME="/opt/spark"

# Arguments
LOG_DIR="${1:?Missing log directory}"
LOG_LEVEL="${2:-INFO}"
CLUSTER_SIZE="${3:?Missing cluster size}"
MODE="${4:-optimal}"
MEMORY_PER_MACHINE_GB="${5:-16}"
EPC_PER_MACHINE_GB="${6:-8}"
NUM_MACHINES="${7:-1}"
SPARK_MASTER_HOST="${8:-127.0.0.1}"

# 1. Suggest cluster config
CONFIG_OUTPUT=$(bash "$SCRIPT_DIR/suggest_cluster_config.sh" "$MODE" "$CLUSTER_SIZE" "$MEMORY_PER_MACHINE_GB" "$EPC_PER_MACHINE_GB" "$NUM_MACHINES")
eval "$CONFIG_OUTPUT"

# 2. Export Spark settings
export SPARK_MASTER_HOST="$SPARK_MASTER_HOST"
export SPARK_LOG_DIR="$LOG_DIR"
export SPARK_LOG_LEVEL="$LOG_LEVEL"
export SPARK_MASTER_PORT="${SPARK_MASTER_PORT:-7077}"
export SPARK_MASTER_WEBUI_PORT="${SPARK_MASTER_WEBUI_PORT:-8080}"
export SPARK_LOG_MAXFILES=10
export SPARK_LOG_MAXSIZE=100m

# 3. Create run-specific conf dir
CONF_SUBDIR_NAME="test_$(basename "$LOG_DIR")"
CONF_DIR="$ROOT_DIR/conf/$CONF_SUBDIR_NAME"
SPARK_CONF_LINK_NAME="$CONF_SUBDIR_NAME"
SPARK_CONF_LINK="$SPARK_HOME/conf/$SPARK_CONF_LINK_NAME"

mkdir -p "$CONF_DIR"
mkdir -p "$(dirname "$SPARK_CONF_LINK")"

# 4. Copy base log4j and substitute
cp "$ROOT_DIR/conf/log4j.properties" "$CONF_DIR/log4j.properties"
sed -i "s|\${SPARK_LOG_DIR}|$SPARK_LOG_DIR|g" "$CONF_DIR/log4j.properties"
sed -i "s|\${SPARK_LOG_LEVEL:-INFO}|$SPARK_LOG_LEVEL|g" "$CONF_DIR/log4j.properties"

# 5. Symlink into Spark classpath
if [[ -e "$SPARK_CONF_LINK" ]]; then
    echo "🔄 Removing existing Spark conf link at $SPARK_CONF_LINK"
    rm -rf "$SPARK_CONF_LINK"
fi
ln -s "$CONF_DIR" "$SPARK_CONF_LINK"
echo "✅ Created symlink: $SPARK_CONF_LINK -> $CONF_DIR"

# 6. Set JVM options
export SPARK_DAEMON_MEMORY="${SPARK_EXECUTOR_MEMORY_GB}g"
SPARK_GC_OPTS="-XX:+UseParallelGC -XX:+UseParallelOldGC"
export SPARK_DAEMON_JAVA_OPTS="-Dlog4j.configuration=file:$SPARK_CONF_LINK/log4j.properties $SPARK_GC_OPTS"

# 7. Write spark-env.sh inside CONF_DIR
cat > "$CONF_DIR/spark-env.sh" <<EOF
# Auto-generated
export SPARK_MASTER_HOST="$SPARK_MASTER_HOST"
$CONFIG_OUTPUT
export SPARK_LOG_DIR="$SPARK_LOG_DIR"
export SPARK_LOG_LEVEL="$SPARK_LOG_LEVEL"
export SPARK_MASTER_PORT="$SPARK_MASTER_PORT"
export SPARK_MASTER_WEBUI_PORT="$SPARK_MASTER_WEBUI_PORT"
export SPARK_LOG_MAXFILES="$SPARK_LOG_MAXFILES"
export SPARK_LOG_MAXSIZE="$SPARK_LOG_MAXSIZE"
export SPARK_DAEMON_MEMORY="$SPARK_DAEMON_MEMORY"
export SPARK_DAEMON_JAVA_OPTS="$SPARK_DAEMON_JAVA_OPTS"
EOF

# 8. Inform
echo "✅ spark-env.sh and log4j.properties created at $CONF_DIR"
echo "✅ log4j copied and symlinked at: $SPARK_CONF_LINK"
echo "✅ SPARK_DAEMON_JAVA_OPTS: $SPARK_DAEMON_JAVA_OPTS"

# 9. Export
export SPARK_CONF_DIR="$CONF_DIR"

