#!/usr/bin/env bash
set -euo pipefail

LOCKFILE="${1:-/opt/system-deps.lock}"
REPO_SETUP="/opt/deps-setup.sh"

echo "🔧 Running repo and manual setup commands..."
if [[ -f "$REPO_SETUP" ]]; then
  bash "$REPO_SETUP"
  apt-get update    # <-- move apt update HERE
else
  echo "⚠️  No repo setup script found at $REPO_SETUP. Continuing without repo additions."
fi

echo "📦 Installing packages from lockfile..."
if [[ -f "$LOCKFILE" ]]; then
  xargs -a "$LOCKFILE" apt-get install -y --no-install-recommends
else
  echo "❌ Lockfile not found at $LOCKFILE"
  exit 1
fi

echo "✅ All packages installed."
