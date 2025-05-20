#!/usr/bin/env bash
set -euo pipefail

# Usage: ./update_ssh_config.sh [resource_group]
RG="${1:-my-rg}"
SSH_CONFIG="${HOME}/.ssh/config"

# ensure ssh config exists and is private
mkdir -p "$(dirname "$SSH_CONFIG")"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

echo "🔍 Querying VMs in resource group '$RG'..."
vms=$(az vm list -g "$RG" --query "[].name" -o tsv)

if [ -z "$vms" ]; then
  echo "⚠️  No VMs found in resource group '$RG'."
  exit 1
fi

for vm in $vms; do
  echo -n "  • $vm … "
  # get public IP
  ip=$(az vm list-ip-addresses -g "$RG" -n "$vm" \
       --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" \
       -o tsv)

  if [ -z "$ip" ]; then
    echo "no public IP, skipping."
    continue
  fi

  # if there's already a Host block for this VM, update its HostName
  if grep -qE "^Host $vm\$" "$SSH_CONFIG"; then
    # update the HostName line within that block
    sed -i "/^Host $vm\$/,/^Host /{s/^\s*HostName\s\+.*/    HostName $ip/}" "$SSH_CONFIG"
    echo "updated to $ip"
  else
    # append a new block
    cat >> "$SSH_CONFIG" <<EOF

Host $vm
    HostName $ip
    User azureuser
    IdentityFile ~/.ssh/id_rsa
EOF
    echo "added $ip"
  fi
done

echo "✅ Done. Your ~/.ssh/config has been updated."

