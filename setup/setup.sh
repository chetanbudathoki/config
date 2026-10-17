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
# This script is designed to transform a fresh Debian VPS into a 
# hardened, production-ready environment with Docker and a dedicated user.

set -e # Exit immediately if a command exits with a non-zero status.

echo "🚀 Starting Complete VPS Bootstrap..."

# --- CONFIGURATION ---
# The script loads credentials and settings from 'config.yml'.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -f "$SCRIPT_DIR/config.yml" ]; then
    CONFIG_FILE="$SCRIPT_DIR/config.yml"
elif [ -f "$SCRIPT_DIR/../config.yml" ]; then
    CONFIG_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/config.yml"
else
    echo "❌ ERROR: config.yml was not found!"
    echo "Please ensure 'config.yml' exists in '$SCRIPT_DIR' or the repository root."
    exit 1
fi
echo "📖 Found $(basename "$CONFIG_FILE") at '$CONFIG_FILE'. Loading configurations..."

# Helper function to read simple and nested YAML key-value pairs (e.g. "nginx.ports.admin")
get_yaml_value() {
    local key="$1"
    local default_val="${2:-}"
    if [ -f "$CONFIG_FILE" ]; then
        local val=""
        # Python-based parser if python3 is available
        if command -v python3 &>/dev/null; then
            val=$(python3 -c "
import sys
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        d = yaml.safe_load(f) or {}
    keys = '$key'.split('.')
    for k in keys:
        if isinstance(d, dict):
            d = d.get(k)
        else:
            d = None
            break
    if d is not None:
        print(d)
except Exception:
    pass
" 2>/dev/null)
        fi

        # AWK fallback if Python or PyYAML is not installed
        if [ -z "$val" ]; then
            val=$(awk -v target_path="$key" '
            BEGIN {
                split(target_path, parts, ".")
                target_depth = length(parts)
            }
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            {
                # Remove comments
                sub(/#.*$/, "")
                # Find indentation level (2 spaces per level standard)
                match($0, /^[[:space:]]*/)
                indent = RLENGTH
                depth = int(indent / 2) + 1
                
                # Extract key and value
                line = $0
                sub(/^[[:space:]]*/, "", line)
                if (line ~ /:/) {
                    split(line, kv, ":")
                    k = kv[1]
                    sub(/[[:space:]]+$/, "", k)
                    
                    # Store current path key at this depth
                    current_path[depth] = k
                    
                    # Check if depth matches target
                    if (depth == target_depth) {
                        match_path = 1
                        for (i = 1; i <= target_depth; i++) {
                            if (current_path[i] != parts[i]) {
                                match_path = 0
                                break
                            }
                        }
                        if (match_path) {
                            # Extract value part after first colon
                            sub(/^[^:]*:[[:space:]]*/, "", line)
                            sub(/[[:space:]]+$/, "", line)
                            print line
                            exit
                        }
                    }
                }
            }' "$CONFIG_FILE" 2>/dev/null)
        fi

        val=$(echo "$val" | tr -d '"' | tr -d "'" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi
    echo "$default_val"
}

get_ssh_keys() {
    if [ -f "$CONFIG_FILE" ]; then
        # Check if multiline block indicator (| or >) is used
        if grep -E "^ssh_public_key:[[:space:]]*[\|>]" "$CONFIG_FILE" >/dev/null 2>&1; then
            sed -n '/^ssh_public_key:[[:space:]]*[\|>]/,/^[^[:space:]#]/p' "$CONFIG_FILE" 2>/dev/null | \
                grep -E '^[[:space:]]+ssh-(ed25519|rsa|dss|ecdsa)' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
            return 0
        fi
        # Standard single line
        local key_line
        key_line=$(grep -E "^ssh_public_key:" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d'#' -f1 | cut -d':' -f2- | tr -d '"' | tr -d "'" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$key_line" ]; then
            echo "$key_line"
            return 0
        fi
    fi
}

# Load required settings
USER_NAME=$(get_yaml_value "username")
SSH_PUBLIC_KEYS=$(get_ssh_keys)

if [ -z "$USER_NAME" ] || [ -z "$SSH_PUBLIC_KEYS" ]; then
    echo "❌ ERROR: 'username' and at least 1 valid 'ssh_public_key' must be specified in the configuration file!"
    exit 1
fi

# Prevent running with template placeholders
if [ "$USER_NAME" = "your_username" ] || [ "$USER_NAME" = "username" ] || \
   [[ "$SSH_PUBLIC_KEYS" == *"user@example.com"* ]] || [[ "$SSH_PUBLIC_KEYS" == *"user1@example.com"* ]] || [[ "$SSH_PUBLIC_KEYS" == *"AAAA..."* ]]; then
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
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" \
    sudo curl git gnupg ca-certificates openssh-server ufw bash-completion jq rsync tar unzip htop

# 2. Setup or Update the User (Passwordless/SSH-Only)
# Check if the script is run directly or via sudo by the target user
INVOKING_USER="${SUDO_USER:-$(id -un)}"

if [ "$INVOKING_USER" != "root" ] && [ "$INVOKING_USER" = "$USER_NAME" ]; then
    echo "👤 Script is executed by user '$INVOKING_USER' matching config username."
    echo "🔄 Updating details for current user '$USER_NAME'..."
    passwd -l "$USER_NAME" || true
    chmod 700 "/home/$USER_NAME" 2>/dev/null || true
    echo "✅ Current user '$USER_NAME' details updated."
elif id "$USER_NAME" &>/dev/null; then
    echo "⚠️ User '$USER_NAME' already exists. Skipping creation and updating details."
    passwd -l "$USER_NAME" || true
    chmod 700 "/home/$USER_NAME" 2>/dev/null || true
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
HOME_DIR=$(eval echo "~$USER_NAME")
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

# SSH OOM & Process Priority Protection: Guarantee SSH access during extreme memory/CPU starvation
# Prevents the kernel OOM killer from killing sshd and gives sshd priority over runaway containers
echo "🛡️ Configuring SSH process immunity against OOM-killer..."
mkdir -p /etc/systemd/system/ssh.service.d /etc/systemd/system/sshd.service.d
cat <<'EOF' > /etc/systemd/system/ssh.service.d/override.conf
[Service]
OOMScoreAdjust=-1000
CPUSchedulingPolicy=rr
CPUSchedulingPriority=50
MemoryMin=32M
EOF
cp /etc/systemd/system/ssh.service.d/override.conf /etc/systemd/system/sshd.service.d/override.conf 2>/dev/null || true
systemctl daemon-reload || true

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

# Check operating system (Debian required)
if [ ! -f /etc/debian_version ] || grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    echo "❌ ERROR: This script is exclusively built for Debian Linux."
    echo "Detected non-Debian distribution. Aborting."
    exit 1
fi

DEBIAN_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
if [ -z "$DEBIAN_CODENAME" ]; then
    DEBIAN_CODENAME="bookworm"
fi

# Setup official Docker APT repository for Debian
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $DEBIAN_CODENAME stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Global Docker Log Rotation, DNS & Networking
# This prevents Docker containers from filling up disk and avoids DNS/MTU timeouts on cloud VPS.
echo "📜 Configuring Docker Daemon (10MB log rotation & reliable DNS)..."
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["1.1.1.1", "8.8.8.8"]
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

# 8. Setup Dedicated Workspace & Project Directory
# Creating /home/$USER_NAME/project as the primary flexible workspace.
# GitHub Actions / CI/CD scripts can freely create subdirectories, deploy docker-compose
# setups, clone repositories, and build artifacts inside without root or sudo prompts.
PROJECT_DIR="/home/$USER_NAME/project"
echo "📁 Configuring flexible project directory at '$PROJECT_DIR'..."
mkdir -p "$PROJECT_DIR"
chown -R "$USER_NAME:docker" "$PROJECT_DIR"
# 2775: Group SetGID (g+s) ensures all newly created files & folders inherit 'docker' group
chmod 2775 "$PROJECT_DIR"

# Symlinks for convenience & backwards compatibility:
# /opt/project -> /home/$USER_NAME/project
# /home/$USER_NAME/projects -> /home/$USER_NAME/project (backward compatibility)
# /opt/projects -> /home/$USER_NAME/project (backward compatibility)
ln -sfn "$PROJECT_DIR" "/opt/project" || true
ln -sfn "$PROJECT_DIR" "/home/$USER_NAME/projects" || true
ln -sfn "$PROJECT_DIR" "/opt/projects" || true
echo "✅ Project workspace created at '$PROJECT_DIR' (with /opt/project and backward-compatible 'projects' aliases)."

# 9. Configure Firewall (UFW) & Secure Docker Port Exposure
# We allow SSH first to prevent accidental lockout, then set default 'deny' for all other traffic.
echo "🛡️ Configuring Firewall (with SSH rate-limiting)..."
ufw limit ssh/tcp || true
ufw limit $SSH_PORT/tcp

ufw default deny incoming
ufw default allow outgoing

# Docker UFW Integration: Prevent Docker from bypassing UFW via raw iptables rules
# Configures /etc/ufw/after.rules so published container ports are governed by UFW rules.
if [ -f /etc/ufw/after.rules ] && ! grep -q "DOCKER-USER" /etc/ufw/after.rules; then
    echo "🛡️ Securing Docker iptables routing against UFW bypass..."
    cat <<'EOF' >> /etc/ufw/after.rules

# BEGIN DOCKER-UFW PROTECTION
*filter
:DOCKER-USER - [0:0]
:ufw-user-input - [0:0]

-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
-A DOCKER-USER -i lo -j ACCEPT
-A DOCKER-USER -o lo -j ACCEPT
-A DOCKER-USER -j RETURN
COMMIT
# END DOCKER-UFW PROTECTION
EOF
fi

echo "🚀 Enabling Firewall..."
ufw --force enable

# 10. Restart Services safely
echo "🔍 Validating SSH Configuration..."
if sshd -t; then
    echo "🔄 Restarting SSH Service..."
    systemctl restart ssh || systemctl restart sshd || true
else
    echo "⚠️ Warning: sshd -t test reported configuration syntax errors. Skipping SSH restart to prevent lockout."
fi

# 11. Infrastructure & Performance Optimization (Swap, Timezone, NTP, Limits)
echo "🌐 Configuring Timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE" || echo "⚠️ Could not set timezone (Check if this is a container)."

# Configure & Enforce NTP Time Synchronization (systemd-timesyncd)
# Eliminates clock drift that breaks Let's Encrypt SSL issuance & Cloudflare R2 / AWS S3 HMAC signatures
echo "🕒 Configuring resilient NTP Time Synchronization via systemd-timesyncd..."
if ! dpkg -l | grep -q "^ii  systemd-timesyncd "; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" systemd-timesyncd >/dev/null 2>&1 || true
fi

mkdir -p /etc/systemd/timesyncd.conf.d
cat <<'EOF' > /etc/systemd/timesyncd.conf.d/00-resilient-ntp.conf
[Time]
NTP=time.cloudflare.com time.google.com 0.debian.pool.ntp.org 1.debian.pool.ntp.org
FallbackNTP=2.debian.pool.ntp.org 3.debian.pool.ntp.org pool.ntp.org
PollIntervalMinSec=32
PollIntervalMaxSec=1024
EOF

systemctl enable systemd-timesyncd 2>/dev/null || true
systemctl restart systemd-timesyncd 2>/dev/null || true
timedatectl set-ntp true 2>/dev/null || true
echo "✅ NTP Time Synchronization active."

if [ -n "$SWAP_SIZE" ] && [ "$SWAP_SIZE" != "0" ]; then
    # Auto-calibrate Swap: calculate server physical RAM in MB
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    REQUESTED_MB=$(echo "$SWAP_SIZE" | sed 's/[Gg]//' | awk '{print $1 * 1024}')
    
    # Ensure swap is at least equal to physical RAM or requested size (min 4096MB)
    ALLOC_SWAP_MB=$REQUESTED_MB
    if [ -n "$TOTAL_RAM_MB" ] && [ "$TOTAL_RAM_MB" -gt "$ALLOC_SWAP_MB" ]; then
        ALLOC_SWAP_MB=$TOTAL_RAM_MB
    fi
    if [ "$ALLOC_SWAP_MB" -lt 4096 ]; then
        ALLOC_SWAP_MB=4096
    fi

    # Check if swap exists but is dangerously small (< 2GB) like the 1GB cloud default
    EXISTING_SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
    if [ -f /swapfile ] && [ -n "$EXISTING_SWAP_MB" ] && [ "$EXISTING_SWAP_MB" -lt 2048 ]; then
        echo "⚠️ Existing swap is dangerously small (${EXISTING_SWAP_MB}MB). Recreating with ${ALLOC_SWAP_MB}MB for OOM safety..."
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
    fi

    if [ -f /swapfile ]; then
        echo "ℹ️ Adequate Swapfile already exists (${EXISTING_SWAP_MB}MB). Skipping creation."
    else
        echo "💾 Creating ${ALLOC_SWAP_MB}MB Swap File for stability and OOM-deadlock prevention..."
        fallocate -l "${ALLOC_SWAP_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$ALLOC_SWAP_MB"
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile || echo "⚠️ Could not activate swap (Check if this is a container)."
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        echo "✅ Swap file created and activated (${ALLOC_SWAP_MB}MB)."
    fi

    # Optimize swappiness (10 is ideal: keeps active RAM fast, uses swap as safe spillover before OOM)
    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

# Performance Optimization: Increase Virtual Memory Mapping Limits (Database Optimization)
echo "🧠 Optimizing Virtual Memory & RAM protection parameters..."
sysctl vm.max_map_count=262144 || true
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl vm.vfs_cache_pressure=50 || true
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

# Throttled Dirty Page Ratios: Prevents heavy disk writes from locking CPU and I/O bus
sysctl vm.dirty_background_ratio=5 || true
echo "vm.dirty_background_ratio=5" >> /etc/sysctl.conf
sysctl vm.dirty_ratio=10 || true
echo "vm.dirty_ratio=10" >> /etc/sysctl.conf

# Reserved Kernel Memory (Prevents Total System Freezes & OOM SSH Lockouts)
# Reserves 128MB of physical RAM strictly for kernel operations, interrupt handlers & SSH fork calls
sysctl vm.min_free_kbytes=131072 || true
echo "vm.min_free_kbytes=131072" >> /etc/sysctl.conf

# Avoid complete kernel panic lockup on memory exhaustion
sysctl vm.panic_on_oom=0 || true
echo "vm.panic_on_oom=0" >> /etc/sysctl.conf
sysctl vm.oom_kill_allocating_task=1 || true
echo "vm.oom_kill_allocating_task=1" >> /etc/sysctl.conf

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
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" fail2ban unattended-upgrades
    
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

    # Prevent /tmp noexec from breaking apt-get, dpkg, and CI/CD temp script executions
    mkdir -p /var/tmp/apt
    chmod 1777 /var/tmp/apt
    echo 'APT::ExtractTemplates::TempDir "/var/tmp/apt";' > /etc/apt/apt.conf.d/50tempdir

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

# 12. Delegate System Cleanup & Automated Maintenance to clean/clean.sh
CLEAN_SCRIPT="$SCRIPT_DIR/../clean/clean.sh"
if [ ! -f "$CLEAN_SCRIPT" ]; then
    CLEAN_SCRIPT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)/clean/clean.sh"
fi

if [ -f "$CLEAN_SCRIPT" ]; then
    echo "🧹 Invoking dedicated cleanup & maintenance module (clean/clean.sh)..."
    chmod +x "$CLEAN_SCRIPT"
    "$CLEAN_SCRIPT"
else
    echo "⚠️ Warning: clean/clean.sh not found. Skipping OS debloat and maintenance setup."
fi

# 14. Deploy CI/CD Post-Deployment Health Check Utility
# Standardized tool inside ~/project that GitHub Actions / CI/CD can run to confirm deployment success
cat <<'EOF' > "/home/$USER_NAME/project/healthcheck.sh"
#!/bin/bash
# =====================================================================
# 🩺 CI/CD Post-Deployment Container & Endpoint Health Check
# Usage: ./healthcheck.sh [CONTAINER_NAME_OR_URL] [TIMEOUT_SECONDS]
# =====================================================================
TARGET="${1:-}"
TIMEOUT="${2:-30}"
INTERVAL=2
ELAPSED=0

if [ -z "$TARGET" ]; then
    echo "Usage: $0 <container_name | http://url> [timeout_seconds]"
    exit 1
fi

echo "🔍 Checking health of '$TARGET' (timeout: ${TIMEOUT}s)..."

if [[ "$TARGET" =~ ^https?:// ]]; then
    while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET" || echo "000")
        if [[ "$STATUS" =~ ^(200|201|204|301|302)$ ]]; then
            echo "✅ Target '$TARGET' is healthy! HTTP Status: $STATUS."
            exit 0
        fi
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        echo "⏳ Waiting for HTTP response... (${ELAPSED}s / ${TIMEOUT}s, status: $STATUS)"
    done
    echo "❌ Health check failed for URL '$TARGET' after ${TIMEOUT}s."
    exit 1
else
    while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
        if docker ps --filter "name=^/${TARGET}$" --filter "status=running" --format '{{.Names}}' | grep -q "^${TARGET}$"; then
            echo "✅ Container '$TARGET' is running and healthy!"
            exit 0
        fi
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        echo "⏳ Waiting for container '$TARGET' to start... (${ELAPSED}s / ${TIMEOUT}s)"
    done
    echo "❌ Container '$TARGET' failed to start or crashed within ${TIMEOUT}s."
    exit 1
fi
EOF

chown "$USER_NAME:docker" "/home/$USER_NAME/project/healthcheck.sh"
chmod 775 "/home/$USER_NAME/project/healthcheck.sh"
echo "✅ CI/CD health check utility installed at '/home/$USER_NAME/project/healthcheck.sh'."

echo "🏁 Base System Setup Complete!"
echo "--------------------------------------------------"
echo "User: $USER_NAME"
echo "Workspace: /home/$USER_NAME/project (/opt/project)"
echo "SSH Port: $SSH_PORT"
echo "Timezone: $TIMEZONE"
echo "Swap: $SWAP_SIZE"
echo "Auth: SSH Key Only (Password Disabled)"
echo "Docker: Installed & configured for '$USER_NAME'"
echo "--------------------------------------------------"
echo "💡 TIP: To deploy Nginx Proxy Manager & automated Cloudflare backups,"
echo "   run the dedicated installer:"
echo "   sudo ./nginx/nginx.sh"
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
