#!/bin/bash

set -euo pipefail

# === Configuration ===
RG_NAME="weave-rg"
CLUSTER_NAME="spark-cluster"
ACR_NAME="graminedirect"
LOCATION="eastus"
NAMESPACE="spark"
PUBLIC_IP_NAME="spark-master-ip"
RESERVED_GB=5  

# Parse arguments
CLUSTER_SIZE=${1:-11}
CORES_PER_NODE=${2:-4}
SGX_WORKERS=${3:-0}
MASTER_CORES=${4:-4}
WORKERS_PER_NODE=${5:-1}

# Derived values
NON_MASTER_NODES=$((CLUSTER_SIZE - 1))
SGX_NODES=$(( SGX_WORKERS < NON_MASTER_NODES ? SGX_WORKERS : NON_MASTER_NODES ))
REGULAR_NODES=$(( NON_MASTER_NODES > SGX_WORKERS ? NON_MASTER_NODES - SGX_WORKERS : 0 ))

echo "🔍 Cluster configuration:"
echo "  Total nodes        = $CLUSTER_SIZE"
echo "  Cores per node     = $CORES_PER_NODE"
echo "  SGX workers        = $SGX_NODES"
echo "  Regular workers    = $REGULAR_NODES"


# === VM Type and Memory Setup ===
LOCATION="eastus"
SKU_CACHE=".vm_skus_eastus.json"

# Fetch and cache VM SKUs
if [ ! -f "$SKU_CACHE" ]; then
  echo "📦 Caching Azure VM SKUs to $SKU_CACHE..."
  az vm list-skus \
    --location "$LOCATION" \
    --resource-type "virtualMachines" \
    -o json > "$SKU_CACHE"
else
  echo "📂 Using cached VM SKU data from $SKU_CACHE"
fi

# Helper function to get CPU or Memory from cache
get_cached_capability() {
  local vm_size=$1
  local cap_name=$2
  jq -r --arg vm "$vm_size" --arg cap "$cap_name" '
    .[] | select(.name == $vm) |
    .capabilities[] | select(.name == $cap) |
    .value' "$SKU_CACHE" | head -n 1
}

# Set VM types
SGX_VM_SIZE="Standard_DC${CORES_PER_NODE}s_v3"
REGULAR_VM_SIZE="Standard_D${CORES_PER_NODE}s_v3"
MASTER_VM_SIZE="Standard_D${MASTER_CORES}s_v3"

# Fetch specs for each pool
SGX_MEMORY_GB=$(get_cached_capability "$SGX_VM_SIZE" "MemoryGB")
SGX_CPU=$(get_cached_capability "$SGX_VM_SIZE" "vCPUs")

REGULAR_MEMORY_GB=$(get_cached_capability "$REGULAR_VM_SIZE" "MemoryGB")
REGULAR_CPU=$(get_cached_capability "$REGULAR_VM_SIZE" "vCPUs")

MASTER_MEMORY_GB=$(get_cached_capability "$MASTER_VM_SIZE" "MemoryGB")
MASTER_CPU=$(get_cached_capability "$MASTER_VM_SIZE" "vCPUs")

# Compute usable resource limits (buffered CPU, full memory)
SGX_USABLE_CPU=$(awk "BEGIN { print $SGX_CPU - 0.5 }")
SGX_USABLE_MEMORY="$(awk "BEGIN { print $SGX_MEMORY_GB - $RESERVED_GB }")Gi"

REGULAR_USABLE_CPU=$(awk "BEGIN { print $REGULAR_CPU - 0.5 }")
REGULAR_USABLE_MEMORY="$(awk "BEGIN { print $REGULAR_MEMORY_GB - $RESERVED_GB }")Gi"

MASTER_USABLE_CPU=$(awk "BEGIN { print $MASTER_CPU - 0.5 }")
MASTER_USABLE_MEMORY="$(awk "BEGIN { print $MASTER_MEMORY_GB - $RESERVED_GB }")Gi"

# Export for pod templates
export SGX_VM_SIZE REGULAR_VM_SIZE MASTER_VM_SIZE
export SGX_USABLE_CPU REGULAR_USABLE_CPU MASTER_USABLE_CPU
export SGX_USABLE_MEMORY REGULAR_USABLE_MEMORY MASTER_USABLE_MEMORY

