#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
NAMESPACE=spark
WORKER_CORES=${1:-4}
WORKER_MEMORY=${2:-6g}
WORKERS_PER_POD=${3:-3}  # 🔧 Accepts number of workers per pod
SPARK_CONF_PATH="$REPO_ROOT/built-spark/conf/spark-defaults.conf"
SPARK_CONF_DEST="/opt/spark/conf"
WORKER_UI_BASE_PORT=9000  # 🔧 Base UI port for workers
WEBUI_LOG="$REPO_ROOT/specs/spark_webuis.txt"
SPARK_PATCH_SRC="$REPO_ROOT/built-spark"
SPARK_MAKEFILE="enclave/Makefile"
SPARK_EXEC_CLASS="bin/spark-executor-class"
SPARK_PATCH_DEST="/opt/spark"
rm -f "$WEBUI_LOG"

# Step 1: Get master pod name
MASTER_POD=$(kubectl get pods -n "$NAMESPACE" -l role=master -o jsonpath='{.items[0].metadata.name}')
echo "🧠 Master pod detected: $MASTER_POD"

echo "🧹 Killing existing Spark JVMs (master/worker) on all pods..."

ALL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=spark-worker -o jsonpath='{.items[*].metadata.name}')
ALL_PODS="$ALL_PODS $MASTER_POD"

echo "📋 Pods detected:"
for POD in $ALL_PODS; do
  echo "  • $POD"
done

for POD in $ALL_PODS; do
  echo "🛑 Killing Spark JVMs in pod [$POD]..."
  kubectl exec -n "$NAMESPACE" "$POD" -- bash -c "
    ps -eo pid,cmd | grep -E 'org\.apache\.spark\.deploy\.(master|worker)\.Master|Worker' | grep -v grep | awk '{print \$1}' | xargs --no-run-if-empty kill -9
  " || echo "⚠️ No Spark JVM found in $POD"
done

sleep 10

# Default ports for each cluster
MASTER_PORTS=(7077 7078)
UI_PORTS=(8080 8081)

echo "📤 Distributing updated patch files to all pods..."
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_CONF_PATH" "$SPARK_CONF_DEST/spark-defaults.conf"
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_PATCH_SRC/$SPARK_MAKEFILE" "$SPARK_PATCH_DEST/$SPARK_MAKEFILE"
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_PATCH_SRC/$SPARK_EXEC_CLASS" "$SPARK_PATCH_DEST/$SPARK_EXEC_CLASS"

echo "🚀 Starting Spark masters..."
for CLUSTER_ID in 0 1; do
  PORT="${MASTER_PORTS[$CLUSTER_ID]}"
  WEBUI_PORT="${UI_PORTS[$CLUSTER_ID]}"

  echo "▶️ Starting master [$CLUSTER_ID] on $MASTER_POD (port $PORT / UI $WEBUI_PORT)..."
  kubectl exec -n "$NAMESPACE" "$MASTER_POD" -- /bin/bash -c "
    mkdir -p /opt/spark/logs/events /opt/spark/logs/master /scratch /opt/spark/enclave/data;
    /opt/spark/bin/spark-class \
        -Dspark.log.dir=/opt/spark/logs/master \
        -Dspark.history.fs.logDirectory=file:/opt/spark/logs/events \
      org.apache.spark.deploy.master.Master \
      --host $MASTER_POD \
      --port ${PORT} \
      --webui-port ${WEBUI_PORT} \
      >> /opt/spark/logs/master_${CLUSTER_ID}.log 2>&1 &" \
      > ".log_start_spark_master_${CLUSTER_ID}.log" 2>&1 &
done

sleep 5

# Step 3: Launch multiple Spark workers per pod
echo "⚙️ Launching Spark workers..."
for CLUSTER_ID in 0 1; do
  MASTER_ADDR="spark://$MASTER_POD:${MASTER_PORTS[$CLUSTER_ID]}"
  echo "🔍 Cluster $CLUSTER_ID: Locating worker pods..."

  WORKER_PODS=$(kubectl get pods -n "$NAMESPACE" -l "cluster=$CLUSTER_ID" -o jsonpath='{.items[*].metadata.name}')
  POD_INDEX=0

  for POD in $WORKER_PODS; do
    for ((i=0; i<WORKERS_PER_POD; i++)); do
      UI_PORT=$((WORKER_UI_BASE_PORT + CLUSTER_ID * 100 + POD_INDEX * WORKERS_PER_POD + i))  # 🔧 ensure uniqueness
      SHUFFLE_PORT=$((7337 + CLUSTER_ID * 100 + POD_INDEX * WORKERS_PER_POD + i))
      echo "🧱 Starting worker $i in pod [$POD] with UI port $UI_PORT and shuffle port $SHUFFLE_PORT..."
      kubectl exec -n "$NAMESPACE" "$POD" -- /bin/bash -c "
        mkdir -p /opt/spark/logs/events /opt/spark/logs/workers /scratch /opt/spark/enclave/data;
        /opt/spark/bin/spark-class \
          -Dspark.log.dir=/opt/spark/logs/workers \
          -Dspark.history.fs.logDirectory=file:/opt/spark/logs/events \
          -Dspark.worker.webui.port=${UI_PORT} \
          -Dspark.shuffle.service.port=${SHUFFLE_PORT} \
          org.apache.spark.deploy.worker.Worker \
          $MASTER_ADDR \
          --cores $WORKER_CORES \
          --memory $WORKER_MEMORY \
          >> /opt/spark/logs/worker_${POD}_${i}.log 2>&1 &" \
          > ".log_worker_start_${POD}_${i}.log" 2>&1 &
      echo "$POD -> http://$POD:$UI_PORT" >> "$WEBUI_LOG"  # 🔧 log UI address
    done
    ((POD_INDEX++))
  done
done

sleep 10

# Step 4: Verify worker registration
MASTER_IP=$(kubectl get svc "$MASTER_POD" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
echo "🔎 Validating worker registration via Spark Master REST API..."

for CLUSTER_ID in 0 1; do
  PORT="${UI_PORTS[$CLUSTER_ID]}"
  ENDPOINT="http://$MASTER_IP:$PORT/json"
  JSON_FILE=".spark_cluster_${CLUSTER_ID}.json"

  echo "🌐 Checking $ENDPOINT"
  if curl --fail --silent "$ENDPOINT" > "$JSON_FILE"; then
    echo "🧾 Cluster $CLUSTER_ID registered workers:"
    jq '.workers[] | {id, host, cores, memory}' "$JSON_FILE"
  else
    echo "❌ Failed to connect to cluster $CLUSTER_ID REST API at $ENDPOINT"
  fi
done

echo "📒 Worker UI addresses logged at: $WEBUI_LOG"
echo "✅ Spark hybrid clusters started successfully with multiple workers per pod."
