#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/YOUR_ORG/weave-artifacts.git"
REPO_DIR="weave-artifacts"
EXAMPLES_DIR="$REPO_DIR/examples/spark-experiments"
DATA_DIR="$EXAMPLES_DIR/data"
OUTPUT_DIR="$EXAMPLES_DIR/output"
FAT_JAR="$EXAMPLES_DIR/target/scala-2.12/experiments-fat.jar"

echo "🔍 Checking for weave-artifacts repo..."
if [ ! -d "$REPO_DIR" ]; then
    git clone "$REPO_URL"
fi

echo "📦 Switching to example directory: $EXAMPLES_DIR"
cd "$EXAMPLES_DIR"

echo "📁 Creating data and output directories..."
mkdir -p "$DATA_DIR" "$OUTPUT_DIR"

echo "⬇️ Downloading datasets..."
if [ ! -f "$DATA_DIR/enron.tsv" ]; then
    wget -O "$DATA_DIR/enron.tsv" https://path-to/enron.tsv
fi

if [ ! -f "$DATA_DIR/nyc_taxi.csv" ]; then
    wget -O "$DATA_DIR/nyc_taxi.csv" https://path-to/nyc_taxi.csv
fi

echo "⚙️ Building experiment fat jar..."
make build-fatjar

echo "🚀 Submitting Spark job with Weave shuffle manager..."

# Example: Histogram on Enron
spool spark-submit \
    --context enron-hist \
    --class SparkMapReduceJobs \
    --mode direct \
    --profiling \
    --shuffler weave \
    "$FAT_JAR" \
    "$DATA_DIR/enron.tsv" hist "$OUTPUT_DIR/enron_hist"

# Example: PageRank on NYC Taxi
spool spark-submit \
    --context nytaxi-pr \
    --class SparkMapReduceJobs \
    --mode direct \
    --profiling \
    --shuffler weave \
    "$FAT_JAR" \
    "$DATA_DIR/nyc_taxi.csv" pagerank "$OUTPUT_DIR/nytaxi_pr" 10

echo "✅ Jobs completed."
echo "📂 Results available in: $OUTPUT_DIR"
