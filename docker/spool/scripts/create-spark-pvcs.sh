#!/bin/bash

set -euo pipefail

CLUSTER_NAME=${1:-spark-cluster}
NAMESPACE=${2:-spark}
NUM_SGX=${3:-2}
NUM_DIRECT=${4:-2}

echo "📦 Preparing PVCs for cluster [$CLUSTER_NAME] in namespace [$NAMESPACE]..."

create_pvc() {
  local POD_NAME=$1
  local TYPE=$2  # "data" or "logs"
  local SIZE=$3
  local PVC_NAME="${TYPE}-${CLUSTER_NAME}-${POD_NAME}"

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
create_pod_pvcs "spark-master-2"

# SGX Workers
for i in $(seq 1 "$NUM_SGX"); do
  create_pod_pvcs "sgx-worker-$i"
done

# Direct Workers
for i in $(seq 1 "$NUM_DIRECT"); do
  create_pod_pvcs "direct-worker-$i"
done

echo "✅ All PVCs created for cluster [$CLUSTER_NAME] in namespace [$NAMESPACE]."