# Log it
echo "🧠 SGX node:     $SGX_VM_SIZE → CPU: $SGX_CPU, Memory: ${SGX_MEMORY_GB}Gi → Usable: ${SGX_USABLE_CPU}, ${SGX_USABLE_MEMORY}"
echo "🧠 Direct node:  $REGULAR_VM_SIZE → CPU: $REGULAR_CPU, Memory: ${REGULAR_MEMORY_GB}Gi → Usable: ${REGULAR_USABLE_CPU}, ${REGULAR_USABLE_MEMORY}"
echo "🧠 Master node:  $MASTER_VM_SIZE → CPU: $MASTER_CPU, Memory: ${MASTER_MEMORY_GB}Gi → Usable: ${MASTER_USABLE_CPU}, ${MASTER_USABLE_MEMORY}"

# === Compile Java DNS Test ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

# === Compile Java DNS Test ===
echo "🔨 Compiling DNS test via build script..."
cd ./jobs/java/dns
./build.sh
DNS_JAR_PATH="jobs/java/dns/build/dns-test.jar"
cd "$REPO_ROOT"

# === Logs ===
exec 3>&1 4>&2

# === Create RG ===
echo "☁️ Creating resource group..."
az group create --name "$RG_NAME" --location "$LOCATION" > .az_group.log 2>&1

validate_or_update_pool() {
  local name=$1
  local expected_vm_size=$2
  local expected_max=$3
  local expected_mode=$4
  local expected_min=$5

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 Validating node pool: [$name]"
  echo "  ↳ Expected VM Size : $expected_vm_size"
  echo "  ↳ Mode              : $expected_mode"
  echo "  ↳ Min Nodes         : $expected_min"
  echo "  ↳ Max Nodes         : $expected_max"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$POOLS_JSON" == "[]" && "$expected_mode" == "System" ]]; then
    echo "🚀 Cluster not yet initialized. Creating system pool [$name] via az aks create..."
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
      --max-count "$expected_max" \
      > ".az_create_${name}.log" 2>&1

    echo "✅ Cluster and [$name] pool initialized successfully."
      # === Get credentials ===
    echo "🔑 Getting AKS credentials after cluster creation..."
    az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing > .az_getcreds.log 2>&1
    echo "🔄 Refreshing POOLS_JSON after cluster creation..."
    POOLS_JSON=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" -o json)
    return
  fi

  if [[ "$POOLS_JSON" == "[]" && "$expected_mode" == "User" ]]; then
    echo "❌ Error: Trying to create user-mode pool [$name] before cluster initialization."
    echo "   ➤ A system node pool must be created first (e.g., masterpool)."
    exit 1
  fi

  POOL=$(echo "$POOLS_JSON" | jq -r --arg name "$name" '.[] | select(.name == $name)')

  if [[ -z "$POOL" ]]; then
    echo "➕ Node pool [$name] not found. Creating it now..."
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
      $( [[ "$name" == "sgxpool" ]] && echo "--node-taints sgx=true:NoSchedule --labels sgx=true node-role=sgx-worker" ) \
      $( [[ "$name" == "directpool" ]] && echo "--node-taints direct=true:NoSchedule --labels direct=true node-role=direct-worker" ) \
      > ".az_add_${name}.log" 2>&1

    echo "✅ Node pool [$name] created."
    return
  fi

  current_vm_size=$(echo "$POOL" | jq -r '.vmSize')
  current_max=$(echo "$POOL" | jq -r '.maxCount')
  current_min=$(echo "$POOL" | jq -r '.minCount')
  current_mode=$(echo "$POOL" | jq -r '.mode')

  echo "🔍 Current pool status:"
  echo "  ↳ VM Size       : $current_vm_size"
  echo "  ↳ Min Count     : $current_min"
  echo "  ↳ Max Count     : $current_max"
  echo "  ↳ Mode          : $current_mode"

  if [[ "$current_vm_size" != "$expected_vm_size" ]]; then
    echo "🧨 Mismatch: VM size differs. Expected [$expected_vm_size], found [$current_vm_size]"
    echo "🗑️  Deleting pool [$name]..."
    az aks nodepool delete \
      --cluster-name "$CLUSTER_NAME" \
      --resource-group "$RG_NAME" \
      --name "$name" \
      --yes > ".az_delete_${name}.log" 2>&1

    echo "➕ Recreating node pool [$name]..."
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
      $( [[ "$name" == "sgxpool" ]] && echo "--node-taints sgx=true:NoSchedule --labels sgx=true node-role=sgx-worker" ) \
      $( [[ "$name" == "directpool" ]] && echo "--node-taints direct=true:NoSchedule --labels direct=true node-role=direct-worker" ) \
      > ".az_add_${name}_recreate.log" 2>&1

    echo "✅ Node pool [$name] recreated."
    return
  fi

  if [[ "$current_max" != "$expected_max" || "$current_min" != "$expected_min" || "$current_mode" != "$expected_mode" ]]; then
    echo "🔁 Scaling mismatch detected:"
    [[ "$current_max" != "$expected_max" ]] && echo "  ✦ Max Count: expected $expected_max, found $current_max"
    [[ "$current_min" != "$expected_min" ]] && echo "  ✦ Min Count: expected $expected_min, found $current_min"
    [[ "$current_mode" != "$expected_mode" ]] && echo "  ✦ Mode     : expected $expected_mode, found $current_mode"

    echo "🛠️  Updating node pool [$name]..."
    az aks nodepool update \
      --update-cluster-autoscaler \
      --resource-group "$RG_NAME" \
      --cluster-name "$CLUSTER_NAME" \
      --name "$name" \
      --max-count "$expected_max" \
      --min-count "$expected_min" \
      > ".az_update_${name}.log" 2>&1

    echo "✅ Node pool [$name] scaling updated."
  else
    echo "✅ Node pool [$name] is already configured correctly."
  fi

  echo
}


