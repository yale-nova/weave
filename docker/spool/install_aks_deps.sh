#!/bin/bash
set -e

echo "📦 Installing dependencies for AKS Spark setup..."

OS="$(uname)"
if [[ "$OS" == "Darwin" ]]; then
  echo "🧠 Detected macOS"

  # Install Homebrew if not present
  if ! command -v brew &>/dev/null; then
    echo "🍺 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  for pkg in kubectl azure-cli jq openjdk@11; do
    if ! brew list --formula | grep -q "^$pkg\$"; then
      echo "🔧 Installing $pkg..."
      brew install "$pkg"
    else
      echo "✅ $pkg is already installed"
    fi
  done

  if ! command -v docker &>/dev/null; then
    echo "🐳 Installing Docker Desktop (requires manual step)..."
    brew install --cask docker
    echo "⚠️ Please start Docker Desktop manually before continuing."
  else
    echo "✅ Docker is already installed"
  fi

  echo "📍 Setting JAVA_HOME..."
  echo "📍 Setting JAVA_HOME..."
  export JAVA_HOME=$(/usr/libexec/java_home -v 11 2>/dev/null || echo "")
  if [[ -z "$JAVA_HOME" ]]; then
    echo "❌ Could not locate Java 11. Attempting to link manually..."
    sudo ln -sfn /opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-11.jdk
    export JAVA_HOME=$(/usr/libexec/java_home -v 11)
  fi
  echo "✅ JAVA_HOME set to $JAVA_HOME"

  echo "🔧 Adding JAVA_HOME and PATH to shell startup file..."
  SHELL_RC="$HOME/.zshrc"
  [[ "$SHELL" == *bash* ]] && SHELL_RC="$HOME/.bashrc"
   grep -qxF 'export PATH="/opt/homebrew/opt/openjdk@11/bin:$PATH"' "$SHELL_RC" || echo 'export PATH="/opt/homebrew/opt/openjdk@11/bin:$PATH"' >> "$SHELL_RC"
  grep -qxF 'export CPPFLAGS="-I/opt/homebrew/opt/openjdk@11/include"' "$SHELL_RC" || echo 'export CPPFLAGS="-I/opt/homebrew/opt/openjdk@11/include"' >> "$SHELL_RC"
  grep -qxF 'export JAVA_HOME=$(/usr/libexec/java_home -v 11)' "$SHELL_RC" || echo 'export JAVA_HOME=$(/usr/libexec/java_home -v 11)' >> "$SHELL_RC"
  echo "✅ Updated $SHELL_RC"


elif [[ "$OS" == "Linux" ]]; then
  echo "🐧 Detected Linux"

  sudo apt update

  for pkg in kubectl azure-cli jq docker.io openjdk-11-jdk; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      echo "🔧 Installing $pkg..."
      sudo apt install -y "$pkg"
    else
      echo "✅ $pkg is already installed"
    fi
  done

  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker "$USER"

  echo "📍 Setting JAVA_HOME..."
  export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
  echo "✅ JAVA_HOME set to $JAVA_HOME"

else
  echo "❌ Unsupported OS: $OS"
  exit 1
fi

echo "✅ All dependencies installed."
echo "ℹ️ Restart your terminal or run 'newgrp docker' to refresh Docker group permissions on Linux."
