#!/bin/bash

# Variables (you can change these)
USERNAME="aciuser"
PASSWORD="acipass123"

# Install sudo and SSH
apt update && apt install -y openssh-server sudo

# Set up SSH
mkdir -p /var/run/sshd
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# Create user
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Start SSH server
service ssh start

echo "User '$USERNAME' created with password '$PASSWORD'"
echo "SSH server started. Make sure port 22 is open and the container has a public IP."

