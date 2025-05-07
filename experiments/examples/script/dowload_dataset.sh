#!/bin/bash
set -euo pipefail

DATA_DIR="examples/data/full"
mkdir -p "$DATA_DIR"

# 1. Enron Dataset (tar.gz)
ENRON_URL="https://www.cs.cmu.edu/~enron/enron_mail_20150507.tar.gz"
ENRON_TAR="$DATA_DIR/enron_mail_20150507.tar.gz"
ENRON_EXTRACTED="$DATA_DIR/enron.tsv"

if [ ! -f "$ENRON_EXTRACTED" ]; then
  echo "⬇️ Downloading and extracting Enron..."
  wget -O "$ENRON_TAR" "$ENRON_URL"
  tar -xzf "$ENRON_TAR" -C "$DATA_DIR"

  # Optional: convert extracted maildir to flat TSV
  echo "📄 Converting Enron to TSV format (flat)..."
  python3 <<EOF
import os
from pathlib import Path
out_file = open("$ENRON_EXTRACTED", "w")
root = Path("$DATA_DIR/maildir")
for rootdir, _, files in os.walk(root):
    for fname in files:
        path = os.path.join(rootdir, fname)
        try:
            with open(path, "r", errors='ignore') as f:
                lines = f.read().splitlines()
                subj = next((l[9:] for l in lines if l.startswith("Subject: ")), "No Subject")
                body_index = next((i for i, l_
