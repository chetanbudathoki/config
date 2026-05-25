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

# --- CONFIGURATION ---
# The script loads credentials and settings from 'config.yml'.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -f "$SCRIPT_DIR/config.yml" ]; then
    CONFIG_FILE="$SCRIPT_DIR/config.yml"
    echo "📖 Found config.yml. Loading configurations..."
else
    echo "❌ ERROR: config.yml was not found!"
    echo "Please create 'config.yml' in the same directory."
    exit 1
fi

# Helper function to read simple YAML key-value pairs
get_yaml_value() {
    local key="$1"
    local default_val="$2"
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(grep -E "^${key}:" "$CONFIG_FILE" | sed -E "s/^${key}:[[:space:]]*//; s/^[\"']//; s/[\"']$//")
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi
    echo "$default_val"
}

# Load required settings
USER_NAME=$(get_yaml_value "username")
SSH_PUBLIC_KEYS=$(get_yaml_value "ssh_public_key")

if [ -z "$USER_NAME" ] || [ -z "$SSH_PUBLIC_KEYS" ]; then
    echo "❌ ERROR: 'username' and 'ssh_public_key' must be specified in the configuration file!"
    exit 1
fi

# Prevent running with template placeholders
if [ "$USER_NAME" = "your_username" ] || [ "$USER_NAME" = "username" ] || \
   [[ "$SSH_PUBLIC_KEYS" == *"user@example.com"* ]] || [[ "$SSH_PUBLIC_KEYS" == *"AAAA..."* ]]; then
    echo "⚠️  WARNING: Detected example template credentials from configuration."
    echo "Please update 'config.yml' with your actual username and SSH key before running."
    echo "Exiting for safety."
    exit 1
fi

# Load optional settings (with safe defaults)
SSH_PORT=$(get_yaml_value "ssh_port" "22")
SYNC_KEYS_TO_ROOT=$(get_yaml_value "sync_keys_to_root" "true")
ENABLE_SECURITY_EXTRAS=$(get_yaml_value "enable_security_extras" "true")
SWAP_SIZE=$(get_yaml_value "swap_size" "2G")
TIMEZONE=$(get_yaml_value "timezone" "UTC")

echo "✅ Configuration successfully loaded from $(basename "$CONFIG_FILE")."
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
    chmod 700 "/home/$USER_NAME" # Tight home directory privacy
    echo "✅ User '$USER_NAME' created with locked password and private home directory (SSH Key Only)."
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

