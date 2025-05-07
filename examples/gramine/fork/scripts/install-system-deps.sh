#!/usr/bin/env bash
set -euo pipefail

DEPS_FILE="$(dirname "$0")/../deps/system-deps.yaml"

if ! command -v yq >/dev/null 2>&1; then
    echo "❌ 'yq' is not installed. Please run install-build-tools.sh first."
    exit 1
fi

if [ ! -f "$DEPS_FILE" ]; then
    echo "⚠️  No system-deps.yaml found at $DEPS_FILE."
    exit 0
fi

echo "📦 Reading packages from $DEPS_FILE..."

count=$(yq '.packages | length' "$DEPS_FILE")
for i in $(seq 0 $((count - 1))); do
    pkg=$(yq -r ".packages[$i].name" "$DEPS_FILE")

    if dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "✅ $pkg already installed."
        continue
    fi

    if yq -e ".packages[$i].repo" "$DEPS_FILE" >/dev/null 2>&1; then
        src=$(yq -r ".packages[$i].repo.source" "$DEPS_FILE")
        key_url=$(yq -r ".packages[$i].repo.key_url" "$DEPS_FILE")

        echo "🔐 Adding custom repo for $pkg..."
        echo "$src" | tee "/etc/apt/sources.list.d/$pkg.list"
        curl -sL "$key_url" | apt-key add -
    fi

    echo "📦 Installing $pkg..."
    apt-get update
    apt-get install -y --no-install-recommends "$pkg"
done
