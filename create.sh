#!/bin/bash

# create.sh: Initial VPS setup (Sudo, User creation, Firewall)
# Usage:
#   chmod +x create.sh
#   ./create.sh
# This script is intended to be run as ROOT on a fresh VPS.
# It installs mandatory tools and creates the 'ss' service user.

set -e # Exit on error

echo "🚀 Starting Phase 1: Infrastructure Setup..."

# 1. Update Package Registry
echo "📦 Updating package registry..."
apt-get update -y

# 2. Install Sudo
echo "🛠️ Installing sudo..."
apt-get install -y sudo

# 3. Create 'ss' User
# We use -m to create home directory and -s to set bash as default shell
USER_NAME="ss"
USER_PASS="HeroBudathoki" # Default temporary password

if id "$USER_NAME" &>/dev/null; then
    echo "⚠️ User '$USER_NAME' already exists. Skipping creation."
else
    echo "👤 Creating user '$USER_NAME'..."
    useradd -m -s /bin/bash "$USER_NAME"
    echo "$USER_NAME:$USER_PASS" | chpasswd
    echo "✅ User '$USER_NAME' created with temporary password."
fi

# 4. Add 'ss' to Sudoers
echo "🔑 Adding '$USER_NAME' to sudo group..."
usermod -aG sudo "$USER_NAME"

# 5. Configure Passwordless Sudo for 'ss' (Optional but recommended for CI/CD)
echo "📝 Configuring passwordless sudo for '$USER_NAME'..."
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER_NAME

# 6. Firewall Configuration (UFW)
echo "🛡️ Configuring Firewall..."
apt-get install -y ufw

# We MUST allow the SSH port before enabling, otherwise we lock ourselves out.
# Since you're using port 21 for SSH, we allow it specifically.
echo "🔓 Allowing Port 21 (SSH) and 22 (Default SSH)..."
ufw allow 21/tcp
ufw allow 22/tcp

# Enable Firewall
echo "🚀 Enabling Firewall..."
ufw --force enable

echo "🏁 Phase 1 Complete!"
echo "--------------------------------------------------"
echo "User: $USER_NAME"
echo "Note: Please change the password immediately or setup SSH keys."
echo "--------------------------------------------------"
