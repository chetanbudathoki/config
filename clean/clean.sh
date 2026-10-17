#!/bin/bash

# =====================================================================
# 🧹 clean.sh: Minimal Debian OS Debloater & Memory/Disk Reclamation
# =====================================================================
# Usage:
#   chmod +x clean/clean.sh
#   sudo ./clean/clean.sh
#
# Strips standard Debian cloud/VPS images down to a lean, dedicated Docker host:
#   1. Purges unnecessary daemons (rpcbind, avahi, cups, exim4, modemmanager, nfs).
#   2. Caps systemd-journald logs to 50MB max with 7-day retention.
#   3. Evicts stale package caches, old kernels, and orphaned libraries.
#   4. Empties stale /tmp and rotated log files older than 7 days.
#   5. Flushes inactive filesystem buffers.
# =====================================================================

set -euo pipefail

echo "🧹 Starting Debian OS Debloat & System Cleanup..."

# Root check
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run directly as root (e.g., sudo ./clean/clean.sh)."
    exit 1
fi

# Ensure running on Debian
if [ ! -f /etc/debian_version ]; then
    echo "❌ ERROR: This cleanup script is specifically tailored for Debian Linux."
    exit 1
fi

# 1. Purge Bloated & Non-Essential Background Services
echo "🗑️ Purging non-essential Debian background daemons..."

# Ensure cron is installed and active for automated scheduled hygiene
if ! dpkg -l | grep -q "^ii  cron "; then
    echo "🕒 Installing cron for scheduled cleanups..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" cron >/dev/null 2>&1 || true
fi
systemctl enable cron 2>/dev/null || true
systemctl start cron 2>/dev/null || true

UNNECESSARY_SERVICES=(
    cups
    cups-daemon
    cups-browsed
    avahi-daemon
    rpcbind
    exim4
    exim4-base
    exim4-config
    modemmanager
    multipath-tools
    bluez
    snapd
)

for pkg in "${UNNECESSARY_SERVICES[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "   - Purging $pkg..."
        systemctl stop "$pkg" 2>/dev/null || true
        systemctl disable "$pkg" 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg" >/dev/null 2>&1 || true
    fi
done

# Clean up snap directories if snap was removed
if [ ! -d /snap ]; then
    rm -rf /snap /var/snap /var/lib/snapd 2>/dev/null || true
fi

# 2. Cap systemd-journald Log Storage to 50MB Max & 7-Day Retention
echo "📜 Capping system journal logs to 50MB max with 7-day retention..."
mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF' > /etc/systemd/journald.conf.d/00-journal-size.conf
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=25M
SystemMaxFileSize=10M
MaxRetentionSec=7day
EOF
systemctl restart systemd-journald 2>/dev/null || true
journalctl --vacuum-time=7d --vacuum-size=50M >/dev/null 2>&1 || true
echo "✅ Journal logs trimmed."

# 3. Configure Global Log Retention (daily rotate, max 7 days)
echo "📜 Hardening logrotate configuration for /var/log..."
cat <<'EOF' > /etc/logrotate.d/00-global-retention
/var/log/syslog
/var/log/mail.log
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/daemon.log
/var/log/auth.log
/var/log/user.log
/var/log/messages
/var/log/debug
/var/log/kern.log
{
    daily
    rotate 7
    maxsize 15M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate 2>/dev/null || true
    endscript
}
EOF
sed -i 's/^rotate .*/rotate 7/' /etc/logrotate.conf 2>/dev/null || true
sed -i 's/#compress/compress/' /etc/logrotate.conf 2>/dev/null || true

# Systemd tmpfiles: Auto-clean /tmp and /var/tmp files
echo "d /tmp 1777 root root 3d" > /etc/tmpfiles.d/tmp-cleanup.conf
echo "d /var/tmp 1777 root root 7d" >> /etc/tmpfiles.d/tmp-cleanup.conf

