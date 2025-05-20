#!/bin/bash
set -euo pipefail

SRC_FILE=$1
DEST_PATH=$2
NAMESPACE=${3:-spark}

echo "📤 Copying [$SRC_FILE] to [$DEST_PATH] in all pods under namespace [$NAMESPACE]..."

# Cross-platform way to get octal permission (e.g., 755)
if [[ "$(uname)" == "Darwin" ]]; then
  # macOS
  PERM_MODE=$(stat -f "%Lp" "$SRC_FILE")
else
  # Linux
  PERM_MODE=$(stat -c "%a" "$SRC_FILE")
fi

# Fetch only running pods
PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Running -l 'role in (direct,sgx,master)' -o jsonpath='{.items[*].metadata.name}')

for POD in $PODS; do
  echo "📁 Copying to pod [$POD]..."
  kubectl cp "$SRC_FILE" "$NAMESPACE/$POD:$DEST_PATH"

  echo "🔐 Applying permission mode [$PERM_MODE] to [$DEST_PATH] in [$POD]..."
  kubectl exec -n "$NAMESPACE" "$POD" -- bash -c 'chmod '"$PERM_MODE"' '"$DEST_PATH"
done

echo "✅ File [$SRC_FILE] copied and permissions [$PERM_MODE] applied to all pods at [$DEST_PATH]."
