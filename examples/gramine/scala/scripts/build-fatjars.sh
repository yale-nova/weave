#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="src/main/scala"
JAR_DIR="jars"
REBUILD=1  # default: rebuild everything

# Parse flags
if [[ "${1:-}" == "--no-rebuild" ]]; then
    REBUILD=0
fi

mkdir -p "$JAR_DIR"

echo "🔍 Searching for main classes in $SRC_DIR..."

for file in "$SRC_DIR"/*.scala; do
    CLASS=$(basename "$file" .scala)
    JAR_PATH="$JAR_DIR/$CLASS.jar"

    if [[ "$REBUILD" -eq 0 && -f "$JAR_PATH" && "$JAR_PATH" -nt "$file" ]]; then
        echo "⚡ Skipping $CLASS — JAR is up-to-date"
        continue
    fi

    echo "🔨 Building fat jar for $CLASS"

    rm -rf target  # sbt always reuses target but we clean to avoid cross contamination
    sbt "set assembly / mainClass := Some(\"$CLASS\")" assembly

    cp target/scala-2.13/fatjar-assembly.jar "$JAR_PATH"
    echo "✅ Built: $JAR_PATH"
done

echo "📦 All fat JARs saved to $JAR_DIR"
