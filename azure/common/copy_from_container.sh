#!/bin/bash
set -euo pipefail

# Help message
usage() {
  echo "Usage: $0 --container-path=CONTAINER_PATH --host-path=HOST_PATH [--resource-group=RESOURCE_GROUP] [--container-name=CONTAINER_NAME]"
  exit 1
}

# Default values
resource_group="weave-ae"
container_name="weavec1"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --container-path=*)
      container_path="${arg#*=}"
      shift
      ;;
    --host-path=*)
      host_path="${arg#*=}"
      shift
      ;;
    --resource-group=*)
      resource_group="${arg#*=}"
      shift
      ;;
    --container-name=*)
      container_name="${arg#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $arg"
      usage
      ;;
  esac
done

# Validate required arguments
if [[ -z "${container_path:-}" || -z "${host_path:-}" ]]; then
  echo "Error: --container-path and --host-path are required."
  usage
fi

# Expand ~ to $HOME in host_path
if [[ "$host_path" == "~"* ]]; then
  host_path="${host_path/#\~/$HOME}"
fi

# Validate path safety
if [[ "$host_path" == "/" ]]; then
  echo "Error: host path is root (/). Refusing to continue."
  exit 1
fi

echo "📋 Listing contents in container path: $container_path"
az container exec   --resource-group "$resource_group"   --name "$container_name"   --exec-command "find $container_path -type f"   --query 'content'   -o tsv

echo -e "\n⬆️  These files will be copied to $host_path. Continue? (y/n): "
read -r confirm
if [[ "$confirm" != "y" ]]; then
  echo "Aborted."
  exit 0
fi

echo "[1/4] Creating archive in container..."
az container exec   --resource-group "$resource_group"   --name "$container_name"   --exec-command "tar czf /tmp/container_copy.tar.gz -C $(dirname "$container_path") $(basename "$container_path")" > /dev/null

echo "[2/4] Base64 encoding archive in container..."
az container exec --resource-group "$resource_group" --name "$container_name" \
  --exec-command "cat /tmp/container_copy.tar.gz" --query content -o tsv | base64 > /tmp/container_copy.b64

echo "[3/4] Decoding archive on host..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    base64 -D -i /tmp/container_copy.b64 -o /tmp/container_copy.tar.gz
else
    # Linux
    base64 -d /tmp/container_copy.b64 > /tmp/container_copy.tar.gz
fi

echo "[4/4] Extracting to $host_path..."
mkdir -p "$host_path"
tar -xzf /tmp/container_copy.tar.gz -C "$host_path"

echo "✅ Done."
