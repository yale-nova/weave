#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(greadlink -f "$SCRIPT_DIR/..")"
DEPS_DIR="$ROOT_DIR/deps"

echo "🍎 Bootstrapping Scala test environment on macOS..."

# === Step 1: Install system packages via Homebrew ===
echo "🧪 Step 1: Installing Homebrew packages..."
brew update
brew install sbt scala openjdk curl yq coreutils gnupg

# === Step 2: Java env setup for macOS (brew's OpenJDK) ===
echo "🔗 Step 2: Setting up Java environment..."
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"

# === Step 3: Build JARs ===
echo "🏗 Step 3: Building fat JARs with sbt..."
"$SCRIPT_DIR/build-fatjars.sh"

# === Step 4: Run Scala tests (reference + Gramine if available) ===
echo "🚀 Step 4: Running Scala tests..."
"$SCRIPT_DIR/run-scala-tests.sh" --native

echo "✅ Done. All JARs built and tested locally on macOS!"
