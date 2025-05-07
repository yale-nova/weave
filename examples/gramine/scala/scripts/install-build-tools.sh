#!/usr/bin/env bash
set -euo pipefail

TOOLS_FILE="$(dirname "$0")/../deps/build-tools.yaml"

echo "🔍 Installing tools from $TOOLS_FILE..."

if [ ! -f "$TOOLS_FILE" ]; then
    echo "⚠️  No $TOOLS_FILE found."
    exit 0
fi

# Ensure yq is available
if ! command -v yq &>/dev/null; then
    echo "📦 Installing yq..."
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    chmod +x /usr/local/bin/yq
fi

# Extract and add external repos (before apt update)
PACKAGES=()
for index in $(yq e '.[].name' "$TOOLS_FILE" | nl -v 0 | cut -f1); do
    NAME=$(yq e ".[$index].name" "$TOOLS_FILE")
    REPO_SRC=$(yq e ".[$index].repo.source" "$TOOLS_FILE")
    KEY_URL=$(yq e ".[$index].repo.key_url" "$TOOLS_FILE")

    if [ "$REPO_SRC" != "null" ]; then
        echo "➕ Adding external repo for $NAME..."
        echo "$REPO_SRC" | tee /etc/apt/sources.list.d/${NAME}.list > /dev/null

        if [ "$KEY_URL" != "null" ]; then
            echo "🔑 Fetching GPG key for $NAME..."
            curl -fsSL "$KEY_URL" | gpg --dearmor -o /usr/share/keyrings/${NAME}.gpg
        fi
    fi

    MANUAL_URL=$(yq e ".[$index].manual_install.url" "$TOOLS_FILE")
    if [ "$MANUAL_URL" != "null" ]; then
        TARGET=$(yq e ".[$index].manual_install.target" "$TOOLS_FILE")
        CHMOD=$(yq e ".[$index].manual_install.chmod" "$TOOLS_FILE")
        echo "⬇️ Manually installing $NAME from $MANUAL_URL..."
        wget -qO "$TARGET" "$MANUAL_URL"
        chmod "$CHMOD" "$TARGET"
    else
        PACKAGES+=("$NAME")
    fi
done

echo "🔄 Updating apt..."
apt-get update

if [ ${#PACKAGES[@]} -gt 0 ]; then
    echo "📦 Installing packages: ${PACKAGES[*]}"
    apt-get install -y --no-install-recommends "${PACKAGES[@]}"
else
    echo "✅ No APT packages to install."
fi
