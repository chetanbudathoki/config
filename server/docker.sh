#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Update the apt package index
sudo apt update

# Install required packages
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update apt package index again
sudo apt update

# Install Docker Engine, CLI, Containerd, Docker Buildx Plugin
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# Install Docker Compose (standalone version)
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Ensure the binary is accessible
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Start Docker service
sudo systemctl start docker

# Enable Docker to start at boot
sudo systemctl enable docker

# Add user 'cb' to Docker group
sudo usermod -aG docker cb

# Restart Docker service
sudo systemctl restart docker
