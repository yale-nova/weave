#!/bin/bash
set -euo pipefail

NAMESPACE=${1:-spark}
OUTPUT=${2:-index.html}
MASTER_POD_NAME=${3:-spark-master}

echo "📝 Generating $OUTPUT..."

cat <<EOF > "$OUTPUT"
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Spark WebUI Portal</title>
  <style>
    body { font-family: sans-serif; padding: 2rem; background: #f9f9f9; }
    h1 { color: #333; }
    ul { line-height: 1.6; }
    a { text-decoration: none; color: #007acc; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>Welcome to the Spark WebUI Portal</h1>
  <ul>
    <li><a href="/master-sgx/" target="_blank">Spark Master (SGX cluster)</a></li>
    <li><a href="/master-direct/" target="_blank">Spark Master (Simulation cluster)</a></li>
    <li><a href="/webui/" target="_blank">📊 Visualization Dashboard (Flask)</a></li>
EOF

echo "🔍 Discovering worker pods..."

WORKER_PODS=$(kubectl get pods -n "$NAMESPACE" -l 'role in (direct,sgx)' -o jsonpath='{.items[*].metadata.name}')
for POD in $WORKER_PODS; do
  FRIENDLY_NAME=$(echo "$POD" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
  echo "📎 Adding entry for $POD → $FRIENDLY_NAME"
  echo "    <li><a href=\"/$POD/\" target=\"_blank\">$FRIENDLY_NAME Web UI</a></li>" >> "$OUTPUT"
done

cat <<EOF >> "$OUTPUT"
  </ul>
</body>
</html>
EOF

echo "✅ index.html generated at $OUTPUT"
