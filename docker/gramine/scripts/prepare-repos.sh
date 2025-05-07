#!/bin/bash
set -euo pipefail

DEST_DIR=./private-clones
HASH_FILE="$DEST_DIR/.repos-hash"
TARBALL="$DEST_DIR/repos.tar.gz"
TMP_CLONE_DIR="$DEST_DIR/_repos_tmp"

mkdir -p "$DEST_DIR"

source private_repos.conf
source github_auth.env

# === Force cleanup on exit ===
cleanup() {
    echo "🧹 Cleaning up temporary repo clones..."
    rm -rf "$TMP_CLONE_DIR"
}
trap cleanup EXIT

# === Step 1: Compute latest hashes ===
echo "📡 Fetching latest commit hashes..."
REPO_HASHES=""
for REPO in $PRIVATEREPOS; do
    HASH=$(curl -s -u "$GITHUB_USERNAME:$GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$REPO/commits/main" | jq -r .sha)
    if [ -z "$HASH" ] || [ "$HASH" == "null" ]; then
        echo "❌ Failed to get latest commit hash for $REPO"
        exit 1
    fi
    REPO_HASHES+="$REPO:$HASH "
done

NEW_HASH=$(echo "$REPO_HASHES" | sha256sum | cut -d' ' -f1)

# === Step 2: Skip clone if already up to date ===
if [ -f "$HASH_FILE" ] && [ -f "$TARBALL" ]; then
    OLD_HASH=$(cat "$HASH_FILE")
    if [ "$OLD_HASH" == "$NEW_HASH" ]; then
        echo "✅ Repo tarball already up to date. Skipping clone."
        exit 0
    fi
fi

# === Step 3: Rehydrate old tarball (for git fetch efficiency) ===
mkdir -p "$TMP_CLONE_DIR"
if [ -f "$TARBALL" ]; then
    echo "📦 Extracting previous tarball to reuse existing clones..."
    tar -xzf "$TARBALL" -C "$TMP_CLONE_DIR"
fi

# === Step 4: Sync repos ===
echo "🔄 Syncing repositories into $TMP_CLONE_DIR"
for REPO in $PRIVATEREPOS; do
    DEST="$TMP_CLONE_DIR/$REPO"
    URL="https://github.com/$GITHUB_USERNAME/$REPO.git"

    if [ -d "$DEST/.git" ]; then
        echo "🔁 Updating $REPO..."
        git -C "$DEST" fetch origin main
        git -C "$DEST" reset --hard origin/main
    else
        echo "📦 Cloning $REPO..."
        git clone --depth=1 "$URL" "$DEST"
    fi
done

# === Step 5: Save hash and tarball ===
echo "$NEW_HASH" > "$HASH_FILE"

echo "📦 Creating updated tarball..."
tar -czf "$TARBALL" -C "$TMP_CLONE_DIR" .

echo "✅ Repositories prepared and packed."

