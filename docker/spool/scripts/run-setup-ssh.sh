#!/bin/bash

set -e

SCRIPT="scripts/setup-ssh.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "❌ SSH setup script not found at $SCRIPT"
  exit 1
fi

# Get the container name (pick first running container with 'spark' or 'master' in the name, customize as needed)
CONTAINER=$(docker ps --filter "status=running" --format "{{.Names}}" | grep -m1 -E "spark|master|worker")

if [ -z "$CONTAINER" ]; then
  echo "❌ No matching container found. Is your Spark container running?"
  exit 1
fi

echo "📦 Found container: $CONTAINER"
echo "📤 Copying $SCRIPT into container..."

docker cp "$SCRIPT" "$CONTAINER":/tmp/setup-ssh.sh

echo "🚀 Executing setup-ssh.sh inside $CONTAINER..."

docker exec -it "$CONTAINER" bash -c "chmod +x /tmp/setup-ssh.sh && /tmp/setup-ssh.sh"

