!/bin/bash

set -e

# Move to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

IMAGE_NAME="gramine-ubuntu"
PLATFORM="linux/amd64"

# Detect host architecture
HOST_ARCH=$(uname -m)

if [[ "$HOST_ARCH" != "x86_64" ]]; then
  echo "⚠️  WARNING: Host architecture is $HOST_ARCH, but the image is being built for $PLATFORM."
  echo "   Gramine only supports SGX on x86_64 platforms. The image may not run correctly on this host."
fi

echo "🛠️  Building Docker image [$IMAGE_NAME] for platform [$PLATFORM]..."

docker buildx build --platform=$PLATFORM -t $IMAGE_NAME --load .

echo "✅ Build complete."

