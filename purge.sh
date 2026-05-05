#!/bin/bash

# purge.sh: Completely remove a user and all their associated data.
# Usage: 
#   chmod +x purge.sh
#   sudo ./purge.sh [username]
#
# This script is a cleanup utility to completely undo the changes made
# by setup.sh for a specific user.

set -e # Exit on error

# --- CONFIGURATION ---
# Default username to purge if none is provided as an argument.
USER_TO_PURGE=${1:-"cb"}

# Root check: This script modifies system users and files.
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo)."
  exit 1
fi

# 1. Safety Confirmation
# Deleting a user is irreversible. We force a confirmation to prevent accidents.
echo "⚠️  WARNING: This will completely delete user '$USER_TO_PURGE' and ALL their data."
echo "This includes their home directory, SSH keys, and sudo privileges."
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# 2. Kill Active Processes
# We must stop any running programs owned by the user, otherwise 'userdel' 
# might fail because files are in use.
echo "🛑 Killing all active processes for user '$USER_TO_PURGE'..."
pkill -u "$USER_TO_PURGE" || true
sleep 2 # Give the system a moment to clean up process handles

# 3. Remove User and Home Directory
# The '-r' flag is critical: it removes the home directory and the mail spool.
if id "$USER_TO_PURGE" &>/dev/null; then
    echo "👤 Removing user '$USER_TO_PURGE' and deleting /home/$USER_TO_PURGE..."
    userdel -r "$USER_TO_PURGE"
    echo "✅ User and home directory removed."
else
    echo "⚠️  User '$USER_TO_PURGE' does not exist. Skipping."
fi

# 4. Remove Sudoers Configuration
# We clean up the custom file created in /etc/sudoers.d/ to ensure 
# no residual permissions remain.
SUDOERS_FILE="/etc/sudoers.d/$USER_TO_PURGE"
if [ -f "$SUDOERS_FILE" ]; then
    echo "🔑 Removing sudoers file: $SUDOERS_FILE"
    rm -f "$SUDOERS_FILE"
    echo "✅ Sudoers entry removed."
fi

# 5. General Cleanup
# Removing any temporary files or lock files associated with the username.
echo "🧹 Cleaning up temporary system files..."
rm -rf /tmp/*$USER_TO_PURGE* || true
rm -rf /var/tmp/*$USER_TO_PURGE* || true

echo "🏁 Purge Complete for '$USER_TO_PURGE'!"
echo "Note: System-wide packages like Docker and Fail2Ban remain installed."
