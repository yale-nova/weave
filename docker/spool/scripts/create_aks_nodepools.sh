#!/bin/bash

set -euo pipefail

# === Cluster and Nodepool Setup Only ===

RG_NAME="weave-rg"
CLUSTER_NAME="spark-cluster"
ACR_NAME="graminedirect"
LOCATION="eastus"
PUBLIC_IP_NAME="spark-master-ip"

# Parse arguments
CLUSTER_SIZE=${1:-11}
CORES_PER_NODE=${2:-4}
SGX_WORKERS=${3:-0}
MASTER_CORES=${4:-4}
WORKERS_PER_NODE=${5:-1}

NON_MASTER_NODES=$((CLUSTER_SIZE - 1))
SGX_NODES=$(( SGX_WORKERS < NON_MASTER_NODES ? SGX_WORKERS : NON_MASTER_NODES ))
REGULAR_NODES=$(( NON_MASTER_NODES > SGX_WORKERS ? NON_MASTER_NODES - SGX_WORKERS : 0 ))

SKU_CACHE=".vm_skus_eastus.json"
RESERVED_GB=5

# Fetch or use cached VM SKUs
if [ ! -f "$SKU_CACHE" ]; then
  az vm list-skus --location "$LOCATION" --resource-type "virtualMachines" -o json > "$SKU_CACHE"
fi

get_cached_capability() {
  local vm_size=$1
  local cap_name=$2
  jq -r --arg vm "$vm_size" --arg cap "$cap_name" '.[] | select(.name == $vm) | .capabilities[] | select(.name == $cap) | .value' "$SKU_CACHE" | head -n 1
}

SGX_VM_SIZE="Standard_DC${CORES_PER_NODE}s_v3"
REGULAR_VM_SIZE="Standard_D${CORES_PER_NODE}s_v3"
MASTER_VM_SIZE="Standard_D${MASTER_CORES}s_v3"

validate_or_update_pool() {
  local name=$1 expected_vm_size=$2 expected_max=$3 expected_mode=$4 expected_min=$5

  if [[ "$POOLS_JSON" == "[]" && "$expected_mode" == "System" ]]; then
    az aks create \
      --resource-group "$RG_NAME" \
      --name "$CLUSTER_NAME" \
      --enable-managed-identity \
      --generate-ssh-keys \
      --enable-addons confcom \
      --enable-cluster-autoscaler \
      --nodepool-name "$name" \
      --node-vm-size "$expected_vm_size" \
      --node-count "$expected_max" \
      --min-count "$expected_min" \
      --max-count "$expected_max"
    az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing
    POOLS_JSON=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" -o json)
    return
  fi

  if [[ "$POOLS_JSON" == "[]" && "$expected_mode" == "User" ]]; then
    echo "❌ System node pool must be created first."
    exit 1
  fi

  POOL=$(echo "$POOLS_JSON" | jq -r --arg name "$name" '.[] | select(.name == $name)')

  if [[ -z "$POOL" ]]; then
    az aks nodepool add \
      --resource-group "$RG_NAME" \
      --cluster-name "$CLUSTER_NAME" \
      --name "$name" \
      --node-vm-size "$expected_vm_size" \
      --node-count "$expected_max" \
      --mode "$expected_mode" \
      --enable-cluster-autoscaler \
      --min-count "$expected_min" \
      --max-count "$expected_max" \
      $( [[ "$name" == "sgxpool" ]] && echo "--node-taints sgx=true:NoSchedule --labels sgx=true" ) \
      $( [[ "$name" == "directpool" ]] && echo "--node-taints direct=true:NoSchedule --labels direct=true" )
    return
  fi

  current_vm_size=$(echo "$POOL" | jq -r '.vmSize')
  current_max=$(echo "$POOL" | jq -r '.maxCount')
  current_min=$(echo "$POOL" | jq -r '.minCount')
  current_mode=$(echo "$POOL" | jq -r '.mode')

  if [[ "$current_vm_size" != "$expected_vm_size" ]]; then
    az aks nodepool delete --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" --name "$name" --yes
    az aks nodepool add \
      --resource-group "$RG_NAME" \
      --cluster-name "$CLUSTER_NAME" \
      --name "$name" \
      --node-vm-size "$expected_vm_size" \
      --node-count "$expected_max" \
      --mode "$expected_mode" \
      --enable-cluster-autoscaler \
      --min-count "$expected_min" \
      --max-count "$expected_max" \
      $( [[ "$name" == "sgxpool" ]] && echo "--node-taints sgx=true:NoSchedule --labels sgx=true" ) \
      $( [[ "$name" == "directpool" ]] && echo "--node-taints direct=true:NoSchedule --labels direct=true" )
    return
  fi

  if [[ "$current_max" != "$expected_max" || "$current_min" != "$expected_min" || "$current_mode" != "$expected_mode" ]]; then
    az aks nodepool update \
      --update-cluster-autoscaler \
      --resource-group "$RG_NAME" \
      --cluster-name "$CLUSTER_NAME" \
      --name "$name" \
      --max-count "$expected_max" \
      --min-count "$expected_min"
  fi
}

az group create --name "$RG_NAME" --location "$LOCATION"

if ! az aks show --name "$CLUSTER_NAME" --resource-group "$RG_NAME" > /dev/null 2>&1; then
  POOLS_JSON="[]"
else
  POOLS_JSON=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" -o json)
  az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing
fi

validate_or_update_pool "masterpool" "$MASTER_VM_SIZE" 2 "System" 1

if [ "$SGX_NODES" -gt 0 ]; then
  validate_or_update_pool "sgxpool" "$SGX_VM_SIZE" "$SGX_NODES" "User" 0
else
  az aks nodepool delete --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" --name sgxpool --yes || true
fi

if [ "$REGULAR_NODES" -gt 0 ]; then
  validate_or_update_pool "directpool" "$REGULAR_VM_SIZE" "$REGULAR_NODES" "User" 0
else
  az aks nodepool delete --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" --name directpool --yes || true
fi

kubectl wait --for=condition=Ready nodes --all --timeout=720s

# === ACR Attachment ===
CLUSTER_MI=$(az aks show --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --query identity.principalId -o tsv)
ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)

if ! az role assignment list --assignee "$CLUSTER_MI" --scope "$ACR_ID" --query "[?roleDefinitionName=='AcrPull']" -o tsv | grep -q .; then
  az role assignment create --assignee "$CLUSTER_MI" --role AcrPull --scope "$ACR_ID"
  az aks update --name "$CLUSTER_NAME" --resource-group "$RG_NAME" --attach-acr "$ACR_NAME"
fi

# === Static IP Setup ===
NODE_RG=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RG_NAME" --query nodeResourceGroup -o tsv)
EXISTING_IPS=$(az network public-ip list --resource-group "$RG_NAME" -o tsv --query "[].name")
MATCHED=false

for IP_NAME in $EXISTING_IPS; do
  if [ "$IP_NAME" == "$PUBLIC_IP_NAME" ]; then
    MATCHED=true
  elif [[ "$IP_NAME" != *vm* ]]; then
    az network public-ip delete --resource-group "$RG_NAME" --name "$IP_NAME" || true
  fi

  if [ "$MATCHED" = false ]; then
    az network public-ip create --resource-group "$NODE_RG" --name "$PUBLIC_IP_NAME" --sku Standard --allocation-method static
    az network public-ip update --name "$PUBLIC_IP_NAME" --resource-group "$NODE_RG" --dns-name weave-webui
  fi

done

echo "✅ Nodepool and cluster setup complete."

