#!/bin/bash
set -euo pipefail

SRC_FILE=$1
DEST_PATH=$2
NAMESPACE=${3:-spark}
SCRATCH_DIR=${4:-"/scratch"}

BASENAME=$(basename "$SRC_FILE")

echo "📤 Copying [$SRC_FILE] to [$DEST_PATH] in all pods under namespace [$NAMESPACE]..."

# Compute source hash
SRC_HASH=$(sha256sum "$SRC_FILE" | awk '{print $1}')

# File permissions
if [[ "$(uname)" == "Darwin" ]]; then
  PERM_MODE=$(stat -f "%Lp" "$SRC_FILE")
else
  PERM_MODE=$(stat -c "%a" "$SRC_FILE")
fi

# Fetch pods
PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Running -l 'role in (direct,sgx,master)' -o jsonpath='{.items[*].metadata.name}')

for POD in $PODS; do
  echo "🔍 Checking pod [$POD]..."

  SCRATCH_PATH="$SCRATCH_DIR/$BASENAME"
  FILE_EXISTS=$(kubectl exec -n "$NAMESPACE" "$POD" -- test -f "$SCRATCH_PATH" && echo "yes" || echo "no")

  if [[ "$FILE_EXISTS" == "yes" ]]; then
    echo "📦 Found existing file at [$SCRATCH_PATH] in pod [$POD], computing hash..."
    DEST_HASH=$(kubectl exec -n "$NAMESPACE" "$POD" -- sha256sum "$SCRATCH_PATH" 2>/dev/null | awk '{print $1}')

    if [[ "$SRC_HASH" != "$DEST_HASH" ]]; then
      echo "⚠️ Hash mismatch. Deleting old file at [$SCRATCH_PATH] in [$POD]..."
      kubectl exec -n "$NAMESPACE" "$POD" -- rm -f "$SCRATCH_PATH"
    else
      echo "✅ Matching file exists at [$SCRATCH_PATH]. No need to delete."
    fi
  else
    echo "ℹ️ No file found at [$SCRATCH_PATH] in [$POD]."
  fi

  echo "📁 Copying file to [$POD:$DEST_PATH]..."
  kubectl cp "$SRC_FILE" "$NAMESPACE/$POD:$DEST_PATH"

  echo "🔐 Setting permissions [$PERM_MODE] on [$DEST_PATH] in [$POD]..."
  kubectl exec -n "$NAMESPACE" "$POD" -- chmod "$PERM_MODE" "$DEST_PATH"
done

echo "✅ Done."
