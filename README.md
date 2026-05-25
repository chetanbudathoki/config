# 🚀 VPS Bootstrap & Hardening Configuration

This repository provides an automated, modular, and secure bootstrap configuration to transform any fresh Debian/Ubuntu VPS into a production-ready, hardened environment optimized for running Docker.

It handles dedicated user creation, SSH hardening, security updates, firewall setup, Docker engine installation, system adjustments (swap/timezone), and brute-force protection out of the box.

---

## ✨ Features

- 👤 **Dedicated Service User**: Sets up a passwordless, secure admin user with locked password logins (SSH-key only), strict home directory privacy (`chmod 700`), and passwordless `sudo` privileges.
- 🛡️ **SSH Hardening & Rate-Limiting**: Disables password-based logins, X11 forwarding, and agent forwarding, restricts login exclusively to designated `AllowUsers`, configures short idle timeouts, and applies UFW rate-limiting (`ufw limit`) to block brute-force connections at the network firewall level.
- 🐳 **Docker Engine**: Installs Docker and Docker Compose, adds the service user to the Docker group, and implements global 10MB container log-rotation.
- 🧱 **Enterprise Hardening & Autonomous Updates**: Blocks local exploit compilations by locking down compilers to root-only, secures `/tmp` and `/dev/shm` mounts (`noexec,nosuid,nodev`), disables legacy network protocols (`sctp`, `dccp`, `rds`, `tipc`) at the kernel module level, and configures **fully autonomous weekly system/Docker updates** with scheduled 03:00 AM auto-reboots and disk space auto-cleans.
- 💾 **Enterprise System & Database Optimizations**: Configures a `2G` Swap file, locks system timezone, increases open files limits (`nofile` to `65535`) in limits.conf & systemd (preventing container file-handle locks), and boosts kernel virtual memory (`vm.max_map_count=262144`) and filesystem cache mapping (`vm.vfs_cache_pressure=50`) for high-performance database execution.
- 🧹 **OS Slimming & Footprint Minimization**: Purges resource-heavy and unnecessary native packages (like `snapd`, `exim4` mail agent, printing services, `rpcbind`, `avahi-daemon`) with strict configuration purges, and caps Systemd's `journald` logs to a maximum of `100MB` to maximize available RAM and SSD space.
- 🕒 **Weekly Docker & Firewall Cleanup (Maintenance)**: Sets up scheduled cron tasks:
  * **Sunday 03:00 AM**: Runs a full system sweep (`docker system prune -af`) to reclaim gigabytes of disk space from unused container images, stopped containers, unused network sockets, and BuildKit caches.
  * **Sunday 04:00 AM**: Runs a custom firewall auditor (`ufw-cleanup.sh`) that checks all allowed UFW rules against active container ports, automatically closing allowed ports that are no longer actively used, while safely protecting whitelisted core ports (`SSH`, `80`, `443`).
- 🧼 **Cleanup Utility (`purge.sh`)**: An administrative utility to securely and completely revert modifications for a user.

---

## 🛠️ How It Works

All configurations are modularized. The installer script `setup.sh` contains **no hardcoded credentials**. Instead, it dynamically parses YAML configurations directly from `config.yml`.

1. Open the configuration file `config.yml` and replace the template placeholder values with your real credentials.
2. Run `setup.sh` to begin provisioning.

> [!WARNING]
> **Safety Built-in**: `setup.sh` includes a safeguard that checks if placeholder templates (`username` or `AAAA...`) are left unchanged. If they are, it exits safely to prevent configuring a VPS with dummy credentials.

---

## 🚀 Step-by-Step Deployment Guide

### 1. Generate an SSH Key (on your Local Computer)
If you don't already have a modern secure key pair:
- **Windows (PowerShell) or Mac/Linux**:
  ```bash
  ssh-keygen -t ed25519 -C "your_email@example.com"
  ```
- Press **Enter** to accept the default location.
- Copy your public key. Under Windows, it is located at `C:\Users\YourName\.ssh\id_ed25519.pub`.

### 2. Prepare the Fresh VPS (Run as root)
Access your fresh VPS via root and install Git:
```bash
apt-get update && apt-get install -y git
```

### 3. Clone and Configure
Clone this repository and configure your credentials:
```bash
git clone https://github.com/chetanbudathoki/config.git
cd config

# Edit the credentials file
nano config.yml
```
Paste in your username and SSH public key:
```yaml
username: "your_username"
ssh_public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOm6A9331n/I9Z44FfGvV3fGZ... user@example.com"
```

### 4. Execute the Installer
Make `setup.sh` executable and run it:
```bash
chmod +x setup.sh
sudo ./setup.sh
```

### 5. Verify (Crucial Step)
**Do not close your current terminal session yet!** Open a **new** terminal window on your local machine and verify that you can connect using your new service user:
```bash
ssh your_username@YOUR_VPS_IP
```

---

## 📂 Configuration Options Reference

You can customize additional optional parameters in your `config.yml`. If omitted, they will fall back to safe default system settings:

| Setting | Default Value | Description |
| :--- | :--- | :--- |
| `username` | *(Required)* | The dedicated non-root admin user. |
| `ssh_public_key` | *(Required)* | The public key string allowed to SSH into the system. |
| `ssh_port` | `22` | Custom port to run the SSH service on. |
| `sync_keys_to_root` | `true` | Copies your keys to the `root` user as a fallback option. |
| `enable_security_extras` | `true` | Installs Fail2Ban, auto-upgrades, and kernel tweaks. |
| `swap_size` | `2G` | Virtual memory swap space size (set to `"0"` to disable). |
| `timezone` | `UTC` | The default system timezone location. |

---

## 🧹 Cleanup Utility (`purge.sh`)

If you ever need to completely remove a user, their associated home directory, SSH authorized keys, sudo privileges, and system files:
```bash
chmod +x purge.sh
sudo ./purge.sh [username]
```
*(Example: `sudo ./purge.sh cb`)*
