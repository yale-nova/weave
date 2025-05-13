#!/bin/bash

set -euo pipefail

# === Configuration ===
RG_NAME="weave-rg"
CLUSTER_NAME="spark-cluster"
ACR_NAME="graminedirect"
LOCATION="eastus"
NAMESPACE="spark"
PUBLIC_IP_NAME="spark-master-ip"

# Parse arguments
CLUSTER_SIZE=${1:-3}
CORES_PER_NODE=${2:-4}
MEMORY_PER_NODE=${3:-4}
SGX_WORKERS=${4:-2}

# Derived values
NON_MASTER_NODES=$((CLUSTER_SIZE - 1))
SGX_NODES=$(( SGX_WORKERS < NON_MASTER_NODES ? SGX_WORKERS : NON_MASTER_NODES ))
REGULAR_NODES=$(( NON_MASTER_NODES > SGX_WORKERS ? NON_MASTER_NODES - SGX_WORKERS : 0 ))

echo "🔍 Cluster configuration:"
echo "  Total nodes        = $CLUSTER_SIZE"
echo "  Cores per node     = $CORES_PER_NODE"
echo "  SGX workers        = $SGX_NODES"
echo "  Regular workers    = $REGULAR_NODES"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

# === Logs ===
exec 3>&1 4>&2

# === Create RG ===
echo "☁️ Creating resource group..."
az group create --name "$RG_NAME" --location "$LOCATION" > .az_group.log 2>&1

# === Create or reuse public IP ===
echo "🌐 Checking for existing public IP [$PUBLIC_IP_NAME]..."

EXISTING_IPS=$(az network public-ip list --resource-group "$RG_NAME" -o tsv --query "[].name")
MATCHED=false

for IP_NAME in $EXISTING_IPS; do
  if [ "$IP_NAME" == "$PUBLIC_IP_NAME" ]; then
    echo "✅ Public IP [$PUBLIC_IP_NAME] already exists. Reusing."
    MATCHED=true
  else
    echo "🧹 Deleting unused public IP [$IP_NAME]..."
    az network public-ip delete --resource-group "$RG_NAME" --name "$IP_NAME" > .az_delete_ip_$IP_NAME.log 2>&1
  fi
done

if [ "$MATCHED" = false ]; then
  echo "➕ Creating public IP [$PUBLIC_IP_NAME]..."
  az network public-ip create \
    --resource-group "$RG_NAME" \
    --name "$PUBLIC_IP_NAME" \
    --sku Standard \
    --allocation-method static > .az_publicip.log 2>&1
fi


# === Attach ACR ===
echo "🔗 Attaching ACR..."

az role assignment create \
  --assignee "$(az aks show --resource-group $RG_NAME --name $CLUSTER_NAME --query identity.principalId -o tsv)" \
  --role AcrPull \
  --scope "$(az acr show --name $ACR_NAME --query id -o tsv)" > .az_acr_role_def.log 2>&1

az aks update \
  --name "$CLUSTER_NAME" \
  --resource-group "$RG_NAME" \
  --attach-acr "$ACR_NAME" > .az_acr.log 2>&1

# === Get credentials ===
az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing > .az_getcreds.log 2>&1


