#!/bin/bash

# setup.sh: Complete VPS Bootstrap (User, SSH, Docker, Security)
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
# This script MUST be run as ROOT on a fresh Debian/Ubuntu VPS.

set -e # Exit on error

echo "🚀 Starting Complete VPS Bootstrap..."

# --- CONFIGURATION: UPDATE THESE DETAILS FIRST ---
# 1. Your Public SSH Keys (Required)
SSH_PUBLIC_KEYS="
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOm6A9331n/I9Z44FfGvV3fGZ... user@example.com
"

# 2. System Username
USER_NAME="cb"

# 3. SSH Port (Standard is 22)
SSH_PORT=22

# 4. Failsafe: Sync keys to root? (Recommended)
# If true, you can log in as root ONLY with an SSH key.
SYNC_KEYS_TO_ROOT=true

# Note: Password-based login will be DISABLED for security. 
# Both 'root' and '$USER_NAME' will be SSH-key ONLY.
# -------------------------------------------------

# 1. Update Package Registry & Install Essentials
echo "📦 Updating package registry and installing essentials..."
apt-get update -y
apt-get install -y sudo curl git gnupg ca-certificates openssh-server ufw

# 2. Create 'ss' User (Passwordless/SSH-Only)
if id "$USER_NAME" &>/dev/null; then
    echo "⚠️ User '$USER_NAME' already exists. Skipping creation."
else
    echo "👤 Creating user '$USER_NAME'..."
    useradd -m -s /bin/bash "$USER_NAME"
    passwd -l "$USER_NAME" # Lock password, force SSH keys
    echo "✅ User '$USER_NAME' created."
fi

# 3. Configure SSH Keys for 'ss'
echo "🔑 Configuring SSH Authorized Keys..."
HOME_DIR="/home/$USER_NAME"
SSH_DIR="$HOME_DIR/.ssh"

mkdir -p "$SSH_DIR"
echo "$SSH_PUBLIC_KEYS" > "$SSH_DIR/authorized_keys"

chown -R "$USER_NAME:$USER_NAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"
echo "✅ SSH keys imported for '$USER_NAME'."

# 4. Failsafe: Sync Keys to Root
if [ "$SYNC_KEYS_TO_ROOT" = true ]; then
    echo "🔑 Syncing SSH keys to root user for failsafe..."
    mkdir -p /root/.ssh
    echo "$SSH_PUBLIC_KEYS" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH keys imported for root."
fi

# 5. Add 'ss' to Sudoers (Passwordless Sudo)
echo "🔑 Granting sudo privileges to '$USER_NAME'..."
usermod -aG sudo "$USER_NAME"
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"

# 6. Harden SSH Configuration
echo "🛡️ Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Disable Password Auth, Set Root to Key-Only, Set Port
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Ensure SSH Port is set (Explicitly 22)
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# 7. Install Docker
echo "🐳 Installing Docker Engine..."
# Remove old versions
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    apt-get remove -y $pkg || true
done

# Setup Docker Repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add 'ss' to Docker group
groupadd -f docker
usermod -aG docker "$USER_NAME"

# 8. Configure Firewall (UFW)
echo "🛡️ Configuring Firewall..."
# First, ensure we don't lock ourselves out
ufw allow ssh || true
ufw allow $SSH_PORT/tcp
ufw allow 80/tcp # HTTP
ufw allow 443/tcp # HTTPS

ufw default deny incoming
ufw default allow outgoing

echo "🚀 Enabling Firewall..."
ufw --force enable

# 9. Restart Services
echo "🔄 Restarting SSH Service..."
systemctl restart ssh

echo "🏁 Setup Complete!"
echo "--------------------------------------------------"
echo "User: $USER_NAME"
echo "SSH Port: $SSH_PORT"
echo "Auth: SSH Key Only"
echo "Docker: Installed & configured for '$USER_NAME'"
echo "--------------------------------------------------"
echo "⚠️  IMPORTANT: Test your connection in a new terminal:"
echo "    ssh $USER_NAME@YOUR_IP -p $SSH_PORT"
echo "--------------------------------------------------"
