#!/usr/bin/env bash
set -e

# === Configurable directories ===
SRC_DIR="./tests"
CLASS_DIR="./build"
JAR_DIR="./jars"
REF_OUT_DIR="./test-outputs"
LOG_DIR="./test-logs"

# === Build config flags with defaults ===
DEBUG="${DEBUG:-0}"
SGX="${SGX:-0}"
EDMM="${EDMM:-0}"

# === Reference output generation ===
echo "🔍 Generating reference outputs..."
for src in "$SRC_DIR"/*.java; do
    name=$(basename "$src" .java)
    echo "🧪 Running $name without Gramine to get reference output..."
    java -jar "$JAR_DIR/$name.jar" > "$REF_OUT_DIR/$name.out"
done


# === Gramine testing ===
echo "🧪 Running tests under Gramine..."
for jar in "$JAR_DIR"/*.jar; do
    name=$(basename "$jar" .jar)
    echo "🚀 Testing $name under Gramine..."
    GRAMINE_BIN="gramine-direct"
    [ "$SGX" -eq 1 ] && GRAMINE_BIN="gramine-sgx"

    OUTPUT="$LOG_DIR/${name}_gramine.out"
    $GRAMINE_BIN java -jar "$jar" > "$OUTPUT" 2>&1 || {
        echo "❌ Gramine failed for $name. Check $OUTPUT"
        continue
    }

    if diff -q "$OUTPUT" "$REF_OUT_DIR/$name.out" >/dev/null; then
        echo "✅ $name output matches reference"
    else
        echo "❌ $name output differs! See:"
        echo "  - Reference: $REF_OUT_DIR/$name.out"
        echo "  - Actual   : $OUTPUT"
    fi

done
