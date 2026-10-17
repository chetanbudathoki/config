#!/bin/bash

# purge.sh: Remove non-root users and their associated data.
# Usage: 
#   sudo ./purge.sh              # Purges ALL non-root human/service users (UID >= 1000)
#   sudo ./purge.sh <username>   # Purges only the specified user
#
# Must be executed as root.

set -e # Exit on error

# Root check: This script modifies system users and files.
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run directly as root (e.g., sudo ./purge.sh or logged in as root)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/config.yml" ]; then
    CONFIG_FILE="$SCRIPT_DIR/config.yml"
elif [ -f "$SCRIPT_DIR/../config.yml" ]; then
    CONFIG_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/config.yml"
else
    CONFIG_FILE="$SCRIPT_DIR/config.yml"
fi

# Helper to extract SSH keys from config.yml (supports single line or multiline block)
get_config_ssh_keys() {
    if [ -f "$CONFIG_FILE" ]; then
        if grep -E "^ssh_public_key:[[:space:]]*[\|>]" "$CONFIG_FILE" >/dev/null 2>&1; then
            sed -n '/^ssh_public_key:[[:space:]]*[\|>]/,/^[^[:space:]#]/p' "$CONFIG_FILE" 2>/dev/null | \
                grep -E '^[[:space:]]+ssh-(ed25519|rsa|dss|ecdsa)' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
            return 0
        fi
        local key_line
        key_line=$(grep -E "^ssh_public_key:" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d'#' -f1 | cut -d':' -f2- | tr -d '"' | tr -d "'" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$key_line" ]; then
            echo "$key_line"
            return 0
        fi
    fi
}

CONFIG_SSH_KEYS=$(get_config_ssh_keys)

# Ensure at least 1 valid SSH key exists in config.yml or in /root/.ssh/authorized_keys
if [ -z "$CONFIG_SSH_KEYS" ] && [ ! -s /root/.ssh/authorized_keys ]; then
    echo "❌ FATAL SAFETY CHECK: No valid SSH public key found!"
    echo "To prevent getting locked out of the server after purging users,"
    echo "you must configure at least 1 valid SSH key in 'config.yml'."
    exit 1
fi

if [[ "$CONFIG_SSH_KEYS" == *"user@example.com"* ]] || [[ "$CONFIG_SSH_KEYS" == *"user1@example.com"* ]] || [[ "$CONFIG_SSH_KEYS" == *"AAAA..."* ]]; then
    if [ ! -s /root/.ssh/authorized_keys ]; then
        echo "❌ FATAL SAFETY CHECK: 'config.yml' still contains example placeholder SSH keys,"
        echo "and '/root/.ssh/authorized_keys' is empty."
        echo "Please paste your real SSH public key into 'config.yml' before purging users to prevent lockout."
        exit 1
    fi
fi

# Determine target users:
TARGET_USER="$1"
USERS_TO_PURGE=()

if [ -n "$TARGET_USER" ]; then
    if [ "$TARGET_USER" = "root" ]; then
        echo "❌ ERROR: Purging 'root' is never allowed."
        exit 1
    fi
    if ! id "$TARGET_USER" &>/dev/null; then
        echo "⚠️ User '$TARGET_USER' does not exist on this system."
        exit 1
    fi
    USERS_TO_PURGE=("$TARGET_USER")
else
    # Find all normal human / service users (UID >= 1000, excluding 'nobody' and 'root')
    while IFS=: read -r username _ uid _ _ homedir _; do
        if [ "$uid" -ge 1000 ] && [ "$username" != "nobody" ] && [ "$username" != "root" ]; then
            USERS_TO_PURGE+=("$username")
        fi
    done < /etc/passwd
fi

if [ ${#USERS_TO_PURGE[@]} -eq 0 ]; then
    echo "ℹ️ No non-root users found to purge."
    exit 0
fi

# 1. Safety Confirmation
echo "=========================================================="
echo "⚠️  WARNING: The following non-root user(s) will be PURGED:"
for u in "${USERS_TO_PURGE[@]}"; do
    echo "   - $u (Home: $(eval echo ~$u 2>/dev/null || echo '/home/'$u))"
done
echo "All their home directories, processes, SSH keys, and sudo privileges will be deleted."
echo "Root SSH key access will be safeguarded and Port 22 verified open."
echo "=========================================================="
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
    echo "Aborted. No changes made."
    exit 0
fi

# 2. Lockout Prevention: Guarantee Root SSH Key & Port 22
echo ""
echo "🔐 Securing root SSH access before purging users..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# If valid keys exist in config.yml, sync them to root's authorized_keys
if [ -n "$CONFIG_SSH_KEYS" ] && [[ "$CONFIG_SSH_KEYS" != *"AAAA..."* ]]; then
    # Merge unique keys
    touch /root/.ssh/authorized_keys
    while IFS= read -r key; do
        if [ -n "$key" ] && ! grep -qF "$key" /root/.ssh/authorized_keys; then
            echo "$key" >> /root/.ssh/authorized_keys
        fi
    done <<< "$CONFIG_SSH_KEYS"
fi
chmod 600 /root/.ssh/authorized_keys
echo "✅ Root SSH authorized_keys confirmed."

# Ensure SSH server configuration permits root key login
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    # Ensure root is in AllowUsers if AllowUsers is active
    if grep -q "^AllowUsers" /etc/ssh/sshd_config; then
        if ! grep -q -E "^AllowUsers.*\broot\b" /etc/ssh/sshd_config; then
            sed -i 's/^AllowUsers[[:space:]]*/AllowUsers root /' /etc/ssh/sshd_config
        fi
    fi
fi

# Ensure UFW allows SSH port 22
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        echo "🛡️ Ensuring port 22/tcp is allowed in UFW firewall..."
        ufw allow 22/tcp comment 'SSH Port 22 (Root Access)' >/dev/null 2>&1 || true
    fi
fi

# 2. Iterate and purge each target user
for USER_NAME in "${USERS_TO_PURGE[@]}"; do
    echo ""
    echo "🗑️  Purging user: '$USER_NAME'..."

    # Kill active processes
    echo "🛑 Killing all active processes for '$USER_NAME'..."
    pkill -u "$USER_NAME" || true
    sleep 1

    # Remove user and home directory
    if id "$USER_NAME" &>/dev/null; then
        echo "👤 Removing user and deleting home directory..."
        userdel -r "$USER_NAME" 2>/dev/null || userdel -f "$USER_NAME" 2>/dev/null || true
        # Ensure home dir is removed if userdel left it
        rm -rf "/home/$USER_NAME" || true
        echo "✅ User '$USER_NAME' removed."
    fi

    # Remove custom sudoers configuration
    SUDOERS_FILE="/etc/sudoers.d/$USER_NAME"
    if [ -f "$SUDOERS_FILE" ]; then
        echo "🔑 Removing sudoers file: $SUDOERS_FILE"
        rm -f "$SUDOERS_FILE"
        echo "✅ Sudoers entry removed."
    fi

    # Remove temporary files
    echo "🧹 Cleaning up temporary files for '$USER_NAME'..."
    rm -rf /tmp/*"$USER_NAME"* 2>/dev/null || true
    rm -rf /var/tmp/*"$USER_NAME"* 2>/dev/null || true

    # Clean from /etc/ssh/sshd_config AllowUsers if present
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i -E "s/([[:space:]])$USER_NAME([[:space:]]|$)/\1/g" /etc/ssh/sshd_config
        # Clean up any trailing whitespace in AllowUsers
        sed -i 's/[[:space:]]*$//' /etc/ssh/sshd_config
    fi
done

# Restart SSH safely if sshd_config was modified and is valid
if command -v sshd >/dev/null 2>&1; then
    if sshd -t 2>/dev/null; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    fi
fi

echo ""
echo "🏁 Purge Complete! All specified non-root users have been removed."
echo "Root SSH access and base system packages remain intact."

