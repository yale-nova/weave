#!/usr/bin/env bash
set -e

# Directories
SRC_DIR="$(pwd)"
TMP_DIR="/tmp/pipreqs-output"
PYPROJECT="pyproject.toml"

# Step 1: Install pipreqs and toml libraries
echo "📦 Installing pipreqs and toml..."
pip install --quiet 'pipreqs==0.4.11' 'toml'


# Step 2: Extract imports via pipreqs
echo "🔍 Extracting Python imports with pipreqs..."
mkdir -p "$TMP_DIR"
pipreqs "$SRC_DIR" --force --savepath "$TMP_DIR/requirements.txt"

# Step 3: Confirm with user
REQ_FILE="$TMP_DIR/requirements.txt"
if [ ! -s "$REQ_FILE" ]; then
    echo "❌ No requirements found. Aborting."
    exit 1
fi

echo "📋 Extracted dependencies:"
cat "$REQ_FILE"
echo ""
read -p "⬆️  Do you want to update pyproject.toml with these dependencies? (y/n): " confirm

if [ "$confirm" != "y" ]; then
    echo "❌ Aborted by user."
    exit 1
fi

# Step 4: Parse and update pyproject.toml
echo "📝 Updating pyproject.toml..."

python3 - <<EOF
import toml
from pathlib import Path

req_path = Path("$REQ_FILE")
deps = [line.strip() for line in req_path.read_text().splitlines() if line.strip() and not line.startswith("#")]

toml_path = Path("$SRC_DIR") / "$PYPROJECT"
if not toml_path.exists():
    print(f"❌ {toml_path} not found!")
    exit(1)

doc = toml.load(toml_path)
doc.setdefault("project", {})["dependencies"] = deps
toml_path.write_text(toml.dumps(doc))
print("✅ pyproject.toml updated successfully.")
EOF

