#!/bin/bash

# setup.sh: Complete VPS Bootstrap (User, SSH, Docker, Security)
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
# This script MUST be run as ROOT on a fresh Debian/Ubuntu VPS.

set -e # Exit on error

echo "🚀 Starting Complete VPS Bootstrap..."

# --- DATA SECTION: UPDATE YOUR KEYS HERE ---
# Add your public keys here (one per line)
SSH_PUBLIC_KEYS="
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOm6A9331n/I9Z44FfGvV3fGZ... user@example.com
"
# -------------------------------------------

USER_NAME="ss"
SSH_PORT=22

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
echo "✅ SSH keys imported."

# 4. Add 'ss' to Sudoers (Passwordless Sudo)
echo "🔑 Granting sudo privileges to '$USER_NAME'..."
usermod -aG sudo "$USER_NAME"
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"

# 5. Harden SSH Configuration
echo "🛡️ Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Disable Password Auth, Disable Root Login, Set Port
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Ensure SSH Port is set (Explicitly 22)
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# 6. Install Docker
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

# 7. Configure Firewall (UFW)
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

# 8. Restart Services
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
