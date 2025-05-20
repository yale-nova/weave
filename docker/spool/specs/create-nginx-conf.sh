#!/bin/bash
set -euo pipefail

NAMESPACE=${1:-spark}
CONF_FILE=${2:-./specs/nginx-map.conf}
MASTER_POD_NAME=${3:-spark-master}
MASTER_UI_PORTS=(8080 8081)

cat <<EOF > "$CONF_FILE"
events {}

http {
  server {
    listen 80;

    location / {
      root /usr/share/nginx/html;
      index index.html;
    }

    location /master-sgx/ {
      proxy_pass http://$MASTER_POD_NAME:${MASTER_UI_PORTS[0]}/;
      proxy_redirect off;
      rewrite ^/master-sgx(/.*)\$ \$1 break;
    }

    location /master-direct/ {
      proxy_pass http://$MASTER_POD_NAME:${MASTER_UI_PORTS[1]}/;
      proxy_redirect off;
      rewrite ^/master-direct(/.*)\$ \$1 break;
    }

    # Static entry for Flask web UI
    location /webui/ {
      proxy_pass http://$MASTER_POD_NAME:9090/;
      proxy_redirect off;
      rewrite ^/webui(/.*)\$ \$1 break;
    }
EOF

echo "🔍 Discovering Spark worker pods..."

# Append dynamic worker reverse proxies
WORKER_PODS=$(kubectl get pods -n "$NAMESPACE" -l 'role in (direct,sgx)' -o jsonpath='{.items[*].metadata.name}')
for POD in $WORKER_PODS; do
  echo "📎 Adding reverse proxy for worker $POD"
  cat <<EOF >> "$CONF_FILE"
    location /$POD/ {
      proxy_pass http://$POD:8081/;
      proxy_redirect off;
      rewrite ^/$POD(/.*)\$ \$1 break;
    }
EOF
done

cat <<EOF >> "$CONF_FILE"
  }
}
EOF

echo "✅ NGINX config written to $CONF_FILE"
