#!/bin/bash

# PRE-SETUP (Run this manually first on a fresh VPS):
# apt-get update && apt-get install -y git
# git clone https://github.com/chetanbudathoki/config.git && cd config

# --- HOW TO GENERATE YOUR SSH KEYS ---
# Run these commands on your LOCAL computer (not the VPS):
#
# WINDOWS (PowerShell/CMD) or MAC/LINUX:
# 1. ssh-keygen -t ed25519 -C "your_email@example.com"
# 2. Press Enter to use the default path.
# 3. Use 'cat ~/.ssh/id_ed25519.pub' (Mac/Linux) or open the file in Notepad (Windows)
#    located at C:\Users\YourName\.ssh\id_ed25519.pub
# 4. Copy the entire string and paste it into the SSH_PUBLIC_KEYS variable below.
# -------------------------------------

# setup.sh: Complete VPS Bootstrap (User, SSH, Docker, Security)
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# This script is designed to transform a fresh Debian/Ubuntu VPS into a 
# hardened, production-ready environment with Docker and a dedicated user.

set -e # Exit immediately if a command exits with a non-zero status.

echo "🚀 Starting Complete VPS Bootstrap..."

# --- CONFIGURATION: UPDATE THESE DETAILS FIRST ---
# 1. Your Public SSH Keys (Required)
# Paste your public key string here (starting with ssh-ed25519 or ssh-rsa).
SSH_PUBLIC_KEYS="
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILP955M/UahnRbnsKUziEdMip2v5AejqPLsPysWB3ob+ sawarisadhan@gmail.com
"

# 2. System Username
# The primary non-root user that will be used for daily operations and Docker.
USER_NAME="ss"

# 3. SSH Port
# 22 is the standard default. Change if you use a custom port.
SSH_PORT=22

# 4. Failsafe: Sync keys to root? (Highly Recommended)
# If true, your SSH key will also be added to the root user.
# This allows you to log in as root using your key even after disabling passwords.
SYNC_KEYS_TO_ROOT=true

# 5. Security Extras: Auto-updates & Brute-force protection
ENABLE_SECURITY_EXTRAS=true

# 6. Infrastructure Extras: Swap & Timezone
# Swap is virtual RAM. 2G is usually perfect for 1GB-2GB RAM servers.
SWAP_SIZE="2G"
TIMEZONE="UTC"

# Note: Password-based login will be DISABLED for security. 
# Both 'root' and '$USER_NAME' will be SSH-key ONLY.
# -------------------------------------------------

# 1. Update Package Registry & Install Essentials
# We install 'sudo' for admin tasks, 'ufw' for the firewall, and 
# 'openssh-server' to manage remote access.
echo "📦 Updating package registry and installing essentials..."
apt-get update -y
apt-get install -y sudo curl git gnupg ca-certificates openssh-server ufw bash-completion

# 2. Create the Service User (Passwordless/SSH-Only)
# We use -m to create a home directory and -s to set Bash as the default shell.
# We then LOCK the password ('passwd -l') to ensure only SSH keys can be used for login.
if id "$USER_NAME" &>/dev/null; then
    echo "⚠️ User '$USER_NAME' already exists. Skipping creation."
else
    echo "👤 Creating user '$USER_NAME'..."
    useradd -m -s /bin/bash "$USER_NAME"
    passwd -l "$USER_NAME" 
    echo "✅ User '$USER_NAME' created with locked password (SSH Key Only)."
fi

# 3. Configure SSH Keys for the Service User
# We create the .ssh directory and set strict permissions (700 for dir, 600 for keys).
# This is required by SSH for security; otherwise, it will reject the keys.
echo "🔑 Configuring SSH Authorized Keys for '$USER_NAME'..."
HOME_DIR="/home/$USER_NAME"
SSH_DIR="$HOME_DIR/.ssh"

mkdir -p "$SSH_DIR"
echo "$SSH_PUBLIC_KEYS" > "$SSH_DIR/authorized_keys"

chown -R "$USER_NAME:$USER_NAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"
echo "✅ SSH keys imported for '$USER_NAME'."

# 4. Failsafe: Sync Keys to Root
# This ensures that even if something happens to the '$USER_NAME' account, 
# you can still log in as root using your private key.
if [ "$SYNC_KEYS_TO_ROOT" = true ]; then
    echo "🔑 Syncing SSH keys to root user for failsafe..."
    mkdir -p /root/.ssh
    echo "$SSH_PUBLIC_KEYS" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH keys imported for root."
fi

# 5. Add Service User to Sudoers (Passwordless Sudo)
# This allows the user to run admin commands via 'sudo' without a password.
# Necessary for CI/CD automation and ease of use in a key-only environment.
echo "🔑 Granting sudo privileges to '$USER_NAME'..."
usermod -aG sudo "$USER_NAME"
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"

