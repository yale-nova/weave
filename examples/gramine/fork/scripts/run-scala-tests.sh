#!/usr/bin/env bash
set -euo pipefail

JAR_DIR="./jars"
LOG_DIR="./test-logs"
mkdir -p "$LOG_DIR"

MODE="gramine"  # default
GRAMINE_BIN="gramine-direct"

# === Handle arguments ===
for arg in "$@"; do
  case "$arg" in
    --native)
      MODE="native"
      ;;
    --sgx)
      GRAMINE_BIN="gramine-sgx"
      ;;
    *)
      echo "❌ Unknown option: $arg"
      echo "Usage: $0 [--native] [--sgx]"
      exit 1
      ;;
  esac
done

echo "🧪 Running Scala test suite in \033[1m$MODE\033[0m mode..."
echo "=========================================================="

for jar in "$JAR_DIR"/*.jar; do
    name=$(basename "$jar" .jar)
    output_file="$LOG_DIR/${name}_${MODE}.out"

    echo -e "\n🔹 Running test: \033[1m$name\033[0m"
    echo "🔸 Mode: $MODE"
    echo "🔸 Logging to: $output_file"
    echo "----------------------------------------------------------"

    if [[ "$MODE" == "native" ]]; then
        if java -jar "$jar" > "$output_file" 2>&1; then
            echo -e "\033[32m✅ $name passed [native]\033[0m"
        else
            echo -e "\033[31m❌ $name failed [native]\033[0m"
            echo "📄 See logs in: $output_file"
        fi
    else
        if $GRAMINE_BIN java -jar "$jar" > "$output_file" 2>&1; then
            echo -e "\033[32m✅ $name passed [$GRAMINE_BIN]\033[0m"
        else
            echo -e "\033[31m❌ $name failed [$GRAMINE_BIN]\033[0m"
            echo "📄 See logs in: $output_file"
        fi
    fi
    echo "=========================================================="
done
