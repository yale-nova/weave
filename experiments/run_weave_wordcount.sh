#!/bin/bash
set -euo pipefail

# === Step 1: Clone and Build Weave Shuffle ===
echo "🔄 Cloning and building spark-weave-shuffle..."
git clone https://github.com/mattslm/spark-weave-shuffle.git
cd spark-weave-shuffle
sbt package

# === Step 2: Set Paths ===
JAR_PATH="target/scala-2.12/spark-weave-shuffle_2.12-0.1.0.jar"
SPARK_JAR="$SPARK_HOME/examples/jars/spark-examples_2.12-3.2.2.jar"
INPUT_FILE="../examples/gramine/java/data/input.txt"

if [ ! -f "$INPUT_FILE" ]; then
  echo "❌ Input file not found at $INPUT_FILE"
  exit 1
fi

# === Step 3: Run Spark Job with Weave Shuffle ===
echo "🚀 Running Spark WordCount with Weave Shuffle..."

$SPARK_HOME/bin/spark-submit \
  --class org.apache.spark.examples.JavaWordCount \
  --master local[*] \
  --conf spark.shuffle.manager=org.apache.spark.shuffle.weave.WeaveShuffleManager \
  --conf spark.driver.extraClassPath=$JAR_PATH \
  --conf spark.executor.extraClassPath=$JAR_PATH \
  --conf spark.weave.alpha=0.05 \
  --conf spark.weave.beta=0.1 \
  --conf spark.weave.c=2 \
  --conf spark.weave.randomShuffle=PRG \
  --conf spark.weave.histogram=DirectCount \
  --conf spark.weave.balancedShuffle=SimpleGreedyBinPacking \
  --conf spark.weave.fakePadding=RepeatReal \
  --conf spark.weave.shuffleMode=TaggedBatch \
  $SPARK_JAR \
  "$INPUT_FILE"