# === Check for existing cluster ===
echo "🔍 Checking for existing AKS cluster [$CLUSTER_NAME] in resource group [$RG_NAME]..."
if ! az aks show --name "$CLUSTER_NAME" --resource-group "$RG_NAME" > /dev/null 2>&1; then
  POOLS_JSON="[]"
else
  POOLS_JSON=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" -o json)
  # === Get credentials ===
  echo "🔑 Getting AKS credentials..."
  az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing > .az_getcreds.log 2>&1
fi

validate_or_update_pool "masterpool" "Standard_D${MASTER_CORES}s_v3" 2 "System" 1

if [ "$SGX_NODES" -gt 0 ]; then
  validate_or_update_pool "sgxpool" "Standard_DC${CORES_PER_NODE}s_v3" "$SGX_NODES" "User" 0
else
  echo "🧹 Removing unused SGX pool..."
  az aks nodepool delete --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" --name sgxpool --yes > .az_delete_sgx.log 2>&1 || true
fi

if [ "$REGULAR_NODES" -gt 0 ]; then
  validate_or_update_pool "directpool" "Standard_D${CORES_PER_NODE}s_v3" "$REGULAR_NODES" "User" 0
else
  echo "🧹 Removing unused direct pool..."
  az aks nodepool delete --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" --name directpool --yes > .az_delete_direct.log 2>&1 || true
fi

# === Wait for nodes ===
echo "⏳ Waiting for AKS nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=720s

echo "✅ AKS cluster setup complete."

# === Create or reuse public IP ===
echo "🌐 Checking for existing public IP [$PUBLIC_IP_NAME]..."

EXISTING_IPS=$(az network public-ip list --resource-group "$RG_NAME" -o tsv --query "[].name")
MATCHED=false

for IP_NAME in $EXISTING_IPS; do
  if [ "$IP_NAME" == "$PUBLIC_IP_NAME" ]; then
    echo "✅ Public IP [$PUBLIC_IP_NAME] already exists. Reusing."
    MATCHED=true
  else
    if [[ "$IP_NAME" != *vm* ]]; then
        echo "🧹 Deleting unused public IP [$IP_NAME]..."
        az network public-ip delete --resource-group "$RG_NAME" --name "$IP_NAME" > .az_delete_ip_$IP_NAME.log 2>&1
    fi
  fi
done
# Get node resource group
NODE_RG=$(az aks show --name spark-cluster --resource-group weave-rg --query nodeResourceGroup -o tsv)

