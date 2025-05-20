#!/bin/bash

set -e  # Stop on error

echo "🛠️ Updating and installing dependencies..."
sudo apt-get update
sudo apt-get install -y curl wget apt-transport-https software-properties-common gnupg lsb-release

echo "☕ Installing OpenJDK 11..."
sudo apt-get install -y openjdk-11-jdk

echo "🐍 Installing Python 3, pip, and virtualenv..."
sudo apt-get install -y python3 python3-pip python3-venv

echo "📦 Upgrading pip..."
pip3 install --upgrade pip

echo "📚 Installing Python libraries: Flask, pandas, numpy, plotly..."
pip3 install flask pandas numpy plotly

echo "☁️ Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

echo "🚢 Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

echo "✅ All tools installed successfully!"

