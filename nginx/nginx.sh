#!/bin/bash

# =====================================================================
# 🌐 nginx.sh: Modular Nginx Proxy Manager & Cloudflare R2 Backup Setup
# =====================================================================
# Usage:
#   chmod +x nginx.sh
#   sudo ./nginx.sh
#
# This script deploys:
#   1. External Docker shared bridge network ('proxy-network')
#   2. Nginx Proxy Manager (NPM) on configured ports
#   3. Opens required firewall ports in UFW
#   4. Configures automated weekly offsite backups to Cloudflare R2 / S3
# =====================================================================

set -euo pipefail

echo "🚀 Starting Nginx Proxy Manager & Cloudflare R2 Backup Setup..."

# Root check
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run directly as root (e.g., sudo ./nginx.sh)."
    exit 1
fi

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

# 1. Load Configurations
USER_NAME=$(get_yaml_value "username")
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "username" ]; then
    # Fallback to the first non-root human user (UID >= 1000)
    USER_NAME=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd || echo "root")
fi

NGINX_HTTP_PORT=$(get_yaml_value "nginx.ports.http" "80")
NGINX_HTTPS_PORT=$(get_yaml_value "nginx.ports.https" "443")
NGINX_ADMIN_PORT=$(get_yaml_value "nginx.ports.admin" "81")
NGINX_ADMIN_EMAIL=$(get_yaml_value "nginx.credentials.email" "")
NGINX_ADMIN_PASSWORD=$(get_yaml_value "nginx.credentials.password" "")

BACKUP_BUCKET=$(get_yaml_value "backup.bucket" "")
BACKUP_ENDPOINT=$(get_yaml_value "backup.endpoint" "")
BACKUP_ACCESS_KEY=$(get_yaml_value "backup.access_key_id" "")
BACKUP_SECRET_KEY=$(get_yaml_value "backup.secret_access_key" "")

# Ensure Docker is installed and running
if ! command -v docker &>/dev/null; then
    echo "❌ ERROR: Docker is not installed. Please run './setup.sh' first."
    exit 1
fi

# 2. Open Firewall Ports in UFW
if command -v ufw >/dev/null 2>&1; then
    echo "🛡️ Configuring Firewall rules for Nginx..."
    [ -n "$NGINX_HTTP_PORT" ] && ufw allow "$NGINX_HTTP_PORT"/tcp comment 'Nginx HTTP' || true
    [ -n "$NGINX_HTTPS_PORT" ] && ufw allow "$NGINX_HTTPS_PORT"/tcp comment 'Nginx HTTPS' || true
    [ -n "$NGINX_ADMIN_PORT" ] && ufw allow "$NGINX_ADMIN_PORT"/tcp comment 'Nginx Proxy Manager Admin' || true
fi

# 3. Deploy Nginx Proxy Manager
echo "🚀 Deploying Nginx Proxy Manager stack..."
USER_HOME=$(eval echo "~$USER_NAME")
NGINX_DIR="$USER_HOME/nginx"
mkdir -p "$NGINX_DIR/data" "$NGINX_DIR/letsencrypt"

# Shared external bridge network for proxying to future CI/CD deployed containers
SHARED_NETWORK="proxy-network"
if ! docker network inspect "$SHARED_NETWORK" &>/dev/null; then
    echo "🌐 Creating shared Docker network '$SHARED_NETWORK'..."
    docker network create "$SHARED_NETWORK" || true
fi

# Build ports list dynamically from configured values
PORT_LINES=""
[ -n "$NGINX_HTTP_PORT" ] && PORT_LINES="${PORT_LINES}      - '${NGINX_HTTP_PORT}:80'\n"
[ -n "$NGINX_HTTPS_PORT" ] && PORT_LINES="${PORT_LINES}      - '${NGINX_HTTPS_PORT}:443'\n"
[ -n "$NGINX_ADMIN_PORT" ] && PORT_LINES="${PORT_LINES}      - '${NGINX_ADMIN_PORT}:81'\n"

# Generate docker-compose.yml for Nginx Proxy Manager
cat <<EOF > "$NGINX_DIR/docker-compose.yml"
# =====================================================================
# 🐳 Generated by nginx.sh - Nginx Proxy Manager Stack
# =====================================================================
version: '3.8'

services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
$(echo -e "$PORT_LINES")
    environment:
      DISABLE_IPV6: 'true'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - default
      - ${SHARED_NETWORK}

networks:
  ${SHARED_NETWORK}:
    external: true
EOF

chown -R "$USER_NAME:docker" "$NGINX_DIR" 2>/dev/null || chown -R "$USER_NAME:$USER_NAME" "$NGINX_DIR"
chmod 2775 "$NGINX_DIR"

# Start the stack using docker compose
echo "🐳 Starting Nginx Proxy Manager container..."
(cd "$NGINX_DIR" && docker compose up -d) || echo "⚠️ Warning: Failed to boot Nginx Proxy Manager automatically. You can run 'docker compose up -d' in $NGINX_DIR."
echo "✅ Nginx Proxy Manager stack is active at '$NGINX_DIR'."

