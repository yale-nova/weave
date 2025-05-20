#!/bin/bash

set -e
cd /workspace
source /workspace/env.ssh-spark.sh

LOG_DUMP="helloworld_log_dump"
touch $LOG_DUMP

function log_error {
  echo "hello world failed at $1: $2" >> "$LOG_DUMP"
  exit 1
}

function dump_logs {
  local label="$1"
  shift
  echo -e "\n==== $label ====" >> "$LOG_DUMP"
  for f in "$@"; do
    if [ -f "$f" ]; then
      echo -e "\n==== $f ====" >> "$LOG_DUMP"
      cat "$f" >> "$LOG_DUMP"
    fi
  done
}

export -f dump_logs

echo "📍 Step 0: Validate environment"
command -v spark-submit >/dev/null || log_error "stage 0" "spark-submit not found"
[ -n "$SPARK_HOME" ] || log_error "stage 0" "SPARK_HOME not set"

echo "📍 Step 1: Start mini Spark cluster"
./spark_mini_cluster.sh || log_error "stage 1" "spark_mini_cluster.sh failed"

echo "📍 Step 2: Verify cluster status"
sleep 10
jps
echo "📄 Tail of worker.log:"
tail -n 5 /workspace/worker.log
echo "📄 Tail of master.log:"
tail -n 5 /workspace/master.log

echo "📍 Step 3: Check Gramine and encryption settings"
declare -A config_descriptions=(
  [spark.executor.gramine.enabled]="Enclaved execution using Gramine"
  [spark.shuffle.service.enabled]="Secure shuffle among executors"
  [spark.authenticate]="Authentication of Spark workers"
  [spark.authenticate.enableSaslEncryption]="SASL-based encryption for authentication"
  [spark.io.encryption.enabled]="I/O encryption for data confidentiality at rest"
  [spark.network.crypto.enabled]="Network-level encryption for data in transit"
  [spark.authenticate.secret]="Shared secret used for authentication"
)

while IFS= read -r key; do
  VALUE=$(grep "^$key\\b" /opt/spark/conf/spark-defaults.conf || true)
  DESC=${config_descriptions[$key]}
  if [[ -n "$VALUE" ]]; then
    echo "  - $VALUE  # $DESC"
  else
    echo "  - $key: NOT SET  # $DESC"
  fi
done <<EOF
spark.executor.gramine.enabled
spark.shuffle.service.enabled
spark.authenticate
spark.authenticate.enableSaslEncryption
spark.io.encryption.enabled
spark.network.crypto.enabled
spark.authenticate.secret
EOF

echo "📍 Step 4: Run SparkPi to generate enclave context"
/opt/spark/bin/spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master spark://127.0.0.1:7077 \
  /opt/spark/jars/spark-examples_2.12-3.2.2.jar \
  100 > spark-pi-out.log 2> spark-pi-err.log

[ -s /opt/spark/enclave/java.manifest ] || log_error "stage 4" "Manifest not found or empty"
[ -s spark-pi-out.log ] || log_error "stage 4" "spark-pi-out.log is empty"

PI_RESULT=$(grep -Eo 'Pi is roughly .*' spark-pi-out.log || echo "No Pi result found")
echo "🧮 $PI_RESULT"

if [[ "$PI_RESULT" != "No Pi result found" ]]; then
  echo "ℹ️ Skipping detailed SparkPi log dump — execution looks successful."
else
  echo "📜 Dumping SparkPi logs due to missing Pi output"
  dump_logs "spark-pi logs" spark-pi-out.log spark-pi-err.log /workspace/master.log /workspace/worker.log

  latest_event_dir=$(ls -td /opt/spark/logs/events/app-* 2>/dev/null | head -n 1)
  [ -d "$latest_event_dir" ] && dump_logs "event logs" "$latest_event_dir"/*

  latest_work_dir=$(ls -td /opt/spark/work/app-* 2>/dev/null | head -n 1)
  [ -d "$latest_work_dir" ] && find "$latest_work_dir" -type f \( -name "stdout" -o -name "stderr" \) -exec bash -c 'dump_logs "executor logs" "$@"' bash {} +
fi

echo "📍 Step 5: Run HelloWorld WordCount"
./helloworld/HelloWorldContainerWordCount.sh > wordcount-out.log 2> wordcount-err.log

EXPECTED="the             -> 2142"
grep -q "$EXPECTED" wordcount-out.log || { dump_logs "wordcount failure" wordcount-out.log wordcount-err.log; log_error "stage 5" "expected output not found"; }

echo "✅ WordCount output verified"

echo "📍 Step 6: Run HelloWorld Sort"
./helloworld/HelloWorldContainerSort.sh > sort-out.log 2> sort-err.log

echo "📍 Step 7: Parse timing CSVs"
python3 parse-times.py sort-err.log ./helloworld/HelloWorldContainerSort.sh || log_error "stage 7" "failed parsing sort-err.log"
python3 parse-times.py wordcount-err.log ./helloworld/HelloWorldContainerWordCount.sh || log_error "stage 7" "failed parsing wordcount-err.log"

echo "📍 Step 8: Validate CSVs and print Real Overhead"
for f in sort-err.csv wordcount-err.csv; do
  if [ -f "$f" ]; then
    echo "📊 Overhead summary for $f:"
    awk -F, 'NR>1 { print $1 ": " $5 }' "$f"
  else
    log_error "stage 8" "$f not found"
  fi
done

echo "🎉 Step 9: Hello World test completed successfully."