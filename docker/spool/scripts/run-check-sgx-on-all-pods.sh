#!/bin/bash

set -euo pipefail

NAMESPACE="${1:-spark}"
CMD="/opt/private-repos/weave-artifacts-auto/docker/spool/scripts/check-sgx.sh"

echo "🔍 Listing all pods in namespace [$NAMESPACE]..."
PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')

if [[ -z "$PODS" ]]; then
  echo "❌ No pods found in namespace [$NAMESPACE]"
  exit 1
fi

for pod in $PODS; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🚀 Running SGX check script on pod [$pod]..."
  kubectl exec -n "$NAMESPACE" "$pod" -- bash -c "$CMD" || echo "⚠️ SGX check failed on pod [$pod]"
  echo "✅ Completed [$pod]"
done
