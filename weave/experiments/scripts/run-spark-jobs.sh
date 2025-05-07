#!/bin/bash
set -euo pipefail

JOB=${1:-hist}
INPUT=${2:-input.txt}
OUTPUT=${3:-output}
ITERATIONS=${4:-10}
SHUFFLER_JAR=${5:-""}
SHUFFLER_CLASS=${6:-""}

APP_JAR="SparkMapReduceJobs.jar"
CLASS_NAME="SparkMapReduceJobs"

SPARK_CONF=""
if [[ -n "$SHUFFLER_CLASS" ]]; then
  SPARK_CONF="--conf spark.shuffle.manager=$SHUFFLER_CLASS"
fi

if [[ "$JOB" == "pagerank" ]]; then
  EXTRA_ARGS="$ITERATIONS"
else
  EXTRA_ARGS=""
fi

echo "🚀 Submitting Spark job: $JOB"

spark-submit \
  --class $CLASS_NAME \
  --master yarn \
  --deploy-mode client \
  --jars "$SHUFFLER_JAR" \
  $SPARK_CONF \
  $APP_JAR \
  "$INPUT" "$JOB" "$OUTPUT" $EXTRA_ARGS

