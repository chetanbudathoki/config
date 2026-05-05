#!/bin/bash

# docker.sh: Docker & Docker Compose Installation for Debian
# Usage:
#   chmod +x docker.sh
#   ./docker.sh

set -e # Exit on error

echo "🐳 Starting Docker Installation..."

# 1. Remove old versions
echo "🧹 Cleaning up old Docker versions..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    apt-get remove -y $pkg || true
done

# 2. Setup Docker's APT repository
echo "📥 Setting up Docker repository..."
apt-get update
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

# 3. Install Docker Engine and Docker Compose
echo "🛠️ Installing Docker Engine and Compose plugin..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 4. Post-installation steps (Group Management)
echo "👥 Managing Docker groups and permissions..."
# Create docker group if it doesn't exist
groupadd -f docker

# Add 'ss' user to docker group
if id "ss" &>/dev/null; then
    echo "Adding 'ss' user to docker group..."
    usermod -aG docker ss
    # Ensure the socket is owned by the docker group
    chown root:docker /var/run/docker.sock || true
    chmod 660 /var/run/docker.sock || true
fi

# Add current user to docker group
usermod -aG docker $USER

# 5. Verification
echo "✅ Verifying installation..."
docker --version
docker compose version

echo "🏁 Docker Setup Complete!"
echo "⚠️ Note: You may need to log out and back in for group changes to take effect."
