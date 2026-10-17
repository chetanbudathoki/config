# 🚀 VPS Bootstrap & Hardening Configuration

An automated, secure, and production-ready bootstrap suite to transform a fresh Debian VPS into a hardened Docker host managed seamlessly via CI/CD.

---

## ⚡ Quick Start

```bash
# 1. SSH into your fresh VPS as root
ssh root@YOUR_SERVER_IP

# 2. Clone the repository
apt-get update && apt-get install -y git
git clone https://github.com/chetanbudathoki/config.git
cd config

# 3. (Recommended First Step) Debloat default cloud OS baggage
chmod +x clean/clean.sh
sudo ./clean/clean.sh

# 4. Configure credentials & options
nano config.yml

# 5. Run the core system & Docker installer
chmod +x setup/setup.sh
sudo ./setup/setup.sh

# 6. (Optional) Deploy Nginx Proxy Manager & Automated Weekly Cloudflare R2 Backups
chmod +x nginx/nginx.sh
sudo ./nginx/nginx.sh
```

---

## 📌 What This Setup Does

1. **Dedicated Service User**: Creates a passwordless, SSH-key-only admin user with passwordless `sudo` and a private home directory (`700`).
2. **SSH Hardening & Firewall**: Disables password auth, restricts `AllowUsers`, applies UFW rate-limiting, and sets up `DOCKER-USER` firewall rules.
3. **Docker CE & Log Limits**: Installs official Docker CE and Compose with a global 10MB container log cap and reliable external DNS resolvers.
4. **Isolated CI/CD Workspace**: Prepares `/home/$USER_NAME/project` with group `docker` and SetGID permissions (`2775`) for non-root CI/CD deploys.
5. **Built-in Nginx Proxy Manager**: Deploys NPM into `~/nginx` on your custom ports with the shared `proxy-network` bridge pre-configured.
6. **OS & Kernel Tuning**: Calibrates swap to physical RAM, reserves 64MB kernel memory (`vm.min_free_kbytes`) to stop SSH lockouts, optimizes database memory mapping (`vm.max_map_count`), increases file descriptors (`65535`), and locks down compilers.
7. **Autonomous RAM Watchdog & Maintenance**: Deploys an automatic memory watchdog (`/usr/local/bin/ram-cleanup.sh`) running every 30 minutes to evict pagecache and prune build memory at ≥85% pressure, emergency disk prune at ≥90%, and Sunday sweeps.
8. **Automated Weekly Cloudflare R2 Backups**: Compresses Nginx proxy data, SSL certificates, and firewall configs every Sunday at 02:00 AM and uploads snapshots offsite to Cloudflare R2 (`<your-bucket-name>`).
9. **CI/CD Health Check Utility**: Standardized helper script pre-installed at `~/project/healthcheck.sh` for verifying container startup and HTTP response.

---

## 📂 Configuration Overview (`config.yml`)

```yaml
username: "deployer"
ssh_public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@example.com"
timezone: "UTC"

nginx:
  ports:
    http: 80
    https: 443
    admin: 81
  credentials:
    email: "admin@example.com"
    password: "changeme"

backup:
  bucket: "your-bucket-name"
  endpoint: "https://<account_id>.r2.cloudflarestorage.com"
  access_key_id: "your_access_key"
  secret_access_key: "your_secret_key"
  retention_days: 30
```

---

## 📁 Module Documentation

Each component has its own dedicated documentation and guide:

- 📘 **[Setup & Hardening Module](setup/README.md)** (`setup/README.md`): Base OS setup, SSH hardening, Swap, Docker engine, RAM watchdog, and CI/CD health check.
- 🧹 **[Debian Debloat & Cleanup Module](clean/README.md)** (`clean/README.md`): Strips non-essential daemons (`exim4`, `rpcbind`, `avahi`), limits journal logs, and reclaims disk/RAM.
- 🌐 **[Nginx & Backup Module](nginx/README.md)** (`nginx/README.md`): Reverse proxy architecture, `proxy-network` bridge, and weekly Cloudflare R2 backup.
- 🗑️ **[Purge & User Cleanup Module](purge/README.md)** (`purge/README.md`): Safe non-root user removal, data deletion, and root lockout defense.
- 🚀 **[Push-Clean Module](push-clean/README.md)** (`push-clean/README.md`): Cross-platform scripts (Linux, macOS, Windows) to purge Git history and force-push clean commits.
- 📋 **[Roadmap & Future Enhancements](todo.md)** (`todo.md`): List of recommended future improvements (alerting webhooks, container memory limits, metrics).


---

## 🧹 Purging Non-Root Users

To completely remove non-root user accounts while keeping root access safe:
```bash
chmod +x purge/purge.sh
sudo ./purge/purge.sh            # Purges ALL non-root users
sudo ./purge/purge.sh <username> # Or purges only the specified user
```
*(Docker, UFW rules, and system packages remain intact).*
