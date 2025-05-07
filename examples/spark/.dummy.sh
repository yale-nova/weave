#!/bin/bash
set -euo pipefail
set -x 
MAX_ATTEMPTS=30
ATTEMPT=0

echo "🛠 Simple Attempt Incrementation Script"

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    echo "⏳ Attempt $ATTEMPT..."
    #sleep 1
    ((ATTEMPT++)) || true
done

echo "✅ Reached $MAX_ATTEMPTS attempts. Exiting cleanly."
exit 0

