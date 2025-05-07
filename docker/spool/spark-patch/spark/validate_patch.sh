#!/usr/bin/env bash
set -euo pipefail

cd spark 
SPARK_SRC="/opt/spark-sc"
SPARK_JARS="$SPARK_SRC/jars"
SEARCH_STRING="Original JVM launch command:"
EXPECTED_CLASS="org/apache/spark/deploy/worker/ExecutorRunner.class"

echo "📦 Searching for rebuilt JARs to copy..."

# Find all jars under target directories
JARS_TO_COPY=$(find "$SPARK_SRC" -type f -path "*/target/*.jar" -name "*.jar" | grep -v "original-" | grep -v "sources")

if [ -z "$JARS_TO_COPY" ]; then
    echo "❌ No compiled JARs found under target directories!"
    exit 1
fi

echo "✅ Found the following JARs to copy:"
echo "$JARS_TO_COPY"

echo "📁 Copying JARs to $SPARK_JARS..."
for jar in $JARS_TO_COPY; do
    cp "$jar" "$SPARK_JARS/"
done

echo "🔍 Validating patch: looking for log string '$SEARCH_STRING'..."
MATCHED=0
for jar in $JARS_TO_COPY; do
    if unzip -p "$jar" | strings | grep -q "$SEARCH_STRING"; then
        echo "✅ Patch detected in: $(basename "$jar")"
        MATCHED=1
    fi
done

if [ "$MATCHED" = 0 ]; then
    echo "❌ Patch log string not found in any copied jar."
    exit 1
fi

echo "🚀 All patched jars copied and validated successfully."