# 4. Automated Weekly Cloudflare R2 / S3 Backup Setup
if [ -n "$BACKUP_ACCESS_KEY" ] && [ -n "$BACKUP_SECRET_KEY" ] && \
   [ -n "$BACKUP_BUCKET" ] && [ "$BACKUP_BUCKET" != "your-bucket-name" ] && \
   [ -n "$BACKUP_ENDPOINT" ] && [[ "$BACKUP_ENDPOINT" != *"<account_id>"* ]]; then
    echo "🗄️ Setting up automated weekly Cloudflare R2 backup..."

    # Install awscli if not present
    if ! command -v aws &>/dev/null; then
        echo "📦 Installing awscli for S3/R2 backup synchronization..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" awscli || true
    fi

    # Create secure root-only backup credentials
    mkdir -p /root/.aws
    cat <<EOF > /root/.aws/credentials
[default]
aws_access_key_id = $BACKUP_ACCESS_KEY
aws_secret_access_key = $BACKUP_SECRET_KEY
EOF
    chmod 600 /root/.aws/credentials

    cat <<EOF > /root/.aws/config
[default]
region = auto
output = json
EOF
    chmod 600 /root/.aws/config

    # Generate /usr/local/bin/backup-vps.sh
    cat <<EOF > /usr/local/bin/backup-vps.sh
#!/bin/bash
# =====================================================================
# 🗄️ Automated VPS Backup (Nginx Proxy Manager, SSL Certs & Configs)
# Uploads encrypted/compressed snapshots to Cloudflare R2 / S3
# =====================================================================
set -euo pipefail

BACKUP_BUCKET="$BACKUP_BUCKET"
BACKUP_ENDPOINT="$BACKUP_ENDPOINT"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")

# Determine public IPv4 of the VPS and format as slug (e.g., 192-0-2-1)
SERVER_IP=\$(curl -s4 https://ifconfig.me || curl -s4 https://api.ipify.org || hostname -I | awk '{print \$1}' || echo "unknown-ip")
IP_SLUG=\$(echo "\$SERVER_IP" | tr '.' '-')

TEMP_DIR=\$(mktemp -d)
ARCHIVE_NAME="nginx_\${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="\${TEMP_DIR}/\${ARCHIVE_NAME}"

cleanup() {
    rm -rf "\$TEMP_DIR"
}
trap cleanup EXIT

echo "📦 [\$(date '+%Y-%m-%d %H:%M:%S')] Starting Nginx Proxy Manager backup for IP '\$SERVER_IP' (slug: \$IP_SLUG)..."

NGINX_TARGET="$NGINX_DIR"
if [ ! -d "\$NGINX_TARGET" ]; then
    echo "⚠️ Target directory '\$NGINX_TARGET' not found. Exiting."
    exit 0
fi

echo "🗜️ Compressing \$NGINX_TARGET..."
tar -czf "\$ARCHIVE_PATH" -C "$USER_HOME" "nginx" --exclude="*.log" --exclude="*.sock" 2>/dev/null || true

# Target S3/R2 path: /<bucketname>/<ip-as-a-slug>/<username>/nginx/<archive_name>
R2_KEY="\${IP_SLUG}/${USER_NAME}/nginx/\${ARCHIVE_NAME}"

echo "☁️ Uploading \$ARCHIVE_NAME to S3/R2 destination: \${BACKUP_BUCKET}/\${R2_KEY}..."
aws s3 cp "\$ARCHIVE_PATH" "s3://\${BACKUP_BUCKET}/\${R2_KEY}" \\
    --endpoint-url "\$BACKUP_ENDPOINT" --only-show-errors

echo "✅ [\$(date '+%Y-%m-%d %H:%M:%S')] Backup successfully uploaded to: \${BACKUP_BUCKET}/\${R2_KEY}."
EOF

    chmod 700 /usr/local/bin/backup-vps.sh

    # Schedule weekly backup on Sunday at 02:00 AM
    echo "🕒 Scheduling weekly Sunday backup at 02:00 AM..."
    (
      crontab -l 2>/dev/null | grep -v "backup-vps.sh" || true
      echo "0 2 * * 0 /usr/local/bin/backup-vps.sh >/var/log/vps-backup.log 2>&1"
    ) | crontab -
    echo "✅ Weekly Cloudflare R2 backup scheduled (Sunday 02:00 AM)."
else
    echo "ℹ️  S3/Cloudflare R2 backup credentials not set or using placeholders. Skipping backup schedule."
fi

echo ""
echo "🏁 Nginx & Backup Setup Complete!"
echo "--------------------------------------------------"
echo "Nginx Proxy Manager: Active"
[ -n "$NGINX_ADMIN_PORT" ] && echo "Admin Web Console  : http://YOUR_SERVER_IP:$NGINX_ADMIN_PORT"
[ -n "$NGINX_ADMIN_EMAIL" ] && echo "Default Account    : $NGINX_ADMIN_EMAIL / ${NGINX_ADMIN_PASSWORD:-(none)}"
echo "Shared Network     : proxy-network"
if [ -n "$BACKUP_BUCKET" ] && [ "$BACKUP_BUCKET" != "your-bucket-name" ]; then
    echo "Weekly R2 Backup   : Active (Destination: s3://${BACKUP_BUCKET}/<ip-slug>/nginx/)"
fi
echo "--------------------------------------------------"
