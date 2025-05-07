#!/bin/bash
  
# Move to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

# Usage
if [ -z "$1" ]; then
  echo "Usage: $0 <ACR_NAME> [--debug] [--test]"
  exit 1
fi

ACR_NAME=$1
PLATFORM="linux/amd64"
REGISTRY="$ACR_NAME.azurecr.io"
IMAGE_NAME="spark-gramine-direct"
TAG="latest"
DOCKERFILEPATH="."

# Optional flags
DEBUG_LOGGING=0
ENABLE_TEST=0

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      echo "🐞 Debug mode enabled — build logs will be saved in /log"
      DEBUG_LOGGING=1
      shift
      ;;
    --test)
      echo "🧪 Test mode enabled — full build with test dependencies and repo compilation"
      ENABLE_TEST=1
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Log in to ACR
echo "🔐 Logging in to Azure Container Registry: $REGISTRY"
az acr login --name "$ACR_NAME"

# Architecture check
HOST_ARCH=$(uname -m)
if [[ "$HOST_ARCH" != "x86_64" ]]; then
  echo "⚠️  Host architecture is $HOST_ARCH, but image is for $PLATFORM."
fi

# Prepare repos
source github_auth.env
./scripts/prepare-repos.sh || {
  echo "❌ Failed to prepare repositories."
  exit 1
}
REPO_STATE_HASH=$(cat private-clones/.repos-hash)
echo "🔑 Using REPO_STATE_HASH: $REPO_STATE_HASH"
echo "$REPO_STATE_HASH" > "$DOCKERFILEPATH/.last_repo_hashes"

# Decide on build target stage
if [[ "$ENABLE_TEST" == "1" ]]; then
  TARGET_STAGE="final-with-tests"
else
  TARGET_STAGE="final-without-tests"
fi

# Build image
BUILD_LOG="/tmp/docker_build_$(date +%s).log"
echo "🛠️ Building Docker image [$IMAGE_NAME:$TAG] for target [$TARGET_STAGE]..."
DOCKER_BUILDKIT=1 docker buildx build \
  --build-arg GITHUB_USERNAME="$GITHUB_USERNAME" \
  --build-arg GITHUB_TOKEN="$GITHUB_TOKEN" \
  --build-arg DEBUG_LOGGING="$DEBUG_LOGGING" \
  --build-arg TEST="$ENABLE_TEST" \
  --build-arg REPO_STATE_HASH="$REPO_STATE_HASH" \
  --platform="$PLATFORM" \
  --target "$TARGET_STAGE" \
  -t "$REGISTRY/$IMAGE_NAME:$TAG" \
  --load "$DOCKERFILEPATH" \
  | tee "$BUILD_LOG"

# Error handling
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "❌ Docker build failed! See logs at $BUILD_LOG"
  exit 1
fi

echo "✅ Build successful"
echo "$REPO_STATE_HASH" > "$DOCKERFILEPATH/.last_successful_build"

# Push if digest changed
LOCAL_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REGISTRY/$IMAGE_NAME:$TAG" | cut -d'@' -f2 || echo "none")
REMOTE_DIGEST=$(az acr repository show-manifests --name "$ACR_NAME" --repository "$IMAGE_NAME" --query "[?tags[?contains(@, '$TAG')]].digest" -o tsv || echo "none")

if [ "$LOCAL_DIGEST" == "$REMOTE_DIGEST" ]; then
  echo "✅ No changes in image. Skipping push."
else
  echo "📤 Pushing updated image..."
  docker push "$REGISTRY/$IMAGE_NAME:$TAG"
  echo "✅ Push complete."
fi
