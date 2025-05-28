#!/bin/bash

# Usage: ./deploy_file.sh <file> <dst_path> host1 host2 ...
# Example: ./deploy_file.sh spark-weave.jar /opt/spark/jars spark-worker-1 spark-worker-2

set -euo pipefail

FILE="$1"
DST="$2"
shift 2
HOSTS=("$@")

if [[ ! -f "$FILE" ]]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

BASENAME=$(basename "$FILE")
LOCAL_HASH=$(sha256sum "$FILE" | awk '{print $1}')

for HOST in "${HOSTS[@]}"; do
  echo "📤 [$HOST] Copying $FILE to ~/"
  scp "$FILE" "$HOST:~/"

  echo "🔐 [$HOST] Deploying to $DST and verifying..."
  ssh "$HOST" "bash -s" <<EOF
set -e

sudo cp ~/$BASENAME "$DST/" && rm -f ~/$BASENAME

echo -n '✅ [$HOST] SHA256 in $DST: '
sudo sha256sum "$DST/$BASENAME" | awk '{print \$1}'

# Clean stale file from /scratch if hash mismatches
if [ -f "/scratch/$BASENAME" ]; then
  SCRATCH_HASH=\$(sha256sum "/scratch/$BASENAME" | awk '{print \$1}')
  if [ "\$SCRATCH_HASH" != "$LOCAL_HASH" ]; then
    echo "🧹 [$HOST] Removing stale /scratch/$BASENAME (hash mismatch)"
    sudo rm -f "/scratch/$BASENAME"
  else
    echo "✅ [$HOST] /scratch/$BASENAME matches current hash"
  fi
else
  echo "ℹ️ [$HOST] No file in /scratch to clean"
fi
EOF

done
