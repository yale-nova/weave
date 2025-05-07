#!/bin/bash
set -euo pipefail

JOB=${1:?Job name (e.g., hist, median, pagerank)}
SCALE=${2:?Sampling factor (e.g., 0.1, 1.0, 2.0)}

REPO_DIR="spark-weave-shuffle"
EXAMPLES_DIR="$REPO_DIR/examples"
FULL_DATA_DIR="$EXAMPLES_DIR/data/full"
TMP_DATA_DIR="$EXAMPLES_DIR/data/tmp"
OUTPUT_DIR="$EXAMPLES_DIR/output/${JOB}_${SCALE}"
FAT_JAR="$EXAMPLES_DIR/target/scala-2.12/experiments-fat.jar"

mkdir -p "$TMP_DATA_DIR" "$OUTPUT_DIR"

# Select dataset
if [ "$JOB" == "pagerank" ]; then
  FULL_FILE="$FULL_DATA_DIR/nyc_taxi.csv"
  TMP_FILE="$TMP_DATA_DIR/nyc_taxi_${SCALE}.csv"
else
  FULL_FILE="$FULL_DATA_DIR/enron.tsv"
  TMP_FILE="$TMP_DATA_DIR/enron_${SCALE}.tsv"
fi

# Downsample or oversample
echo "📊 Preparing dataset for scale factor $SCALE..."
if [[ "$SCALE" == "1.0" ]]; then
  cp "$FULL_FILE" "$TMP_FILE"
else
  # If scale < 1, sample lines. If > 1, replicate lines
  python3 - <<EOF
import random, math
input_path = "$FULL_FILE"
output_path = "$TMP_FILE"
scale = float("$SCALE")
lines = open(input_path).readlines()
n = len(lines)
if scale < 1.0:
    sampled = random.sample(lines, int(scale * n))
elif scale > 1.0:
    sampled = lines * int(scale) + random.sample(lines, int((scale % 1) * n))
else:
    sampled = lines
with open(output_path, 'w') as out:
    out.writelines(sampled)
EOF
fi

# Build JAR if needed
echo "⚙️ Building fat JAR..."
cd "$EXAMPLES_DIR"
make build-fatjar

# Submit job with spool
echo "🚀 Submitting Spark job..."
spool spark-submit \
  --context ${JOB}-${SCALE} \
  --class SparkMapReduceJobs \
  --mode direct \
  --profiling \
  --shuffler weave \
  "$FAT_JAR" \
  "$TMP_FILE" "$JOB" "$OUTPUT_DIR" 10

echo "✅ Done. Output in: $OUTPUT_DIR"
