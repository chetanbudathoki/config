#!/bin/bash

# purge.sh: Completely remove a user and all their associated data.
# Usage: 
#   chmod +x purge.sh
#   sudo ./purge.sh [username]
# Default username is 'cb' if not provided.

set -e

# Default to 'cb' if no argument is provided
USER_TO_PURGE=${1:-"cb"}

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo)."
  exit 1
fi

echo "⚠️  WARNING: This will completely delete user '$USER_TO_PURGE' and ALL their data."
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# 1. Kill all processes owned by the user
echo "🛑 Killing all processes for user '$USER_TO_PURGE'..."
pkill -u "$USER_TO_PURGE" || true
sleep 2

# 2. Remove user and home directory
if id "$USER_TO_PURGE" &>/dev/null; then
    echo "👤 Removing user '$USER_TO_PURGE' and home directory..."
    userdel -r "$USER_TO_PURGE"
    echo "✅ User removed."
else
    echo "⚠️  User '$USER_TO_PURGE' does not exist. Skipping."
fi

# 3. Remove sudoers entry
SUDOERS_FILE="/etc/sudoers.d/$USER_TO_PURGE"
if [ -f "$SUDOERS_FILE" ]; then
    echo "🔑 Removing sudoers file: $SUDOERS_FILE"
    rm -f "$SUDOERS_FILE"
    echo "✅ Sudoers entry removed."
fi

# 4. Remove from specific groups (optional as userdel handles this usually)
# But we can check if they left any mess in /tmp or /var/tmp
echo "🧹 Cleaning up temporary files..."
rm -rf /tmp/*$USER_TO_PURGE* || true

echo "🏁 Purge Complete for '$USER_TO_PURGE'!"
