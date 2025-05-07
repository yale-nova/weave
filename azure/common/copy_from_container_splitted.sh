#!/bin/bash
set -euo pipefail

# Help message
usage() {
  echo "Usage: $0 --container-path=CONTAINER_PATH --host-path=HOST_PATH [--resource-group=RESOURCE_GROUP] [--container-name=CONTAINER_NAME]"
  exit 1
}

# Defaults
resource_group="weave-ae"
container_name="weavec1"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --container-path=*) container_path="${arg#*=}" ;;
    --host-path=*) host_path="${arg#*=}" ;;
    --resource-group=*) resource_group="${arg#*=}" ;;
    --container-name=*) container_name="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; usage ;;
  esac
done

# Validate required arguments
if [[ -z "${container_path:-}" || -z "${host_path:-}" ]]; then
  echo "Error: --container-path and --host-path are required."
  usage
fi

# Expand ~ to $HOME
host_path="${host_path/#\~/$HOME}"

# Safety check
if [[ "$host_path" == "/" ]]; then
  echo "Error: host path is root (/). Refusing to continue."
  exit 1
fi

# Step 0: Announce and list container contents
echo "📋 Listing contents in container path: $container_path"
az container exec \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --exec-command "find $container_path -type f" \
  --query 'content' -o tsv

echo -e "\n⬆️  These files will be copied to $host_path. Continue? (y/n): "
read -r confirm
if [[ "$confirm" != "y" ]]; then
  echo "Aborted."
  exit 0
fi

# Step 1: Create archive
echo "[1/4] Creating archive in container..."
az container exec \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --exec-command "tar czf /tmp/container_copy.tar.gz -C $(dirname "$container_path") $(basename "$container_path")" > /dev/null

# Step 2: Stream base64 safely
echo "[2/4] Base64 encoding archive in container (stream-safe)..."
az container exec \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --exec-command "base64 /tmp/container_copy.tar.gz" > /tmp/container_copy.b64

# Step 3: Decode archive on host
echo "[3/4] Decoding archive on host..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    base64 -D -i /tmp/container_copy.b64 -o /tmp/container_copy.tar.gz
else
    base64 -d /tmp/container_copy.b64 > /tmp/container_copy.tar.gz
fi

# Verify archive integrity
if ! tar -tzf /tmp/container_copy.tar.gz > /dev/null 2>&1; then
  echo "❌ Archive appears to be corrupted. Aborting extraction."
  exit 1
fi

# Step 4: Extract archive
echo "[4/4] Extracting to $host_path..."
mkdir -p "$host_path"
tar -xzf /tmp/container_copy.tar.gz -C "$host_path"

echo "✅ Done."

