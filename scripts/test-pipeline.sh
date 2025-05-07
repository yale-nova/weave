#!/bin/bash
set -euo pipefail

echo "🧪 Testing Spool + Weave + SparkMapReduce end-to-end..."

# Parameters
JOB="hist"
SCALE="0.1"
FULL_DATA="examples/data/full/enron.tsv"
SAMPLED="examples/data/tmp/enron_sampled_0.1.tsv"
OUTPUT_DIR="examples/output/test_hist_0.1"
FAT_JAR="examples/target/scala-2.12/experiments-fat.jar"

# 1. Run sampling
echo "🔍 Running SamplingJob..."
spool spark-submit \
  --context test-sample \
  --class SamplingJob \
  --mode direct \
  --shuffler weave \
  "$FAT_JAR" "$FULL_DATA" "$SAMPLED" "$SCALE"

# 2. Check if sampling output exists
if [ ! -f "$SAMPLED/part-00000" ]; then
  echo "❌ Sampling failed. No output found."
  exit 1
else
  echo "✅ Sampling output found: $SAMPLED"
fi

# 3. Run actual job
echo "🚀 Running SparkMapReduceJob: $JOB..."
spool spark-submit \
  --context test-hist \
  --class SparkMapReduceJobs \
  --mode direct \
  --profiling \
  --shuffler weave \
  "$FAT_JAR" "$SAMPLED" "$JOB" "$OUTPUT_DIR"

# 4. Validate output
if [ -f "$OUTPUT_DIR/part-00000" ]; then
  echo "✅ Job completed successfully: $JOB"
else
  echo "❌ Job failed. Output not found."
  exit 1
fi

echo "🎉 All tests passed."