if [ "$MATCHED" = false ]; then
  echo "➕ Creating public IP [$PUBLIC_IP_NAME]..."
  az network public-ip create \
    --resource-group "$NODE_RG" \
    --name "$PUBLIC_IP_NAME" \
    --sku Standard \
    --allocation-method static > .az_publicip.log 2>&1
  echo "➕ Creating dns name for [$PUBLIC_IP_NAME]..."
  az network public-ip update \
    --name "$PUBLIC_IP_NAME" \
    --resource-group $NODE_RG \
    --dns-name weave-webui > .az_publicdns.log 2>&1
fi



# === Attach ACR (if not already attached) ===
echo "🔗 Checking ACR attachment..."

CLUSTER_MI=$(az aks show --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --query identity.principalId -o tsv)
ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)

az role assignment list \
  --assignee "$CLUSTER_MI" \
  --scope "$ACR_ID" \
  --query "[?roleDefinitionName=='AcrPull']" -o tsv > .az_acr_check.log 2>&1

ACR_BOUND=$(cat .az_acr_check.log)

if [ -n "$ACR_BOUND" ]; then
  echo "✅ ACR [$ACR_NAME] is already attached to AKS."
else
  echo "➕ Attaching ACR [$ACR_NAME] to AKS..."
  az role assignment create \
    --assignee "$CLUSTER_MI" \
    --role AcrPull \
    --scope "$ACR_ID" > .az_acr_role_def.log 2>&1

  az aks update \
    --name "$CLUSTER_NAME" \
    --resource-group "$RG_NAME" \
    --attach-acr "$ACR_NAME" > .az_acr_attach.log 2>&1
fi


# === Clean Existing Namespace and Pods ===
echo "🧼 Cleaning existing namespace and pods if any..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found > .log_kubectl_ns_delete 2>&1
kubectl create namespace "$NAMESPACE" > .log_kubectl_ns_create 2>&1

# === Create Spark PVCs ===
echo "📦 Creating PersistentVolumeClaims for [$CLUSTER_NAME / $NAMESPACE]..."
$REPO_ROOT/scripts/create-spark-pvcs-bound.sh "$CLUSTER_NAME" "$NAMESPACE" "$SGX_NODES" "$REGULAR_NODES"

# === Launch Static Spark Pods and Headless Services ===
echo "🚀 Launching static Spark pods and headless services..."