# === Check existing cluster ===
echo "🔍 Checking existing cluster..."
if az aks show --name "$CLUSTER_NAME" --resource-group "$RG_NAME" > /dev/null 2>&1; then
  echo "✅ Cluster exists. Validating node pools..."

  POOLS=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RG_NAME" -o json)

  DELETE_CLUSTER=false

  for EXPECTED in masterpool sgxpool directpool; do
    if echo "$POOLS" | jq -e ".[] | select(.name==\"$EXPECTED\")" >/dev/null; then
      VM_SIZE=$(echo "$POOLS" | jq -r ".[] | select(.name==\"$EXPECTED\") | .vmSize")
      if [[ "$EXPECTED" == "masterpool" && "$VM_SIZE" != "Standard_D${CORES_PER_NODE}s_v3" ]]; then
        DELETE_CLUSTER=true
      elif [[ "$EXPECTED" == "sgxpool" && $SGX_NODES -gt 0 && "$VM_SIZE" != "Standard_DC${CORES_PER_NODE}s_v3" ]]; then
        DELETE_CLUSTER=true
      elif [[ "$EXPECTED" == "directpool" && $REGULAR_NODES -gt 0 && "$VM_SIZE" != "Standard_D${CORES_PER_NODE}s_v3" ]]; then
        DELETE_CLUSTER=true
      fi
    fi
  done

  if [ "$DELETE_CLUSTER" = true ]; then
    echo "🧨 Deleting mismatched cluster..."
    az aks delete --name "$CLUSTER_NAME" --resource-group "$RG_NAME" --yes --no-wait > .az_delete.log 2>&1
    sleep 30
  else
    echo "✅ All node pools match. Continuing."
  fi
fi

# === Create AKS cluster ===
if ! az aks show --name "$CLUSTER_NAME" --resource-group "$RG_NAME" > /dev/null 2>&1; then
  echo "🚀 Creating AKS cluster..."
  az aks create \
    --resource-group "$RG_NAME" \
    --name "$CLUSTER_NAME" \
    --node-count 1 \
    --node-vm-size "Standard_D${CORES_PER_NODE}s_v3" \
    --generate-ssh-keys \
    --enable-managed-identity \
    --nodepool-name masterpool \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 1 > .az_create.log 2>&1
    # === Add SGX pool ===
  if [ "$SGX_NODES" -gt 0 ]; then
    echo "➕ Adding SGX pool..."
    az aks nodepool add \
      --resource-group "$RG_NAME" \
      --cluster-name "$CLUSTER_NAME" \
      --name sgxpool \
      --node-count "$SGX_NODES" \
      --node-vm-size Standard_DC${CORES_PER_NODE}s_v3 \
      --labels sgx=true node-role=sgx-worker \
      --enable-cluster-autoscaler \
      --min-count 0 \
      --max-count "$SGX_NODES" \
      --mode User \
      --enable-node-public-ip \
      --node-taints sgx=true:NoSchedule > .az_sgxpool.log 2>&1
  fi

    # === Add direct pool ===
  if [ "$REGULAR_NODES" -gt 0 ]; then
    echo "➕ Adding direct pool..."
    az aks nodepool add \
      --resource-group "$RG_NAME" \
      --cluster-name "$CLUSTER_NAME" \
      --name directpool \
      --node-count "$REGULAR_NODES" \
      --node-vm-size Standard_D${CORES_PER_NODE}s_v3 \
      --labels node-role=direct-worker \
      --enable-cluster-autoscaler \
      --min-count 0 \
      --max-count "$REGULAR_NODES" \
      --mode User > .az_directpool.log 2>&1
  fi

fi  

# === Wait for nodes ===
echo "⏳ Waiting for AKS nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "✅ AKS cluster setup complete."

# === Clean Existing Namespace and Pods ===
echo "🧼 Cleaning existing namespace and pods if any..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
kubectl create namespace "$NAMESPACE" > /dev/null 2>&1

# === Launch Static Spark Pods and Headless Services ===
echo "🚀 Launching static Spark pods and headless services..."

export CORES_PER_NODE MEMORY_PER_NODE

# Master
cat <<EOF | envsubst | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: spark-master
  labels:
    app: spark-master
spec:
  containers:
  - name: spark-node
    image: "$ACR_NAME.azurecr.io/spark-spool-direct:latest"
    command: ["tail", "-f", "/dev/null"]
    resources:
      requests:
        cpu: "${CORES_PER_NODE}"
        memory: "${MEMORY_PER_NODE}Gi"
      limits:
        cpu: "${CORES_PER_NODE}"
        memory: "${MEMORY_PER_NODE}Gi"
EOF

