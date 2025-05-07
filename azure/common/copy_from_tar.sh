#!/bin/bash
set -euo pipefail

# Usage
usage() {
  echo "Usage: $0 --container-path=CONTAINER_PATH --host-path=HOST_PATH [--resource-group=RESOURCE_GROUP] [--container-name=CONTAINER_NAME]"
  exit 1
}

# Defaults
resource_group="weave-ae"
container_name="weavec1"

# Parse args
for arg in "$@"; do
  case $arg in
    --container-path=*)
      container_path="${arg#*=}";;
    --host-path=*)
      host_path="${arg#*=}";;
    --resource-group=*)
      resource_group="${arg#*=}";;
    --container-name=*)
      container_name="${arg#*=}";;
    *)
      echo "Unknown argument: $arg"; usage;;
  esac
done

# Required args check
if [[ -z "${container_path:-}" || -z "${host_path:-}" ]]; then
  echo "Error: --container-path and --host-path are required."; usage
fi

# Expand ~
host_path="${host_path/#\~/$HOME}"
[[ "$host_path" == "/" ]] && { echo "Refusing to extract to root"; exit 1; }

# Temp archive path in container
archive_path="/tmp/container_copy.tar.gz"

echo "[1/6] Creating archive in container..."
az container exec \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --exec-command "tar czf $archive_path -C $(dirname "$container_path") $(basename "$container_path")"

echo "[2/6] Starting HTTP server in background and saving PID..."
az container exec \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --exec-command "nohup python3 -m http.server 8080 --directory /tmp > /tmp/http.log 2>&1 & echo \$! > /tmp/http.pid"

echo "[3/6] Getting container IP..."
container_ip=$(az container show \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --query ipAddress.ip -o tsv)

[[ -z "$container_ip" ]] && { echo "Error: Could not get container IP."; exit 1; }

echo "[4/6] Downloading archive from $container_ip..."
mkdir -p "$host_path"
curl --retry 10 --retry-delay 2 --fail http://$container_ip:8080/container_copy.tar.gz -o /tmp/container_copy.tar.gz

echo "[5/6] Shutting down HTTP server in container..."
az container exec \
  --resource-group "$resource_group" \
  --name "$container_name" \
  --exec-command "kill \$(cat /tmp/http.pid) && rm -f /tmp/http.pid"

echo "[6/6] Extracting archive to $host_path..."
tar -xzf /tmp/container_copy.tar.gz -C "$host_path"
rm -f /tmp/container_copy.tar.gz

echo "✅ Done."