launch_static_pod() {
  local POD_NAME=$1
  local ROLE=$2             # master | sgx | direct
  local NODEPOOL=$3         # masterpool | sgxpool | directpool
  local TAINT_KEY=$4        # sgx | direct | ""
  local WORKER_GROUP=$5
  local WORKER_INDEX=$6

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔧 Creating pod [$POD_NAME]"
  echo "  ↳ Role:        $ROLE"
  echo "  ↳ Node pool:   $NODEPOOL"
  [[ -n "$TAINT_KEY" ]] && echo "  ↳ Taint:       $TAINT_KEY=true:NoSchedule"
  echo "  ↳ NodeSelector: agentpool=$NODEPOOL"
  echo "  ↳ AntiAffinity: role=$ROLE"
  echo "  ↳ Worker group: $WORKER_GROUP"
  echo "  ↳ Worker index: $WORKER_INDEX"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  POD_YAML=".log_pod_${POD_NAME}.yaml"
  APPLY_LOG=".log_apply_${POD_NAME}.log"

  {
    echo "apiVersion: v1"
    echo "kind: Pod"
    echo "metadata:"
    echo "  name: ${POD_NAME}"
    echo "  labels:"
    echo "    app: spark-worker"
    echo "    role: ${ROLE}"
    echo "    worker-group: \"${WORKER_GROUP}\""
    echo "    worker-index: \"${WORKER_INDEX}\""
    if [[ "$ROLE" == "sgx" ]]; then
      echo "    cluster: \"0\""
    elif [[ "$ROLE" == "direct" ]]; then
      echo "    cluster: \"1\""
    fi
    echo "spec:"
    if [[ "$NODEPOOL" != "masterpool" ]]; then
      echo "  nodeSelector:"
      echo "    agentpool: $NODEPOOL"
    fi
    if [[ -n "$TAINT_KEY" ]]; then
      echo "  tolerations:"
      echo "    - key: \"$TAINT_KEY\""
      echo "      operator: \"Equal\""
      echo "      value: \"true\""
      echo "      effect: \"NoSchedule\""
    fi
    echo "  affinity:"
    echo "    podAntiAffinity:"
    echo "      requiredDuringSchedulingIgnoredDuringExecution:"
    echo "        - labelSelector:"
    echo "            matchExpressions:"
    echo "              - key: role"
    echo "                operator: In"
    echo "                values: [\"$ROLE\"]"
    echo "              - key: worker-group"
    echo "                operator: In"
    echo "                values: [\"$WORKER_GROUP\"]"
    echo "          topologyKey: \"kubernetes.io/hostname\""
    echo "  containers:"
    echo "    - name: spark-node"
    echo "      image: \"$ACR_NAME.azurecr.io/spark-spool-direct:latest\""
    echo "      command: [\"/bin/bash\", \"-c\"]"
    echo "      args:"
    echo "        - /opt/private-repos/weave-artifacts-auto/docker/spool/scripts/check-sgx.sh | tee /tmp/check-sgx.log;"
    echo "          env | tee /tmp/env.log;"
    echo "          tail -f /dev/null"
    echo "      env:"
    if [[ "$ROLE" == "sgx" ]]; then
      echo "        - name: SGX"
      echo "          value: \"1\""
      echo "        - name: EDMM"
      echo "          value: \"0\""
      echo "      securityContext:"
      echo "        privileged: true"
    else
      echo "        - name: SGX"
      echo "          value: \"0\""
      echo "        - name: EDMM"
      echo "          value: \"1\""
    fi
    echo "      volumeMounts:"
    echo "        - name: log-volume"
    echo "          mountPath: /opt/spark/logs"
    echo "        - name: data-volume"
    echo "          mountPath: /opt/spark/enclave/data"
    echo "        - name: scratch-local"
    echo "          mountPath: /scratch"
    if [[ "$ROLE" == "sgx" ]]; then
      echo "        - name: sgx-enclave"
      echo "          mountPath: /dev/sgx/enclave"
      echo "        - name: sgx-provision"
      echo "          mountPath: /dev/sgx/provision"
    fi

    echo "  volumes:"
    echo "    - name: log-volume"
    echo "      persistentVolumeClaim:"
    echo "        claimName: logs-${CLUSTER_NAME}-${POD_NAME}"
    echo "    - name: data-volume"
    echo "      persistentVolumeClaim:"
    echo "        claimName: data-${CLUSTER_NAME}-${POD_NAME}"
    echo "    - name: scratch-local"
    echo "      emptyDir: {}"
    if [[ "$ROLE" == "sgx" ]]; then
      echo "    - name: sgx-enclave"
      echo "      hostPath:"
      echo "        path: /dev/sgx/enclave"
      echo "        type: CharDevice"
      echo "    - name: sgx-provision"
      echo "      hostPath:"
      echo "        path: /dev/sgx/provision"
      echo "        type: CharDevice"
    fi
  } | tee "$POD_YAML" | kubectl apply -n "$NAMESPACE" -f - > "$APPLY_LOG" 2>&1

  echo "✅ Pod [$POD_NAME] submitted"

  echo "📡 Creating headless service [$POD_NAME] with ports 7077 (comm) and 8081 (UI)..."
cat <<EOF | tee ".log_svc_${POD_NAME}.yaml" | kubectl apply -n "$NAMESPACE" -f - > ".log_svc_apply_${POD_NAME}.log" 2>&1
apiVersion: v1
kind: Service
metadata:
  name: $POD_NAME
spec:
  clusterIP: None
  selector:
    app: spark-worker
    role: "$ROLE"
    worker-group: "${WORKER_GROUP}"
    worker-index: "${WORKER_INDEX}"
  ports:
    - name: spark-comm
      port: 7077
      targetPort: 7077
    - name: spark-ui
      port: 8081
      targetPort: 8081
EOF
  echo "🔧 Service [$POD_NAME] created"

  echo "⏳ Waiting for [$POD_NAME] to be ready..."
  kubectl wait --for=condition=Ready pod/$POD_NAME -n "$NAMESPACE" --timeout=420s > ".log_wait_${POD_NAME}.log" 2>&1

  echo "📥 Fetching SGX check and environment info from [$POD_NAME]..."
  kubectl cp "$NAMESPACE/$POD_NAME:/tmp/check-sgx.log" "./log_check_sgx_${POD_NAME}.log" > /dev/null 2>&1 || echo "⚠️ Could not fetch check-sgx.log"
  kubectl cp "$NAMESPACE/$POD_NAME:/tmp/env.log" "./log_env_${POD_NAME}.log" > /dev/null 2>&1 || echo "⚠️ Could not fetch env.log"

  echo "🔍 [check-sgx.log] for [$POD_NAME]:"
  cat "./log_check_sgx_${POD_NAME}.log" || echo "❌ Not available"

  echo "🔍 [env.log] for [$POD_NAME]:"
  cat "./log_env_${POD_NAME}.log" || echo "❌ Not available"
}



