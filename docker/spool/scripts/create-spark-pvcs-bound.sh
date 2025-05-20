#!/bin/bash

set -euo pipefail

CLUSTER_NAME=${1:-spark-cluster}
NAMESPACE=${2:-spark}
NUM_SGX=${3:-0}
NUM_DIRECT=${4:-10}
WORKERS_PER_NODE=${5:-1}

echo "📦 Preparing PVCs for cluster [$CLUSTER_NAME] in namespace [$NAMESPACE]..."

create_pvc() {
  local POD_NAME=$1
  local TYPE=$2  # "data" or "logs"
  local SIZE=$3
  local PVC_NAME="${TYPE}-${CLUSTER_NAME}-${POD_NAME}"
  
  sleep 2
  echo "🧹 Deleting old PVC [$PVC_NAME] if exists..."
  kubectl delete pvc "$PVC_NAME" -n "$NAMESPACE" --ignore-not-found

  echo "🪵 Creating PVC [$PVC_NAME] with size $SIZE..."
  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${SIZE}
EOF
}

create_pod_pvcs() {
  local POD=$1
  create_pvc "$POD" "data" "10Gi"
  create_pvc "$POD" "logs" "1Gi"
}


# Master PVCs
create_pod_pvcs "spark-master-1" 
# create_pod_pvcs "spark-master-2"

# SGX Workers
if [ "$NUM_SGX" -gt 0 ]; then
    for i in $(seq 1 "$NUM_SGX"); do
        for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
            create_pod_pvcs "sgx-worker-${i}-${j}"
        done
    done
fi


# Direct Workers
for i in $(seq 1 "$NUM_DIRECT"); do
  for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
    create_pod_pvcs "direct-worker-${i}-${j}"
  done
done

# === Clean-up PVCs not matching expected pattern ===
echo "🧹 Cleaning unexpected PVCs in namespace [$NAMESPACE]..."

EXPECTED_PATTERNS=()
EXPECTED_PATTERNS+=("data-${CLUSTER_NAME}-spark-master-1")
EXPECTED_PATTERNS+=("logs-${CLUSTER_NAME}-spark-master-1")
# EXPECTED_PATTERNS+=("data-${CLUSTER_NAME}-spark-master-2")
# EXPECTED_PATTERNS+=("logs-${CLUSTER_NAME}-spark-master-2")

for i in $(seq 1 "$NUM_SGX"); do
  for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
    EXPECTED_PATTERNS+=("data-${CLUSTER_NAME}-sgx-worker-${i}-${j}")
    EXPECTED_PATTERNS+=("logs-${CLUSTER_NAME}-sgx-worker-${i}-${j}")
  done
done

for i in $(seq 1 "$NUM_DIRECT"); do
  for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
    EXPECTED_PATTERNS+=("data-${CLUSTER_NAME}-direct-worker-${i}-${j}")
    EXPECTED_PATTERNS+=("logs-${CLUSTER_NAME}-direct-worker-${i}-${j}")
  done
done

EXISTING_PVCS=$(kubectl get pvc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

for pvc in $EXISTING_PVCS; do
  if ! printf '%s\n' "${EXPECTED_PATTERNS[@]}" | grep -qx "$pvc"; then
    echo "❌ PVC [$pvc] is unexpected. Deleting..."
    kubectl delete pvc "$pvc" -n "$NAMESPACE"
  fi
done

echo "✅ PVC creation and cleanup complete for cluster [$CLUSTER_NAME]."