# 4. Clean APT Cache & Remove Orphaned Dependencies
echo "🧹 Cleaning apt cache and removing orphaned packages..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y >/dev/null 2>&1 || true
apt-get clean -y >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/*
apt-get update -y >/dev/null 2>&1 || true

# 5. Clean Stale Temporary Files & Old Compressed Logs
echo "🧹 Cleaning stale /tmp and rotated log files..."
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
find /var/log -type f -regex '.*\.[0-9]+\.gz$' -delete 2>/dev/null || true
find /var/log -type f -regex '.*\.[0-9]+$' -delete 2>/dev/null || true

# 6. Install Daily Disk & Log Hygiene Utility (/usr/local/bin/disk-cleanup.sh)
echo "💾 Installing daily disk hygiene utility..."
cat <<'EOF' > /usr/local/bin/disk-cleanup.sh
#!/bin/bash
# =====================================================================
# 🧹 VPS Disk & Log Hygiene Utility
# Automatically vacuums systemd journals, removes stale logs, cleans
# APT cache, and prunes old Docker buildkit caches.
# =====================================================================
set -euo pipefail

# 1. Vacuum systemd journal logs to max 50MB and max 7 days
if command -v journalctl &>/dev/null; then
    journalctl --vacuum-time=7d --vacuum-size=50M >/dev/null 2>&1 || true
fi

# 2. Clean APT package cache and lists archives
if command -v apt-get &>/dev/null; then
    apt-get clean -y >/dev/null 2>&1 || true
    apt-get autoclean -y >/dev/null 2>&1 || true
fi

# 3. Purge rotated logs older than 7 days and stale temp files
find /var/log -type f -regex '.*\.[0-9]+\.gz$' -mtime +7 -delete 2>/dev/null || true
find /var/log -type f -regex '.*\.[0-9]+$' -mtime +7 -delete 2>/dev/null || true
find /tmp /var/tmp -type f -atime +3 -delete 2>/dev/null || true

# 4. Trigger logrotate daily run to prevent runaway unrotated files
if command -v logrotate &>/dev/null; then
    logrotate /etc/logrotate.conf >/dev/null 2>&1 || true
fi

# 5. Prune dangling Docker builder caches older than 7 days
if command -v docker &>/dev/null && docker info &>/dev/null; then
    docker builder prune -f --filter "until=168h" --keep-storage 500MB >/dev/null 2>&1 || true
fi
EOF
chmod +x /usr/local/bin/disk-cleanup.sh

# 7. Install Proactive RAM, Swap & Cache Watchdog (/usr/local/bin/ram-cleanup.sh)
echo "🧠 Installing RAM & Swap watchdog utility..."
cat <<'EOF' > /usr/local/bin/ram-cleanup.sh
#!/bin/bash
# =====================================================================
# 🧠 VPS RAM & Swap Watchdog
# Monitors system memory and safely evicts pagecache/dentries/inodes
# or prunes BuildKit caches if memory pressure spikes dangerously.
# =====================================================================
set -euo pipefail

MEM_TOTAL=$(free | awk '/^Mem:/{print $2}')
MEM_AVAILABLE=$(free | awk '/^Mem:/{print $7}')

if [ -z "$MEM_TOTAL" ] || [ "$MEM_TOTAL" -eq 0 ] || [ -z "$MEM_AVAILABLE" ]; then
    exit 0
fi

MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

# Threshold 1: Elevated memory usage (>=85%) -> Safe kernel cache flush
if [ "$MEM_PERCENT" -ge 85 ]; then
    echo "⚠️ [$(date '+%Y-%m-%d %H:%M:%S')] High memory usage detected: ${MEM_PERCENT}%. Evicting filesystem caches..."
    sync
    echo 3 > /proc/sys/vm/drop_caches
fi

# Threshold 2: Critical memory pressure (>=92%) -> Evict caches + prune Docker builder caches
if [ "$MEM_PERCENT" -ge 92 ]; then
    echo "🚨 [$(date '+%Y-%m-%d %H:%M:%S')] Critical memory pressure: ${MEM_PERCENT}%. Running emergency Docker builder prune..."
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        docker builder prune -f --keep-storage 500MB >/dev/null 2>&1 || true
    fi
fi

# Threshold 3: Swap Exhaustion Watchdog (>=85% Swap Used) -> Stop kswapd CPU death spirals
SWAP_TOTAL=$(free | awk '/^Swap:/{print $2}')
SWAP_FREE=$(free | awk '/^Swap:/{print $4}')
if [ -n "$SWAP_TOTAL" ] && [ "$SWAP_TOTAL" -gt 0 ] && [ -n "$SWAP_FREE" ]; then
    SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
    SWAP_PERCENT=$((SWAP_USED * 100 / SWAP_TOTAL))
    if [ "$SWAP_PERCENT" -ge 85 ]; then
        echo "🚨 [$(date '+%Y-%m-%d %H:%M:%S')] Critical Swap usage detected: ${SWAP_PERCENT}%. Evicting memory to prevent thrashing..."
        sync
        echo 3 > /proc/sys/vm/drop_caches
        if command -v docker &>/dev/null && docker info &>/dev/null; then
            docker builder prune -f --keep-storage 200MB >/dev/null 2>&1 || true
        fi
    fi
fi

# Threshold 4: Emergency Disk Safeguard (>=90% Root Disk Used)
DISK_PERCENT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ -n "$DISK_PERCENT" ] && [ "$DISK_PERCENT" -ge 90 ]; then
    echo "🚨 [$(date '+%Y-%m-%d %H:%M:%S')] Critical disk usage detected: ${DISK_PERCENT}%. Running emergency Docker system prune..."
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        docker system prune -f >/dev/null 2>&1 || true
    fi
fi

# Routine: Prune dead/exited containers older than 48 hours
if command -v docker &>/dev/null && docker info &>/dev/null; then
    docker container prune --filter "until=48h" -f >/dev/null 2>&1 || true
fi
EOF
chmod +x /usr/local/bin/ram-cleanup.sh

# 8. Install Self-Cleaning Firewall Audit Utility (/usr/local/bin/ufw-cleanup.sh)
echo "🛡️ Installing self-cleaning firewall audit utility..."
cat <<'EOF' > /usr/local/bin/ufw-cleanup.sh
#!/bin/bash
# /usr/local/bin/ufw-cleanup.sh
# Automatically purges UFW rules for ports that have no active listening process/Docker container.
set -euo pipefail

if ! command -v ufw &>/dev/null; then
    exit 0
fi

# Default whitelist of ports that should NEVER be closed automatically
WHITELIST=("22" "80" "443" "81")
CURRENT_SSH_PORT=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | grep -oE '[0-9]+$' | head -n1 || echo "")
[ -n "$CURRENT_SSH_PORT" ] && WHITELIST+=("$CURRENT_SSH_PORT")

UFW_PORTS=$(ufw status 2>/dev/null | grep -E 'ALLOW|LIMIT|ALLOW IN|LIMIT IN' | awk '{print $1}' | grep -oE '^[0-9]+' | sort -u || true)
ACTIVE_PORTS=$(ss -tulpn 2>/dev/null | awk '{print $5}' | grep -oE ':[0-9]+$' | cut -d: -f2 | sort -u || true)

for port in $UFW_PORTS; do
    is_whitelisted=false
    for white in "${WHITELIST[@]}"; do
        if [ "$port" = "$white" ]; then
            is_whitelisted=true
            break
        fi
    done
    [ "$is_whitelisted" = true ] && continue

    is_active=false
    for active in $ACTIVE_PORTS; do
        if [ "$port" = "$active" ]; then
            is_active=true
            break
        fi
    done

    if [ "$is_active" = false ]; then
        echo "🗑️ Port $port has no active listening service. Purging from UFW..."
        ufw delete allow "$port" >/dev/null 2>&1 || true
        ufw delete allow "$port/tcp" >/dev/null 2>&1 || true
        ufw delete allow "$port/udp" >/dev/null 2>&1 || true
        ufw delete limit "$port" >/dev/null 2>&1 || true
        ufw delete limit "$port/tcp" >/dev/null 2>&1 || true
        ufw delete limit "$port/udp" >/dev/null 2>&1 || true
    fi
done
ufw reload >/dev/null 2>&1 || true
EOF
chmod +x /usr/local/bin/ufw-cleanup.sh

# 9. Install Automated Docker Version Cleaner (/usr/local/bin/docker-version-cleanup.sh)
echo "🐳 Installing automated Docker version cleaner (Now + Fallback retention)..."
cat <<'EOF' > /usr/local/bin/docker-version-cleanup.sh
#!/bin/bash
# =====================================================================
# 🐳 docker-version-cleanup.sh: Automated Dual-Version Retention Cleaner
# =====================================================================
# Keeps ONLY the Active (newest) and Fallback (previous) version stacks.
# Automatically purges older Docker stacks and dangling containers.
# Example: If v0.0.1, v0.0.2, v0.0.3 exist, v0.0.1 is deleted.
# =====================================================================
set -euo pipefail

if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
    exit 0
fi

BASE_DIRS=(
    "/home/${SUDO_USER:-$USER}/project/sawarisadhan"
    "/opt/project/sawarisadhan"
    "/home/ubuntu/project/sawarisadhan"
    "/home/debian/project/sawarisadhan"
    "$HOME/project/sawarisadhan"
)

TARGET_BASE=""
for dir in "${BASE_DIRS[@]}"; do
    if [ -d "$dir/stacks" ] || [ -f "$dir/.version-state" ]; then
        TARGET_BASE="$dir"
        break
    fi
done

if [ -n "$TARGET_BASE" ] && [ -d "$TARGET_BASE/stacks" ]; then
    STACKS_DIR="$TARGET_BASE/stacks"
    STATE_FILE="$TARGET_BASE/.version-state"

    ACTIVE_TAG=""
    PREV_TAG=""

    if [ -f "$STATE_FILE" ]; then
        ACTIVE_TAG=$(grep -E '^ACTIVE_TAG=' "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
        PREV_TAG=$(grep -E '^PREV_TAG=' "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
    fi

    AVAILABLE_TAGS=($(find "$STACKS_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" 2>/dev/null | sort -V || true))
    TAG_COUNT=${#AVAILABLE_TAGS[@]}

    if [ "$TAG_COUNT" -gt 2 ]; then
        if [ -z "$ACTIVE_TAG" ]; then
            ACTIVE_TAG="${AVAILABLE_TAGS[$((TAG_COUNT - 1))]}"
            PREV_TAG="${AVAILABLE_TAGS[$((TAG_COUNT - 2))]}"
        fi

        for tag in "${AVAILABLE_TAGS[@]}"; do
            if [ "$tag" != "$ACTIVE_TAG" ] && [ "$tag" != "$PREV_TAG" ]; then
                COMPOSE_FILE="$STACKS_DIR/$tag/docker-compose.yml"
                PROJECT_NAME="sawari-$tag"

                if [ -f "$COMPOSE_FILE" ]; then
                    docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" down -v --remove-orphans >/dev/null 2>&1 || true
                fi
                docker ps -a --filter "name=.*-v?${tag//./\\.}.*" -q 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
                rm -rf "$STACKS_DIR/$tag"
            fi
        done
    fi
fi

# Cleanup standalone legacy service containers that exceed dual-version window
for service in "auth" "core" "media" "desktop" "web"; do
    CONTAINERS=($(docker ps -a --format '{{.Names}}' | grep -E "(sawarisadhan|sawari)-${service}" | sort -V || true))
    COUNT=${#CONTAINERS[@]}
    if [ "$COUNT" -gt 2 ]; then
        REMOVE_COUNT=$((COUNT - 2))
        for ((i=0; i<REMOVE_COUNT; i++)); do
            docker rm -f "${CONTAINERS[$i]}" >/dev/null 2>&1 || true
        done
    fi
done

docker image prune -f >/dev/null 2>&1 || true
EOF
chmod +x /usr/local/bin/docker-version-cleanup.sh

# 10. Configure Crontab Maintenance Schedule
echo "🕒 Scheduling automated maintenance tasks in crontab..."
(
  crontab -l 2>/dev/null | grep -v -E "docker system prune|docker image prune|ufw-cleanup.sh|ram-cleanup.sh|disk-cleanup.sh|docker-version-cleanup.sh" || true
  # Check memory & swap pressure every 30 minutes
  echo "*/30 * * * * /usr/local/bin/ram-cleanup.sh >/dev/null 2>&1"
  # Daily automated Docker version cleanup at 03:30 AM (preserves only Active + Fallback)
  echo "30 3 * * * /usr/local/bin/docker-version-cleanup.sh >/dev/null 2>&1"
  # Daily automated disk and log cleanup at 04:00 AM
  echo "0 4 * * * /usr/local/bin/disk-cleanup.sh >/dev/null 2>&1"
  # Daily low-impact memory and disk sync at 04:30 AM
  echo "30 4 * * * /usr/local/bin/ram-cleanup.sh && sync >/dev/null 2>&1"
  # Weekly Sunday deep sweep: Docker prune at 03:00 AM, Firewall port audit at 04:30 AM
  echo "0 3 * * 0 docker system prune -af >/dev/null 2>&1"
  echo "30 4 * * 0 /usr/local/bin/ufw-cleanup.sh >/dev/null 2>&1"
) | crontab -
echo "✅ Maintenance cron schedule configured successfully."

# 11. Flush Inactive Kernel Page Caches
echo "🧠 Evicting dormant kernel filesystem buffers..."
sync
echo 3 > /proc/sys/vm/drop_caches

echo ""
echo "🏁 Debian cleanup & automated maintenance setup complete!"
echo "--------------------------------------------------"
echo "Memory Status:"
free -h
echo "--------------------------------------------------"
echo "Root Disk Status:"
df -h /
echo "--------------------------------------------------"
