#!/usr/bin/env bash
# parse-system-deps.sh
set -euo pipefail

ROOT_DIR="${1:-/opt/private-repos}"
LOCKFILE="/opt/system-deps.lock"
REPO_SETUP="/opt/deps-setup.sh"

mkdir -p ./tmp
> "$LOCKFILE"
> "$REPO_SETUP"

declare -A DEPS_REPO

while IFS= read -r -d '' file; do
  echo "🔍 Reading $file"
  count=$(yq '.packages | length' "$file")

  for i in $(seq 0 $((count - 1))); do
    name=$(yq -r ".packages[$i].name" "$file")
    repo=$(yq -r ".packages[$i].repo.source // \"\"" "$file")
    key=$(yq -r ".packages[$i].repo.key_url // \"\"" "$file")

    # Handle conflicts
    if [[ -n "${DEPS_REPO[$name]:-}" && "$repo" != "${DEPS_REPO[$name]}" ]]; then
      echo "❌ Conflict detected for package '$name':"
      echo "    - Source 1: ${DEPS_REPO[$name]}"
      echo "    - Source 2: $repo"
      exit 1
    fi
    DEPS_REPO["$name"]="$repo"

    # Append lockfile
    echo "$name" >> "$LOCKFILE"

    # Append repo commands
    if [[ -n "$repo" ]]; then
      echo "echo '$repo' > /etc/apt/sources.list.d/$name.list" >> "$REPO_SETUP"
    fi
    if [[ -n "$key" ]]; then
      echo "curl -sL '$key' | apt-key add -" >> "$REPO_SETUP"
    fi

    # Handle manual installs (skip yq — assume pre-installed)
    if yq -e ".packages[$i].manual_install" "$file" >/dev/null 2>&1 && [[ "$name" != "yq" ]]; then
      url=$(yq -r ".packages[$i].manual_install.url" "$file")
      target=$(yq -r ".packages[$i].manual_install.target" "$file")
      chmod_val=$(yq -r ".packages[$i].manual_install.chmod" "$file")
      echo "curl -sL '$url' -o '$target'" >> "$REPO_SETUP"
      echo "chmod $chmod_val '$target'" >> "$REPO_SETUP"
    fi
    
        if yq -e ".packages[$i].manual_install.unpack" "$file" >/dev/null 2>&1; then
      unpack_type=$(yq -r ".packages[$i].manual_install.unpack.type" "$file")
      unpack_dest=$(yq -r ".packages[$i].manual_install.unpack.dest" "$file")
      link_to=$(yq -r ".packages[$i].manual_install.unpack.link_to" "$file")
      export_path=$(yq -r ".packages[$i].manual_install.unpack.export_path" "$file")

      if [[ "$unpack_type" == "tar.gz" ]]; then
        echo "tar -xvzf '$target' -C '$unpack_dest'" >> "$REPO_SETUP"
      else
        echo "❌ Unsupported unpack type: $unpack_type"
        exit 1
      fi

      if [[ -n "$link_to" ]]; then
        basename_target=$(basename "$target" .tgz)
        echo "ln -sfn '$unpack_dest/$basename_target' '$link_to'" >> "$REPO_SETUP"
      fi

      if [[ -n "$export_path" ]]; then
        echo "export PATH='$export_path':\$PATH" >> "$REPO_SETUP"
      fi
    fi

  done

done < <(find "$ROOT_DIR" -name system-deps.yaml -print0)

sort -u "$LOCKFILE" -o "$LOCKFILE"
echo "✅ Dependency lockfile created at $LOCKFILE"
echo "✅ Repo setup script created at $REPO_SETUP"