# Master Pods
for i in $(seq 1 1); do
  POD_NAME="spark-master-${i}"
  launch_static_pod "$POD_NAME" "master" "masterpool" "" "i" "1"
done

# SGX Workers
if [ "$SGX_NODES" -gt 0 ]; then
  echo "🚀 Launching SGX worker pods..."
  for i in $(seq 1 "$SGX_NODES"); do
    for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
      POD_NAME="sgx-worker-${i}-${j}"
      launch_static_pod "$POD_NAME" "sgx" "sgxpool" "sgx" "$j" "$i"
    done
  done
else
  echo "⚠️ No SGX worker nodes requested. Skipping SGX pod creation."
fi

# Direct Workers
if [ "$REGULAR_NODES" -gt 0 ]; then
  echo "🚀 Launching direct worker pods..."
  for i in $(seq 1 "$REGULAR_NODES"); do
    for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
      POD_NAME="direct-worker-${i}-${j}"
      launch_static_pod "$POD_NAME" "direct" "directpool" "direct" "$j" "$i"
    done
  done
else
  echo "⚠️ No direct worker nodes requested. Skipping direct pod creation."
fi


# === Wait for Pods to be Ready ===
echo "⏳ Waiting for all Spark pods to be Ready..."
for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
  echo "⌛ Waiting for pod $pod..."
  kubectl wait --for=condition=Ready pod/$pod -n "$NAMESPACE" --timeout=420s > ".log_wait_${pod}.log" 2>&1
  sleep 2
done

# === Submit DNS Test Job ===
echo "🚀 Submitting DNS resolution test job..."
kubectl create configmap dns-test --from-file=dns-test.jar="$DNS_JAR_PATH" --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > .log_configmap_dns.log 2>&1

# Construct host list
DNS_HOSTS=("spark-master-1" "spark-master-2")

for i in $(seq 1 "$SGX_NODES"); do
  for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
    DNS_HOSTS+=("sgx-worker-${i}-${j}")
  done
done

for i in $(seq 1 "$REGULAR_NODES"); do
  for j in $(seq 0 $((WORKERS_PER_NODE - 1))); do
    DNS_HOSTS+=("direct-worker-${i}-${j}")
  done
done

DNS_ARGS=$(printf '"%s", ' "${DNS_HOSTS[@]}")
DNS_ARGS=${DNS_ARGS%, }

cat <<EOF | tee ".log_dns_job.yaml" | kubectl apply -n "$NAMESPACE" -f - > ".log_apply_dns_job.log" 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: spark-dns-check
spec:
  template:
    spec:
      containers:
      - name: dns-checker
        image: openjdk:11
        command: ["java", "-cp", "/config/dns-test.jar", "DnsTest"]
        args: [${DNS_ARGS}]
        volumeMounts:
        - name: config-volume
          mountPath: /config
      volumes:
      - name: config-volume
        configMap:
          name: dns-test
      restartPolicy: Never
  backoffLimit: 0
EOF

# === Wait and Display DNS Test Result ===
echo "⏳ Waiting for Spark DNS resolution job to finish..."
kubectl wait --for=condition=Complete job/spark-dns-check -n "$NAMESPACE" --timeout=120s > .log_wait_dns_job.log 2>&1 || echo "⚠️ DNS resolution test job did not complete in time."

echo "📄 DNS resolution test result logs:"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" --selector=job-name=spark-dns-check -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD_NAME" -n "$NAMESPACE" || echo "⚠️ Could not fetch DNS test logs."

echo "✅ Cluster setup complete."

