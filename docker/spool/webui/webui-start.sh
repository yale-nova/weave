#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
NAMESPACE="spark"
NGINX_POD="spark-nginx"
NGINX_SERVICE="spark-nginx"
CONF_SCRIPT="$REPO_ROOT/specs/create-nginx-conf.sh"
INDEX_GEN_SCRIPT="$REPO_ROOT/webui/create-index-html.sh"
INDEX_HTML="$REPO_ROOT/webui/index.html"
FLASK_SCRIPT="$REPO_ROOT/scripts/helloworld/flask_plot_runner.py"
MASTER_POD=$(kubectl get pods -n "$NAMESPACE" -l role=master -o jsonpath='{.items[0].metadata.name}')

echo "🧹 Cleaning old nginx pod and service..."
kubectl delete pod "$NGINX_POD" -n "$NAMESPACE" --ignore-not-found
kubectl delete svc "$NGINX_SERVICE" -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap spark-nginx-config -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap spark-nginx-index -n "$NAMESPACE" --ignore-not-found

echo "📦 Creating nginx.conf..."
bash "$CONF_SCRIPT"

echo "📝 Generating index.html..."
bash "$INDEX_GEN_SCRIPT"
mv index.html "$INDEX_HTML"

echo "🧩 Creating config map for nginx..."
kubectl create configmap spark-nginx-config \
  --from-file=nginx.conf="$REPO_ROOT/specs/nginx-map.conf" \
  --from-file=index.html="$INDEX_HTML" \
  -n "$NAMESPACE"

echo "🧩 Creating config map for indexing..."
kubectl create configmap spark-nginx-index \
  --from-file=index.html=$REPO_ROOT/webui/index.html \
  -n "$NAMESPACE"

echo "🔪 Killing any existing Flask server..."
kubectl exec -n "$NAMESPACE" "$MASTER_POD" -- \
  pkill -f flask_plot_runner.py || true

echo "🧩 Copying the Flask server..."
kubectl cp "$FLASK_SCRIPT" "$NAMESPACE/$MASTER_POD:/workspace/flask_plot_runner.py"

echo "🐍 Starting new Flask server..."
kubectl exec -n "$NAMESPACE" "$MASTER_POD" -- bash -c '
  cd /workspace
  nohup python3 flask_plot_runner.py > flask_server_log.out 2>&1 &
  echo "✅ Flask server launched."
'

echo "🚀 Creating Nginx pod and service..."
kubectl apply -f "$REPO_ROOT/specs/nginx-pod.yaml"
kubectl apply -f "$REPO_ROOT/specs/nginx-service.yaml"

echo "⏳ Waiting for Nginx pod and service to be ready..."
kubectl wait --for=condition=Ready pod/$NGINX_POD -n "$NAMESPACE" --timeout=120s

# Get node resource group
NODE_RG=$(az aks show --name spark-cluster --resource-group weave-rg --query nodeResourceGroup -o tsv)

NGINX_DNS=$(az network public-ip show \
  --name spark-master-ip \
  --resource-group $NODE_RG \
  --query "dnsSettings.fqdn" -o tsv)
echo "🌐 Nginx server is live at: http://$NGINX_DNS"
echo "📄 Index page: http://$NGINX_DNS/index.html"

