#!/bin/bash

set -euo pipefail

# === Configuration ===
RG_NAME="weave-rg"
CLUSTER_NAME="spark-cluster"
ACR_NAME="graminedirect"
LOCATION="eastus"
NAMESPACE="spark"

# Parse arguments: total cluster size, CPU cores per node, memory (GB), SGX worker count
CLUSTER_SIZE=${1:-3}
CORES_PER_NODE=${2:-2}
MEMORY_PER_NODE=${3:-4}
SGX_WORKERS=${4:-2}

# Derived configuration
NON_MASTER_NODES=$((CLUSTER_SIZE - 1))
SGX_NODES=$(( SGX_WORKERS < NON_MASTER_NODES ? SGX_WORKERS : NON_MASTER_NODES ))
REGULAR_NODES=$(( NON_MASTER_NODES > SGX_WORKERS ? NON_MASTER_NODES - SGX_WORKERS : 0 ))

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

# === Cleanup misconfigured clusters ===
echo "🧹 Checking for existing clusters with mismatched configuration..."
EXISTING_CLUSTERS=$(az aks list -o tsv --query "[].name")
for EXISTING in $EXISTING_CLUSTERS; do
  CONFIG=$(az aks show --name "$EXISTING" --resource-group "$RG_NAME" --query "agentPoolProfiles[0]" -o json || echo "")
  if [ -z "$CONFIG" ]; then continue; fi
  COUNT=$(echo "$CONFIG" | jq .count)
  SIZE=$(echo "$CONFIG" | jq -r .vmSize)
  if [ "$EXISTING" != "$CLUSTER_NAME" ]; then
    echo "🗑️ Deleting unexpected cluster $EXISTING"
    az aks delete --name "$EXISTING" --resource-group "$RG_NAME" --yes --no-wait
    exit 0
  fi
  echo "✅ Cluster $EXISTING already exists. Continuing to pod setup."
  break
done

# === Compile Java DNS Test ===
echo "🔨 Compiling DNS test via build script..."
cd ./jobs/java/dns
./build.sh
DNS_JAR_PATH="jobs/java/dns/build/dns-test.jar"
cd "$REPO_ROOT"

# === Create Resource Group ===
echo "☁️ Creating resource group [$RG_NAME] in [$LOCATION]..."
az group create --name "$RG_NAME" --location "$LOCATION"

# === Create base AKS cluster with 1 master node ===
echo "🚀 Creating AKS cluster with 1 master node..."
az aks create \
  --resource-group "$RG_NAME" \
  --name "$CLUSTER_NAME" \
  --node-count 1 \
  --node-vm-size "Standard_D${CORES_PER_NODE}s_v3" \
  --generate-ssh-keys \
  --enable-managed-identity \
  --nodepool-name masterpool \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 1 || true

az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing

# === Add SGX Node Pool ===
if [ "$SGX_NODES" -gt 0 ]; then
  echo "➕ Adding SGX node pool with $SGX_NODES nodes..."
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
    --node-taints sgx=true:NoSchedule
fi

# === Add regular worker node pool ===
if [ "$REGULAR_NODES" -gt 0 ]; then
  echo "➕ Adding regular node pool with $REGULAR_NODES nodes..."
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
    --mode User
fi

# === Wait for Nodes ===
echo "⏳ Waiting for all AKS nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# === Clean Existing Namespace and Pods ===
echo "🧼 Cleaning existing namespace and pods if any..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found
kubectl create namespace "$NAMESPACE"

# === Launch Static Spark Pods and Headless Services ===
echo "🚀 Launching static Spark pods and headless services..."

# Master
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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
EOF

cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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
for i in $(seq 1 "$SGX_NODES"); do
  POD_NAME="sgx-worker-$i"
  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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
EOF

  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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

# Direct Workers
for i in $(seq 1 "$REGULAR_NODES"); do
  POD_NAME="direct-worker-$i"
  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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
EOF

  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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

# === Wait for Pods to be Ready ===
echo "⏳ Waiting for all Spark pods to be Ready..."
for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
  echo "⌛ Waiting for pod $pod..."
  kubectl wait --for=condition=Ready pod/$pod -n "$NAMESPACE" --timeout=180s
  sleep 2
done

# === Submit DNS Test Job ===
echo "🚀 Submitting DNS resolution test job..."
kubectl create configmap dns-test --from-file=dns-test.jar="$DNS_JAR_PATH" --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

DNS_HOSTS=(spark-master)
for i in $(seq 1 "$SGX_NODES"); do DNS_HOSTS+=("sgx-worker-$i"); done
for i in $(seq 1 "$REGULAR_NODES"); do DNS_HOSTS+=("direct-worker-$i"); done
DNS_ARGS=$(printf '"%s", ' "${DNS_HOSTS[@]}")
DNS_ARGS=${DNS_ARGS%, }

cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
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
kubectl wait --for=condition=Complete job/spark-dns-check -n "$NAMESPACE" --timeout=120s || echo "⚠️ DNS resolution test job did not complete in time."

echo "📄 DNS resolution test result logs:"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" --selector=job-name=spark-dns-check -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD_NAME" -n "$NAMESPACE" || echo "⚠️ Could not fetch DNS test logs."

echo "✅ Cluster setup complete."
