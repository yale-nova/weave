#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
NAMESPACE=spark
WORKER_CORES=${1:-4}
WORKER_MEMORY=${2:-12g}
WORKER_PER_NODE=${3:-1}
SPARK_PATCH_SRC="$REPO_ROOT/built-spark"
SPARK_MAKEFILE="enclave/Makefile"
SPARK_MANIFEST="enclave/java.manifest.template"
SPARK_EXEC_CLASS="bin/spark-executor-class"
SPARK_PATCH_DEST="/opt/spark"
SPARK_CONF_PATH="$REPO_ROOT/built-spark/conf/spark-defaults.conf"
SPARK_CONF_DEST="/opt/spark/conf"

# Step 1: Get master pod name
MASTER_PODS=$(kubectl get pods -n "$NAMESPACE" -l role=master -o jsonpath='{.items[0].metadata.name}')
echo "🧠 Master pods detected: $MASTER_PODS"

echo "🛠️ Generating /etc/hosts helper content..."
HOSTS_HELPER="hosts.helper"
echo "# Spark cluster host mappings" > "$HOSTS_HELPER"


# Generate hosts.helper
echo "# Spark cluster host mappings" > "$HOSTS_HELPER"

WORKER_IPS=$(kubectl get pods -n "$NAMESPACE" -l 'role in (sgx,direct),app=spark-worker' -o jsonpath='{range .items[*]}{.status.podIP} {.metadata.name}{"\n"}{end}')
MASTER_IPS=$(kubectl get pods -n "$NAMESPACE" -l role=master -o jsonpath='{range .items[*]}{.status.podIP} {.metadata.name}{"\n"}{end}')
ALL_PODS_IPS="${WORKER_IPS}\n${MASTER_IPS}"

WORKER_PODS=$(kubectl get pods -n "$NAMESPACE" -l 'role in (sgx,direct),app=spark-worker' -o jsonpath='{.items[*].metadata.name}')
MASTER_PODS=$(kubectl get pods -n "$NAMESPACE" -l role=master -o jsonpath='{.items[*].metadata.name}')
ALL_PODS="$WORKER_PODS $MASTER_PODS"

echo -e "$ALL_PODS_IPS" >> "$HOSTS_HELPER"
echo "📄 Generated hosts.helper:"
cat "$HOSTS_HELPER"

echo "📥 Distributing and appending hosts.helper to each pod’s /etc/hosts..."
for POD in $ALL_PODS; do
  echo "  • Updating /etc/hosts in pod [$POD]..."

  kubectl cp "$HOSTS_HELPER" "$NAMESPACE/$POD:/tmp/hosts.helper"

  kubectl exec -n "$NAMESPACE" "$POD" -- bash -c \
    'cat /etc/hosts /tmp/hosts.helper | awk "!seen[\$1]++" > /tmp/hosts.merged && cp /tmp/hosts.merged /etc/hosts'

  kubectl exec -n "$NAMESPACE" "$POD" -- mkdir -p /opt/spark/enclave/helper-files
  kubectl exec -n "$NAMESPACE" "$POD" -- cp /etc/hosts /opt/spark/enclave/helper-files/hosts
done

rm -f "$HOSTS_HELPER"


# Step 2: Kill existing Spark JVMs 
echo "🧹 Killing existing Spark JVMs (master/worker) on all pods..."

ALL_PODS=$(kubectl get pods -n "$NAMESPACE" -l 'role in (sgx,direct),app=spark-worker' -o jsonpath='{.items[*].metadata.name}')
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

echo "📤 Distributing updated patch files to all pods..."
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_CONF_PATH" "$SPARK_CONF_DEST/spark-defaults.conf"
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_PATCH_SRC/$SPARK_MAKEFILE" "$SPARK_PATCH_DEST/$SPARK_MAKEFILE"
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_PATCH_SRC/$SPARK_MANIFEST" "$SPARK_PATCH_DEST/$SPARK_MANIFEST"
"$REPO_ROOT/scripts/copy-updated-file.sh" "$SPARK_PATCH_SRC/$SPARK_EXEC_CLASS" "$SPARK_PATCH_DEST/$SPARK_EXEC_CLASS"

# Step 2: Launch Spark masters
for CLUSTER_ID in 1 1; do
  i = $CLUSTER_ID
  PORT=7077
  WEBUI_PORT=8080
  
  echo "🚀 Starting master [$CLUSTER_ID] on spark-master-${i} (port $PORT / UI $WEBUI_PORT)..."
  MASTER_IP=$(kubectl get pod spark-master-${i} -n spark -o jsonpath='{.status.podIP}')
  kubectl exec -n "$NAMESPACE" spark-master-${i} -- /bin/bash -c "
    mkdir -p /opt/spark/logs/events /opt/spark/logs/master /scratch /opt/spark/enclave/data;
    SPARK_LOCAL_IP=${MASTER_IP} iPROXY_DEBUG="0" /opt/spark/bin/spark-class \
        -Dspark.log.dir=/opt/spark/logs/master \
        -Dspark.history.fs.logDirectory=file:/opt/spark/logs/events \
      org.apache.spark.deploy.master.Master \
      --host $MASTER_IP \
      --port ${PORT} \
      --webui-port ${WEBUI_PORT} >> /opt/spark/logs/spark-master-${i}.log 2>&1 &" \
      > ".log_start_spark_master_${i}.log" 2>&1 &

done

sleep 5

# Step 3: Launch Spark workers
for CLUSTER_ID in 1; do
  MASTER_POD_I="spark-master-${CLUSTER_ID}"
  MASTER_IP=$(kubectl get pod "$MASTER_POD_I" -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
  MASTER_ADDR="spark://$MASTER_IP:7077"
  echo "🔍 Cluster $CLUSTER_ID: Locating SGX and direct workers..."

  WORKER_PODS=$(kubectl get pods -n "$NAMESPACE" -l "cluster=$CLUSTER_ID" -o jsonpath='{.items[*].metadata.name}')

  for POD in $WORKER_PODS; do
    echo "⚙️ Starting worker [$POD] for master [$CLUSTER_ID]..."
    POD_IP=$(kubectl get pod $POD -n spark -o jsonpath='{.status.podIP}')
    kubectl exec -n "$NAMESPACE" "$POD" -- /bin/bash -c "
      mkdir -p /opt/spark/logs/events /opt/spark/logs/workers /scratch /opt/spark/enclave/data;
      SPARK_LOCAL_IP=${POD_IP} PROXY_DEBUG="0" /opt/spark/bin/spark-class \
        -Dspark.log.dir=/opt/spark/logs/workers \
        -Dspark.history.fs.logDirectory=file:/opt/spark/logs/events \
        org.apache.spark.deploy.worker.Worker \
        $MASTER_ADDR \
        --cores $WORKER_CORES \
        --memory $WORKER_MEMORY >> /opt/spark/logs/$POD.log 2>&1 &" \
        > ".log_worker_start_${POD}.log" 2>&1 &

  done
done

sleep 10

# Step 4: Verify cluster registration through UI
MASTER_IP=$(kubectl get svc spark-master-1 -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
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

echo "✅ Spark hybrid clusters started successfully."