# Failsafe: Remove cloud-init overrides in sshd_config.d to prevent password auth leaks
if [ -d /etc/ssh/sshd_config.d ]; then
    echo "🧹 Clearing sshd_config.d override snippets to prevent config leaks..."
    rm -f /etc/ssh/sshd_config.d/*.conf || true
fi

# Update sshd_config settings using 'sed'
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
 
# Set SSH Timeouts: Automatically disconnect idle sessions after 5 minutes.
sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config

# Tight SSH Hardening: Disable X11 Forwarding, limit retries, and block agent forwarding
sed -i 's/#X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config

if ! grep -q "^MaxAuthTries" /etc/ssh/sshd_config; then
    echo "MaxAuthTries 2" >> /etc/ssh/sshd_config
fi
if ! grep -q "^AllowAgentForwarding" /etc/ssh/sshd_config; then
    echo "AllowAgentForwarding no" >> /etc/ssh/sshd_config
fi

# Restrict SSH entry exclusively to authorized users
ALLOWED_USERS="$USER_NAME"
if [ "$SYNC_KEYS_TO_ROOT" = true ]; then
    ALLOWED_USERS="$USER_NAME root"
fi
sed -i '/^AllowUsers/d' /etc/ssh/sshd_config
echo "AllowUsers $ALLOWED_USERS" >> /etc/ssh/sshd_config

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
systemctl daemon-reload
systemctl enable docker || true
systemctl enable containerd || true
systemctl restart docker || true
systemctl restart containerd || true

# Add our service user to the 'docker' group to allow running docker without 'sudo'.
groupadd -f docker
usermod -aG docker "$USER_NAME"

# 8. Configure Firewall (UFW)
# We allow SSH first to prevent accidental lockout, then set default 'deny' for all other traffic.
echo "🛡️ Configuring Firewall (with SSH rate-limiting)..."
ufw limit ssh/tcp || true
ufw limit $SSH_PORT/tcp
ufw allow 80/tcp # HTTP
ufw allow 443/tcp # HTTPS

ufw default deny incoming
ufw default allow outgoing

echo "🚀 Enabling Firewall..."
ufw --force enable

# 9. Restart Services to apply changes
echo "🔄 Restarting SSH Service..."
systemctl restart ssh

# 10. Infrastructure & Performance Optimization (Swap, Timezone, Limits)
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

# Performance Optimization: Increase Virtual Memory Mapping Limits (Database Optimization)
echo "🧠 Optimizing Virtual Memory limits for production databases..."
sysctl vm.max_map_count=262144 || true
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl vm.vfs_cache_pressure=50 || true
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

# Performance Optimization: Increase System Open File limits (nofile) to prevent container locks
echo "📜 Optimizing system file limits (nofile)..."
cat <<EOF >> /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

# Ensure systemd service configurations inherit file limit optimizations
mkdir -p /etc/systemd/system/docker.service.d
cat <<EOF > /etc/systemd/system/docker.service.d/limits.conf
[Service]
LimitNOFILE=65535
EOF
systemctl daemon-reload || true
echo "✅ Infrastructure and performance parameters optimized."

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
    
    # Configure Unattended Upgrades to automatically install security and package patches daily,
    # clean up unused dependencies, and auto-reboot at 03:00 AM if required by updates.
    cat <<'EOF' > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
    "${distro_id}:${distro_codename}";
    "origin=Docker,archive=stable";
};

// Automatically reboot the system if a reboot is needed
Unattended-Upgrade::Automatic-Reboot "true";

// Reboot at a specific safe time (e.g. 3:00 AM)
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Clean up unused dependencies after upgrading
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Do not install on shutdown, install immediately
Unattended-Upgrade::InstallOnShutdown "false";
EOF

    # Configure periodic upgrades (Weekly check, upgrade, and cache clean every 7 days)
    cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "7";
APT::Periodic::Download-Upgradeable-Packages "7";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "7";
EOF
    
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
    
    # Secure shared memory and temp directories (noexec, nosuid, nodev)
    echo "🔒 Securing /tmp and /dev/shm with secure mount options..."
    if ! grep -q "tmpfs /tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    fi
    chmod 1777 /tmp /var/tmp /dev/shm || true

    # Disable compiler execution for unprivileged/non-root users to block local exploit compilation
    echo "🛡️ Locking down compiler executables..."
    COMPILERS=(
        /usr/bin/as
        /usr/bin/byacc
        /usr/bin/yacc
        /usr/bin/bcc
        /usr/bin/kgcc
        /usr/bin/cc
        /usr/bin/gcc
        /usr/bin/g++
        /usr/bin/make
        /usr/bin/clang
    )
    for compiler in "${COMPILERS[@]}"; do
        if [ -f "$compiler" ]; then
            chmod 700 "$compiler" || true
        fi
    done

    # Disable unused legacy network protocols at the kernel level
    echo "🧠 Hardening kernel modules (disabling sctp, dccp, rds, tipc)..."
    cat <<EOF > /etc/modprobe.d/security-hardening.conf
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF

    echo "✅ Security extras configured."
fi

# 12. Slim down the OS (Remove non-essential packages & services)
# Since this is a dedicated Docker host, we remove unnecessary native services 
# (like mail transfer agents, printing, and snapd) to free up memory and minimize attack surface.
echo "🧹 Slimming down the OS and removing non-essential packages..."

UNNECESSARY_PACKAGES=(
    exim4
    exim4-base
    exim4-config
    rpcbind
    avahi-daemon
    cups
    cups-daemon
    snapd
    cron
)

# Make sure cron is installed and active for our scheduled tasks
if ! dpkg -l | grep -q "^ii  cron "; then
    echo "🕒 Installing cron for scheduled cleanups..."
    apt-get install -y cron || true
fi
systemctl enable cron || true
systemctl start cron || true

for pkg in "${UNNECESSARY_PACKAGES[@]}"; do
    # Do not purge cron since we need it for our cron jobs
    if [ "$pkg" = "cron" ]; then continue; fi
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "🗑️ Removing package and configuration: $pkg..."
        apt-get purge -y "$pkg" || true
    fi
done

# Clean up snap directories if snapd was removed
if [ ! -d /snap ]; then
    rm -rf /snap /var/snap /var/lib/snapd || true
fi

# Autoremove and clean package cache with purge to free disk space
apt-get autoremove --purge -y
apt-get clean -y

# System log optimization: Cap systemd-journald logs to 100M max to prevent disk saturation
echo "🧹 Limiting system log (Journald) size to 100M max..."
sed -i 's/#SystemMaxUse=/SystemMaxUse=100M/' /etc/systemd/journald.conf
sed -i 's/SystemMaxUse=.*/SystemMaxUse=100M/' /etc/systemd/journald.conf
systemctl restart systemd-journald || true

