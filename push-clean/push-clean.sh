#!/bin/bash
# =====================================================================
# 🚀 push-clean.sh: Wipe Git History & Force Push a Single Clean Commit
# Target OS: Linux & macOS
# =====================================================================
# Usage:
#   chmod +x push-clean/push-clean.sh
#   ./push-clean/push-clean.sh "Release: $(date '+%Y-%m-%d')"
# =====================================================================

set -euo pipefail

COMMIT_MSG="${1:-Clean release: $(date '+%Y-%m-%d %H:%M:%S')}"
TARGET_BRANCH="${2:-main}"
REMOTE="${3:-origin}"

# Navigate to the git root directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

echo "🧹 Preparing clean, zero-history push to $REMOTE/$TARGET_BRANCH..."

# Safety check: Ensure no real secrets in config.yml
if [ -f "config.yml" ]; then
    if grep -qE "AAAA|your_access_key" config.yml 2>/dev/null; then
        echo "✅ Detected sample placeholders in config.yml."
    else
        echo "⚠️  NOTICE: Please ensure 'config.yml' does not contain private live secrets before making repo public!"
    fi
fi

# 1. Create a detached orphan branch with no parents or history
TEMP_BRANCH="temp-orphan-$(date +%s)"
git checkout --orphan "$TEMP_BRANCH" >/dev/null 2>&1

# 2. Stage all current files
git add -A

# 3. Create the single initial commit
git commit -m "$COMMIT_MSG"

# 4. Force-replace the target branch with the clean orphan branch
git branch -D "$TARGET_BRANCH" >/dev/null 2>&1 || true
git branch -m "$TARGET_BRANCH"

echo "🚀 Force-pushing single clean commit to $REMOTE/$TARGET_BRANCH..."
git push -f "$REMOTE" "$TARGET_BRANCH"

echo ""
echo "🎉 Clean push complete! Past git history has been completely purged on GitHub."
echo "Only 1 single commit now exists on '$TARGET_BRANCH'."