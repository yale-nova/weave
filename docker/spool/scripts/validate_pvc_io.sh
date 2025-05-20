#!/bin/bash
set -euo pipefail

CLUSTER_NAME=${1:-spark-cluster}
NAMESPACE=${2:-spark}

echo "📦 Validating PVC and scratch I/O for cluster [$CLUSTER_NAME] in namespace [$NAMESPACE]..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Fetching pods in namespace [$NAMESPACE] for cluster [$CLUSTER_NAME]..."
PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')

TEST_FILE="pvc_test_$(date +%s).txt"
TEST_CONTENT="Hello from $CLUSTER_NAME I/O test!"

for POD in $PODS; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Validating I/O for pod: $POD"

  echo "➡️ Writing test file to /opt/spark/enclave/data/"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    /bin/bash -c "echo '$TEST_CONTENT (data)' > /opt/spark/enclave/data/$TEST_FILE"

  echo "➡️ Writing test file to /opt/spark/logs/"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    /bin/bash -c "echo '$TEST_CONTENT (logs)' > /opt/spark/logs/$TEST_FILE"

  echo "➡️ Writing test file to /scratch/"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    /bin/bash -c "echo '$TEST_CONTENT (scratch)' > /scratch/$TEST_FILE"

  echo "📄 Reading back from data PVC:"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    cat /opt/spark/enclave/data/$TEST_FILE || echo "❌ Failed to read data test file"

  echo "📄 Reading back from logs PVC:"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    cat /opt/spark/logs/$TEST_FILE || echo "❌ Failed to read logs test file"

  echo "📄 Reading back from scratch:"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    cat /scratch/$TEST_FILE || echo "❌ Failed to read scratch test file"

  echo "✅ I/O check complete for $POD"
done

echo "🎉 PVC + scratch I/O validation complete for all pods in [$NAMESPACE]."