cat <<EOF | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: spark-master
spec:
  clusterIP: None
  selector:
    app: spark-master
  ports:
  - port: 7077
EOF

# SGX Workers
if [ "$SGX_NODES" -gt 0 ]; then
  for i in $(seq 1 "$SGX_NODES"); do
    POD_NAME="sgx-worker-$i"
    export POD_NAME
    cat <<EOF | envsubst | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  labels:
    app: spark-worker
    sgx: "true"
spec:
  nodeSelector:
    agentpool: sgxpool
  tolerations:
    - key: "sgx"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
  containers:
  - name: spark-node
    image: "$ACR_NAME.azurecr.io/spark-spool-direct:latest"
    command: ["tail", "-f", "/dev/null"]
    resources:
      requests:
        cpu: "${CORES_PER_NODE}"
        memory: "${MEMORY_PER_NODE}Gi"
      limits:
        cpu: "${CORES_PER_NODE}"
        memory: "${MEMORY_PER_NODE}Gi"
EOF

    cat <<EOF | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: $POD_NAME
spec:
  clusterIP: None
  selector:
    app: spark-worker
    sgx: "true"
  ports:
  - port: 7077
EOF
  done
else 
  echo "⚠️ No SGX worker nodes requested. Skipping direct pod creation."
fi

# Direct Workers
if [ "$REGULAR_NODES" -gt 0 ]; then
  echo "🚀 Launching direct worker pods and headless services..."
  for i in $(seq 1 "$REGULAR_NODES"); do
    POD_NAME="direct-worker-$i"
    export POD_NAME
    cat <<EOF | envsubst | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  labels:
    app: spark-worker
    sgx: "false"
spec:
  nodeSelector:
    agentpool: directpool
  containers:
  - name: spark-node
    image: "$ACR_NAME.azurecr.io/spark-spool-direct:latest"
    command: ["tail", "-f", "/dev/null"]
    resources:
      requests:
        cpu: "${CORES_PER_NODE}"
        memory: "${MEMORY_PER_NODE}Gi"
      limits:
        cpu: "${CORES_PER_NODE}"
        memory: "${MEMORY_PER_NODE}Gi"
EOF

  cat <<EOF | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: $POD_NAME
spec:
  clusterIP: None
  selector:
    app: spark-worker
    sgx: "false"
  ports:
  - port: 7077
EOF
  done
else 
  echo "⚠️ No direct worker nodes requested. Skipping SGX pod creation."
fi

# === Wait for Pods to be Ready ===
echo "⏳ Waiting for all Spark pods to be Ready..."
for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
  echo "⌛ Waiting for pod $pod..."
  kubectl wait --for=condition=Ready pod/$pod -n "$NAMESPACE" --timeout=180s > /dev/null 2>&1
  sleep 2
done

# === Submit DNS Test Job ===
echo "🚀 Submitting DNS resolution test job..."
kubectl create configmap dns-test --from-file=dns-test.jar="$DNS_JAR_PATH" --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

DNS_HOSTS=(spark-master)
for i in $(seq 1 "$SGX_NODES"); do DNS_HOSTS+=("sgx-worker-$i"); done
for i in $(seq 1 "$REGULAR_NODES"); do DNS_HOSTS+=("direct-worker-$i"); done
DNS_ARGS=$(printf '"%s", ' "${DNS_HOSTS[@]}")
DNS_ARGS=${DNS_ARGS%, }

cat <<EOF | kubectl apply -n "$NAMESPACE" -f - > /dev/null 2>&1
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
kubectl wait --for=condition=Complete job/spark-dns-check -n "$NAMESPACE" --timeout=120s > /dev/null 2>&1 || echo "⚠️ DNS resolution test job did not complete in time."

echo "📄 DNS resolution test result logs:"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" --selector=job-name=spark-dns-check -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD_NAME" -n "$NAMESPACE" || echo "⚠️ Could not fetch DNS test logs."

echo "✅ Cluster setup complete."

