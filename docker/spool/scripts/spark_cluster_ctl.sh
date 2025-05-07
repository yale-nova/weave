#!/bin/bash

set -euo pipefail

# === Configuration ===
RG_NAME="weave-rg"
CLUSTER_NAME="spark-weave"
ACR_NAME="graminedirect"
IMAGE="$ACR_NAME.azurecr.io/spark-spool-direct:latest"
LOCK_FILE="/tmp/spool_ctl.lock"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
cd "$REPO_ROOT"

COMMAND=${1:-}
shift || true

# === Allow-list for lock-free commands ===
LOCK_FREE_COMMANDS=(ui ui-master monitor collect-metrics check-kubectl cluster-health)

is_lock_free() {
  for cmd in "${LOCK_FREE_COMMANDS[@]}"; do
    [[ "$COMMAND" == "$cmd" ]] && return 0
  done
  return 1
}

# === Enforce lock unless command is exempt ===
if ! is_lock_free "$COMMAND"; then
  if [ -f "$LOCK_FILE" ]; then
    echo "🚫 Another spool-ctl.sh script is already running (lock file exists at $LOCK_FILE)."
    echo "If this is incorrect, use 'submit-job stop' to stop running jobs and clear the lock."
    exit 1
  fi
  trap 'echo "⚠️  Script exited unexpectedly. Cleaning up..."; rm -f "$LOCK_FILE"' EXIT
  touch "$LOCK_FILE"
fi

# === Usage ===
if [ -z "$COMMAND" ]; then
  echo "Usage: $0 <command> [args...]"
  echo "Available commands:"
  echo "  create-cluster <CLUSTER_SIZE> <CORES> <MEMORY_GB>   Create AKS cluster"
  echo "  delete-cluster                                      Delete AKS cluster"
  echo "  recreate-image                                      Rebuild and push container image"
  echo "  submit-job [args...]                                Submit Spark job to cluster"
  echo "  submit-job stop                                     Stop Spark job and remove lock"
  echo "  ui                                                  Port-forward Spark app UI"
  echo "  ui-master                                           Port-forward Spark Master UI"
  echo "  monitor                                             Show live resource usage of pods"
  echo "  collect-metrics                                     Fetch and summarize Spark metrics JSON"
  echo "  check-kubectl                                       Verify kubectl and metrics-server"
  echo "  cluster-health                                      Show node and pod status"
  exit 1
fi

case "$COMMAND" in
  create-cluster)
    if [ $# -lt 3 ]; then
      echo "❌ Usage: $0 create-cluster <CLUSTER_SIZE> <CORES> <MEMORY_GB>"
      exit 1
    fi
    CLUSTER_SIZE=$1; shift
    CORES=$1; shift
    MEMORY=$1; shift
    echo "🚀 Creating AKS cluster with $CLUSTER_SIZE nodes, $CORES cores, $MEMORY GB RAM per node..."
    ./scripts/create_aks_cluster.sh "$CLUSTER_SIZE" "$CORES" "$MEMORY"
    ;;

  delete-cluster)
    echo "🗑️ Deleting cluster and cleaning up lock..."
    rm -f "$LOCK_FILE"
    az aks delete --yes --name "$CLUSTER_NAME" --resource-group "$RG_NAME"
    ;;

  recreate-image)
    echo "♻️ Rebuilding container image with --debug --test..."
    ./scripts/build_acr.sh "$ACR_NAME" --debug --test
    ;;

  submit-job)
    echo "📤 Submitting job with arguments: $@"
    if [ -f "$LOCK_FILE" ]; then
      echo "🔒 Cluster is active but no experiment is running — proceeding with job submit."
    fi
    ./scripts/deploy_spark_job.sh "$@"
    ;;

  submit-job\ stop)
    echo "🚑 Stopping running Spark job and removing lock..."
    kubectl delete job spark-job --ignore-not-found
    rm -f "$LOCK_FILE"
    ;;

  ui)
    echo "🌐 Forwarding app UI (port 4040)..."
    POD=$(kubectl get pod -l job-name=spark-job -o jsonpath='{.items[0].metadata.name}')
    kubectl port-forward "$POD" 4040:4040
    ;;

  ui-master)
    echo "🌐 Forwarding Spark Master UI (port 8080)..."
    POD=$(kubectl get pods -l app=spark-master -o jsonpath='{.items[0].metadata.name}')
    kubectl port-forward "$POD" 8080:8080
    ;;

  monitor)
    echo "📱 Monitoring pod resource usage..."
    if ! command -v kubectl &>/dev/null; then
      echo "❌ 'kubectl' not found. Please install it:"
      echo "  brew install kubectl"
      exit 1
    fi
    kubectl top pods
    ;;

  check-kubectl)
    echo "🔎 Checking for 'kubectl' and metrics-server..."
    if ! command -v kubectl &>/dev/null; then
      echo "❌ 'kubectl' not found. Install it with: brew install kubectl"
      exit 1
    fi
    echo "✅ 'kubectl' is installed"
    if kubectl get apiservices | grep metrics.k8s.io | grep -q True; then
      echo "✅ metrics-server is running"
    else
      echo "⚠️  metrics-server not detected. You can install it with:"
      echo "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
    ;;

  cluster-health)
    echo "📦 Nodes:"
    kubectl get nodes -o wide
    echo -e "\n📦 Pods:"
    kubectl get pods -o wide --all-namespaces
    ;;

  collect-metrics)
    echo "📊 [STUB] Collecting Spark /metrics/json..."
    # TODO: curl from port-forwarded localhost:4040 and parse key metrics
    ;;

  *)
    echo "❌ Unknown command: $COMMAND"
    exit 1
    ;;
esac
