#!/bin/bash

# Move to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

set -e

# === 🧾 Usage ===
if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <RG_NAME> <ACR_NAME> <CONTAINER_NAME> <CPU_CORES> <MEMORY_GB>"
  echo "Example: $0 weave-ae graminedirect weavec1 4 16"
  exit 1
fi

# === 🔧 Inputs ===
RG_NAME=$1
ACR_NAME=$2
CONTAINER_NAME=$3
CPU=$4
MEMORY=$5
IMAGE_NAME="$ACR_NAME.azurecr.io/spark-spool-direct:latest"

# === ☑️ Check and Register Microsoft.ContainerInstance ===
echo "🔍 Checking Azure subscription registration for 'Microsoft.ContainerInstance'..."
REGISTRATION_STATE=$(az provider show --namespace Microsoft.ContainerInstance --query "registrationState" -o tsv)

if [ "$REGISTRATION_STATE" != "Registered" ]; then
  echo "⚙️  'Microsoft.ContainerInstance' not registered. Registering now..."
  az provider register --namespace Microsoft.ContainerInstance
  echo "⏳ Waiting for registration to complete..."
  while [[ "$(az provider show --namespace Microsoft.ContainerInstance --query "registrationState" -o tsv)" != "Registered" ]]; do
    sleep 2
    echo "…still waiting..."
  done
  echo "✅ 'Microsoft.ContainerInstance' successfully registered."
else
  echo "✅ 'Microsoft.ContainerInstance' is already registered."
fi

# === 🔥 Delete existing container if it exists ===
EXISTING_CONTAINER=$(az container show --resource-group "$RG_NAME" --name "$CONTAINER_NAME" --query "name" -o tsv 2>/dev/null || echo "")
if [ "$EXISTING_CONTAINER" == "$CONTAINER_NAME" ]; then
  echo "🗑️  Deleting existing container [$CONTAINER_NAME]..."
  az container delete --resource-group "$RG_NAME" --name "$CONTAINER_NAME" --yes
  echo "✅ Deleted previous container [$CONTAINER_NAME]"
fi

# === 🔑 Authenticate ACR ===
echo "🧩 Enabling admin access for ACR [$ACR_NAME]..."
az acr update -n "$ACR_NAME" --admin-enabled true

echo "🔑 Fetching ACR credentials..."
ACR_CREDS=$(az acr credential show --name "$ACR_NAME")
ACR_USERNAME=$(echo "$ACR_CREDS" | jq -r '.username')
ACR_PASSWORD=$(echo "$ACR_CREDS" | jq -r '.passwords[0].value')

# === 🚀 Create new container ===
echo "🚀 Creating container [$CONTAINER_NAME] with $CPU vCPU(s) and $MEMORY GB memory..."

az container create \
  --resource-group "$RG_NAME" \
  --name "$CONTAINER_NAME" \
  --image "$IMAGE_NAME" \
  --cpu "$CPU" \
  --memory "$MEMORY" \
  --registry-login-server "$ACR_NAME.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --restart-policy Never \
  --os-type Linux

echo "⏳ Waiting for container to reach 'Running' state..."
while true; do
  STATE=$(az container show --resource-group "$RG_NAME" --name "$CONTAINER_NAME" --query "instanceView.state" -o tsv)
  echo "Current state: $STATE"
  if [ "$STATE" == "Running" ]; then
    echo "✅ Container is running."
    break
  elif [ "$STATE" == "Failed" ]; then
    echo "❌ Container failed to start. Use 'az container logs' to debug."
    exit 1
  fi
  sleep 2
done

# === 🧪 Health check: exec into container and run command ===
echo "🔍 Running health check inside container..."
az container exec \
  --resource-group "$RG_NAME" \
  --name "$CONTAINER_NAME" \
  --exec-command "echo Hello from inside container!"

echo "✅ Health check completed successfully."