# 6. Harden SSH Configuration
# We disable password authentication entirely to block brute-force attacks.
# We also set 'prohibit-password' for root to allow key-based root login as a backup.
echo "🛡️ Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Update sshd_config settings using 'sed'
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
 
# Set SSH Timeouts: Automatically disconnect idle sessions after 5 minutes.
sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config

# Ensure the custom SSH Port is explicitly defined.
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# 7. Install Docker Engine
# Following official Docker installation steps for Debian-based systems.
echo "🐳 Installing Docker Engine..."
# Remove any conflicting legacy packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    apt-get remove -y $pkg || true
done

# Setup Docker APT repository using keyrings
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Global Docker Log Rotation
# This prevents Docker containers from filling up your disk with massive log files.
echo "📜 Configuring Docker Log Rotation (10MB max per container)..."
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker

# Add our service user to the 'docker' group to allow running docker without 'sudo'.
groupadd -f docker
usermod -aG docker "$USER_NAME"

# 8. Configure Firewall (UFW)
# We allow SSH first to prevent accidental lockout, then set default 'deny' for all other traffic.
echo "🛡️ Configuring Firewall..."
ufw allow ssh || true
ufw allow $SSH_PORT/tcp
ufw allow 80/tcp # HTTP
ufw allow 443/tcp # HTTPS

ufw default deny incoming
ufw default allow outgoing

echo "🚀 Enabling Firewall..."
ufw --force enable

# 9. Restart Services to apply changes
echo "🔄 Restarting SSH Service..."
systemctl restart ssh

# 10. Infrastructure Configuration (Swap & Timezone)
echo "🌐 Configuring Timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE" || echo "⚠️ Could not set timezone (Check if this is a container)."

if [ -n "$SWAP_SIZE" ] && [ "$SWAP_SIZE" != "0" ]; then
    if [ -f /swapfile ]; then
        echo "⚠️ Swapfile already exists. Skipping creation."
    else
        echo "💾 Creating ${SWAP_SIZE} Swap File for stability..."
        fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$(echo $SWAP_SIZE | sed 's/G//' | awk '{print $1 * 1024}')
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile || echo "⚠️ Could not activate swap (Check if this is a container)."
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        # Optimize swappiness (10 is good for servers)
        sysctl vm.swappiness=10
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
        echo "✅ Swap file created and activated."
    fi
fi

# 11. Security Extras (Optional)
# This includes Fail2Ban for auto-banning and Unattended-Upgrades for security patches.
if [ "$ENABLE_SECURITY_EXTRAS" = true ]; then
    echo "🛡️ Setting up Fail2Ban & Automated Security Updates..."
    apt-get install -y fail2ban unattended-upgrades
    
    # Configure Fail2Ban to monitor SSH and ban aggressive IPs for 1 hour.
    cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
bantime = 1h
EOF
    systemctl restart fail2ban
    
    # Configure Unattended Upgrades to automatically install security patches daily.
    echo 'Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };' > /etc/apt/apt.conf.d/50unattended-upgrades
    echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
    
    # Kernel Hardening: Protecting the network stack via sysctl tweaks.
    # Includes protections against Smurf attacks, IP spoofing, and SYN floods.
    echo "🧠 Hardening Network Kernel Parameters..."
    cat <<EOF > /etc/sysctl.d/99-security-hardening.conf
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
# Disabling IPv6 unless explicitly needed to reduce attack surface.
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    sysctl -p /etc/sysctl.d/99-security-hardening.conf || true

    # Login Banner: Displays a legal warning before/during login.
    echo "📜 Setting up Legal Login Banner..."
    echo "*****************************************************************" >> /etc/issue.net
    echo "WARNING: AUTHORIZED USE ONLY. Unauthorized access is prohibited." >> /etc/issue.net
    echo "All activities on this system are monitored and recorded." >> /etc/issue.net
    echo "*****************************************************************" >> /etc/issue.net
    sed -i "s|#Banner none|Banner /etc/issue.net|" /etc/ssh/sshd_config
    
    echo "✅ Security extras configured."
fi

echo "🏁 Setup Complete!"
echo "--------------------------------------------------"
echo "User: $USER_NAME"
echo "SSH Port: $SSH_PORT"
echo "Timezone: $TIMEZONE"
echo "Swap: $SWAP_SIZE"
echo "Auth: SSH Key Only (Password Disabled)"
echo "Docker: Installed & configured for '$USER_NAME'"
echo "--------------------------------------------------"
if [ -f /var/run/reboot-required ]; then
    echo "🚨 IMPORTANT: A system reboot is REQUIRED to apply security updates."
    echo "    Run: sudo reboot"
    echo "--------------------------------------------------"
fi
echo "⚠️  IMPORTANT: DO NOT CLOSE THIS SESSION until you verify"
echo "access in a new terminal with your SSH key:"
echo "    ssh $USER_NAME@YOUR_IP -p $SSH_PORT"
echo "--------------------------------------------------"
