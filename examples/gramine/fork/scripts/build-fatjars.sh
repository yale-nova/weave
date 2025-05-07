#!/usr/bin/env bash
set -euo pipefail

# Always operate relative to the root of the project (one directory above scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."

SRC_DIR="$PROJECT_ROOT/src/fork/scala"
JAR_DIR="$PROJECT_ROOT/fork-jars"
REBUILD=1  # default: rebuild everything

# Parse flags
if [[ "${1:-}" == "--no-rebuild" ]]; then
    REBUILD=0
fi

mkdir -p "$JAR_DIR"

echo "🔍 Looking for ForkTestSuite.scala in $SRC_DIR..."

if [[ ! -f "$SRC_DIR/ForkTestSuite.scala" ]]; then
    echo "❌ ForkTestSuite.scala not found in $SRC_DIR!"
    exit 1
fi

JAR_PATH="$JAR_DIR/ForkTestSuite.jar"

if [[ "$REBUILD" -eq 0 && -f "$JAR_PATH" && "$JAR_PATH" -nt "$SRC_DIR/ForkTestSuite.scala" ]]; then
    echo "⚡ Skipping rebuild — JAR is up-to-date"
else
    echo "🔨 Building fat jar for ForkTestSuite"

    cd "$PROJECT_ROOT"  # <-- important: run sbt from root
    rm -rf target
    sbt clean assembly
    cp target/scala-2.13/fork-tests-assembly.jar "$JAR_PATH"
    echo "✅ Built: $JAR_PATH"
fi

echo "📦 ForkTestSuite.jar saved in fork-jars/"

