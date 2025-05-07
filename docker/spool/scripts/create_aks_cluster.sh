#!/bin/bash

set -euo pipefail

# === Configuration ===
RG_NAME="weave-rg"
CLUSTER_NAME="spark-cluster"
ACR_NAME="graminedirect"
LOCATION="eastus"
NAMESPACE="spark"

# Parse arguments: cluster size, CPU cores per node, memory (GB) per node
CLUSTER_SIZE=${1:-3}
CORES_PER_NODE=${2:-2}
MEMORY_PER_NODE=${3:-4}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

#az aks update \
#  --name $CLUSTER_NAME \
#  --resource-group $RG_NAME \
#  --attach-acr $ACR_NAME

# === Cleanup misconfigured clusters ===
echo "🧹 Checking for existing clusters with mismatched configuration..."
EXISTING_CLUSTERS=$(az aks list -o tsv --query "[].name")
for EXISTING in $EXISTING_CLUSTERS; do
  CONFIG=$(az aks show --name "$EXISTING" --resource-group "$RG_NAME" --query "agentPoolProfiles[0]" -o json || echo "")
  if [ -z "$CONFIG" ]; then
    continue
  fi
  COUNT=$(echo "$CONFIG" | jq .count)
  SIZE=$(echo "$CONFIG" | jq -r .vmSize)
  if [ "$COUNT" != "$CLUSTER_SIZE" ] || [[ "$SIZE" != *D${CORES_PER_NODE}s_v3* ]]; then
    echo "🗑️ Deleting cluster $EXISTING due to mismatch (count=$COUNT, size=$SIZE)"
    az aks delete --name "$EXISTING" --resource-group "$RG_NAME" --yes --no-wait
    exit 0
  fi
  if [ "$EXISTING" != "$CLUSTER_NAME" ]; then
    echo "🗑️ Deleting unexpected cluster $EXISTING"
    az aks delete --name "$EXISTING" --resource-group "$RG_NAME" --yes --no-wait
    exit 0
  fi
  echo "✅ Cluster $EXISTING already exists with matching config. Continuing to pod setup."
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

# === Create AKS Cluster (if not already created) ===
echo "🚀 Creating AKS cluster with $CLUSTER_SIZE nodes, $CORES_PER_NODE cores, $MEMORY_PER_NODE GB RAM per node..."
az aks create \
  --resource-group "$RG_NAME" \
  --name "$CLUSTER_NAME" \
  --node-count "$CLUSTER_SIZE" \
  --node-vm-size "Standard_D${CORES_PER_NODE}s_v3" \
  --generate-ssh-keys \
  --enable-managed-identity || true

az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing

# === Wait for Nodes ===
echo "⏳ Waiting for all AKS nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# === Clean Existing Namespace and Pods ===
echo "🧼 Cleaning existing namespace and pods if any..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found
kubectl create namespace "$NAMESPACE"

# === Launch Static Spark Pods and Headless Services ===
echo "🚀 Launching static Spark pods and headless services..."
for i in $(seq 0 $(($CLUSTER_SIZE - 1))); do
  ROLE="worker$((i - 1))"
  POD_NAME="spark-worker-$i"
  SERVICE_NAME=$POD_NAME
  if [ $i -eq 0 ]; then
    ROLE="master"
    POD_NAME="spark-master"
    SERVICE_NAME="spark-master"
  fi

  echo "📦 Creating pod $POD_NAME targeting spark-role=$ROLE"

  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  labels:
    app: $POD_NAME
spec:
  hostname: $POD_NAME
  containers:
  - name: spark-node
    image: "$ACR_NAME.azurecr.io/spark-spool-direct:latest"
    command: ["tail", "-f", "/dev/null"]
EOF

  echo "🔧 Creating headless service for $SERVICE_NAME"

  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
spec:
  clusterIP: None
  selector:
    app: $POD_NAME
  ports:
  - port: 7077
EOF

done

# === Wait for Pods to be Ready ===
echo "⏳ Waiting for all Spark pods to be Ready..."
for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
  echo "⌛ Waiting for pod $pod..."
  kubectl wait --for=condition=Ready pod/$pod -n "$NAMESPACE" --timeout=180s
done

# === Submit DNS Test Job ===
echo "🚀 Submitting DNS resolution test job..."
kubectl create configmap dns-test --from-file=dns-test.jar="$DNS_JAR_PATH" --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Generate host list for DNS test dynamically
DNS_HOSTS=(spark-master)
for i in $(seq 1 $(($CLUSTER_SIZE - 1))); do
  DNS_HOSTS+=("spark-worker-$i")
done

# Pass host list as an array of quoted strings
DNS_ARGS=$(printf '"%s", ' "${DNS_HOSTS[@]}")
DNS_ARGS=${DNS_ARGS%, }  # remove trailing comma

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
if ! kubectl wait --for=condition=Complete job/spark-dns-check -n "$NAMESPACE" --timeout=120s; then
  echo "⚠️ DNS resolution test job did not complete in time."
fi

echo "📄 DNS resolution test result logs:"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" --selector=job-name=spark-dns-check -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD_NAME" -n "$NAMESPACE" || echo "⚠️ Could not fetch DNS test logs."

echo "✅ Cluster setup complete."
