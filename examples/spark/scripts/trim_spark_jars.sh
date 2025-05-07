#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SPARK_JARS_DIR="/opt/spark/jars"
MINIMAL_JARS_DIR="$SCRIPT_DIR/../minimal-jars"

# Clean output
rm -rf "$MINIMAL_JARS_DIR"
mkdir -p "$MINIMAL_JARS_DIR"

# Essential patterns
ESSENTIAL_PATTERNS=(
  "spark-core.*\\.jar"
  "spark-network-common.*\\.jar"
  "spark-network-shuffle.*\\.jar"
  "spark-launcher.*\\.jar"
  "spark-unsafe.*\\.jar"
  "spark-tags.*\\.jar"
  "spark-sql.*\\.jar"
  "scala-library.*\\.jar"
  "slf4j-api.*\\.jar"
  "slf4j-log4j12.*\\.jar"
  "log4j.*\\.jar"
  "commons-configuration2.*\\.jar"
  "commons-lang3.*\\.jar"
  "commons-collections.*\\.jar"
  "commons-logging.*\\.jar"             # ✅ NEW
  "protobuf-java.*\\.jar"
  "netty-all.*\\.jar"
  "jackson-core.*\\.jar"                # ✅ NEW
  "jackson-databind.*\\.jar"            # ✅ NEW
  "jackson-annotations.*\\.jar"         # ✅ NEW
)

echo "🔍 Copying minimal essential Spark jars..."

for pattern in "${ESSENTIAL_PATTERNS[@]}"; do
  find "$SPARK_JARS_DIR" -maxdepth 1 -type f -regextype posix-extended -regex ".*/$pattern" -exec cp {} "$MINIMAL_JARS_DIR" \;
done

echo "✅ Slimmed jars copied to $MINIMAL_JARS_DIR"