echo "✅ OS slimmed down successfully."

# 13. Schedule Weekly Docker Cleanup & Self-Cleaning Firewall (Cron Jobs)
# To prevent old, cached, and dangling Docker images from filling up your VPS SSD,
# and to clean up allowed ports that are no longer bound to any active containers:
echo "🕒 Creating self-cleaning firewall utility (/usr/local/bin/ufw-cleanup.sh)..."

cat <<EOF > /usr/local/bin/ufw-cleanup.sh
#!/bin/bash
# /usr/local/bin/ufw-cleanup.sh
# Automatically purges UFW rules for ports that have no active listening process/Docker container.

# Whitelist: Critical ports that should NEVER be closed automatically
WHITELIST=("22" "$SSH_PORT" "80" "443")

echo "🔍 Starting weekly UFW firewall port audit..."

# Get all allowed ports from UFW
UFW_PORTS=\$(ufw status | grep -E 'ALLOW|LIMIT|ALLOW IN|LIMIT IN' | awk '{print \$1}' | grep -oE '^[0-9]+' | sort -u)

# Get all currently active listening ports on the host
ACTIVE_PORTS=\$(ss -tulpn | awk '{print \$5}' | grep -oE ':[0-9]+$' | cut -d: -f2 | sort -u)

for port in \$UFW_PORTS; do
    # Check if port is whitelisted
    is_whitelisted=false
    for white in "\${WHITELIST[@]}"; do
        if [ "\$port" = "\$white" ]; then
            is_whitelisted=true
            break
        fi
    done
    
    if [ "\$is_whitelisted" = true ]; then
        continue
    fi
    
    # Check if port is active
    is_active=false
    for active in \$ACTIVE_PORTS; do
        if [ "\$port" = "\$active" ]; then
            is_active=true
            break
        fi
    done
    
    if [ "\$is_active" = false ]; then
        echo "🗑️ Port \$port is allowed in UFW but has no active listening service. Closing port..."
        ufw delete allow "\$port" || true
        ufw delete allow "\$port/tcp" || true
        ufw delete allow "\$port/udp" || true
        ufw delete limit "\$port" || true
        ufw delete limit "\$port/tcp" || true
        ufw delete limit "\$port/udp" || true
    fi
done

# Reload firewall to apply cleanups
ufw reload
echo "✅ Firewall audit complete."
EOF

chmod +x /usr/local/bin/ufw-cleanup.sh
echo "✅ Self-cleaning firewall utility configured."

echo "🕒 Scheduling weekly cron jobs (Docker cleanup & Firewall audit)..."
(
  crontab -l 2>/dev/null | grep -v -E "docker system prune|docker image prune|ufw-cleanup.sh" || true
  echo "0 3 * * 0 docker system prune -af >/dev/null 2>&1"
  echo "0 4 * * 0 /usr/local/bin/ufw-cleanup.sh >/dev/null 2>&1"
) | crontab -
echo "✅ Scheduled maintenance tasks successfully configured."

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
