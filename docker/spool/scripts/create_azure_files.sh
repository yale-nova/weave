#!/bin/bash
set -euo pipefail

# ======= CONFIGURE THESE =======
RESOURCE_GROUP="weave-rg"
LOCATION="eastus"
STORAGE_ACCOUNT="sparkstorage$RANDOM"
SHARE_NAME="sparkdata"
# ===============================

echo "🔧 Creating storage account: $STORAGE_ACCOUNT in $RESOURCE_GROUP..."

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS

echo "✅ Storage account created."

echo "📁 Creating file share: $SHARE_NAME..."

az storage share-rm create \
  --resource-group "$RESOURCE_GROUP" \
  --storage-account "$STORAGE_ACCOUNT" \
  --name "$SHARE_NAME"

echo "✅ File share created."

echo "🔐 Getting access key..."

STORAGE_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query '[0].value' -o tsv)

echo ""
echo "🔑 Mount info:"
echo "============================================"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "File Share     : $SHARE_NAME"
echo "Storage Key    : $STORAGE_KEY"
echo ""
echo "🔗 Mount command for Linux:"
echo "sudo apt install -y cifs-utils"
echo "sudo mkdir -p /mnt/azurefiles"
echo "sudo mount -t cifs //${STORAGE_ACCOUNT}.file.core.windows.net/${SHARE_NAME} /mnt/azurefiles \\"
echo "  -o vers=3.0,username=${STORAGE_ACCOUNT},password=${STORAGE_KEY},dir_mode=0777,file_mode=0777,serverino"
echo "============================================"
