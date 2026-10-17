# 🚀 Setup Module (`setup/`)

The `setup/` module handles initial bare-metal provisioning and OS hardening exclusively for **Debian** VPS servers. It creates an isolated admin user, configures SSH anti-lockout immunity, sets up Docker CE, tunes the Linux kernel to eliminate out-of-memory lockups, and delegates scheduled OS hygiene to `clean/clean.sh`.

---

## 📋 What `setup.sh` Configures

### 1. Dedicated Service User & Locked Passwords
* Creates a dedicated non-root user matching the `username` setting in `config.yml`.
* Locks the account password (`passwd -l`), guaranteeing that only cryptographic SSH public keys can authenticate.
* Grants passwordless sudo access via `/etc/sudoers.d/$USER_NAME` for non-interactive CI/CD automation.
* Configures a private home directory with restrictive permissions (`chmod 700`).

### 2. SSH Hardening & Anti-Lockout Immunity
* **Brute-Force Immunity**: Sets `PasswordAuthentication no` and `MaxAuthTries 2`.
* **Root Fallback**: Sets `PermitRootLogin prohibit-password` (root password disabled, cryptographic keys allowed as emergency backup).
* **Strict Whitelisting**: Restricts SSH daemon access to authorized users via `AllowUsers $USER_NAME root`.
* **Idle Timeout**: Automatically disconnects inactive SSH sessions after 5 minutes (`ClientAliveInterval 300`).
* **Cloud-Init Cleanup**: Removes cloud provider override snippets in `/etc/ssh/sshd_config.d/` to prevent password auth leaks.
* **OOM Immunity & Real-Time Scheduling**: Installs a systemd override at `/etc/systemd/system/ssh.service.d/override.conf`:
  * `OOMScoreAdjust=-1000`: Protects `sshd` from ever being terminated by the Linux kernel OOM-killer.
  * `CPUSchedulingPolicy=rr` & `CPUSchedulingPriority=50`: Grants real-time round-robin CPU scheduling so SSH logins succeed even when application containers peg the CPU at 96%+.
  * `MemoryMin=32M`: Reserves 32MB of un-evictable memory for spawning SSH login sessions.

### 3. Docker CE & Daemon Log Rotation
* Verifies Debian architecture and installs official Docker CE, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin` using the official Debian GPG keyring.
* Configures `/etc/docker/daemon.json` with strict container log limits:
  ```json
  {
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "10m",
      "max-file": "3"
    },
    "dns": ["1.1.1.1", "8.8.8.8"]
  }
  ```
  *(Caps container log size to 30MB total per container, eliminating unbounded runaway log files).*
* Adds `$USER_NAME` to the `docker` group so Docker commands run without `sudo`.

### 4. Debian Debloat & Maintenance Automation (Delegated to `clean/clean.sh`)
* Automatically invokes [clean/clean.sh](file:///d:/projects/cb/config/clean/clean.sh) during bootstrap:
  * Purges unnecessary background daemons (`exim4`, `rpcbind`, `avahi-daemon`, `cups`, `snapd`).
  * Caps `systemd-journald` to **50MB max** with a **7-day retention cutoff**.
  * Installs `/usr/local/bin/disk-cleanup.sh`, `/usr/local/bin/ram-cleanup.sh`, and `/usr/local/bin/ufw-cleanup.sh`.
  * Registers automated crontab schedules for 30-minute RAM watchdogs, daily disk/log hygiene, and weekly deep prunes.

### 5. Isolated CI/CD Workspace (`/home/$USER_NAME/project`)
* Prepares `/home/$USER_NAME/project` with `docker` group ownership and SetGID permissions (`chmod 2775`).
* Any file or folder created by CI/CD automatically inherits the `docker` group, allowing seamless deployments without permission errors.
* Provides a standardized `/opt/project` symlink pointing directly to `/home/$USER_NAME/project` (with backward-compatible `projects` symlinks).

### 6. UFW Firewall with Docker Leak Protection
* Rate-limits SSH connections (`ufw limit $SSH_PORT/tcp`) to block connection flooding.
* Enforces `default deny incoming` and `default allow outgoing`.
* Injects `DOCKER-USER` filtering into `/etc/ufw/after.rules` to prevent Docker from bypassing UFW through raw iptables rules.

### 7. Kernel Memory, Swap & Anti-Thrashing Stability
* **Dynamic Swap Allocation**: Detects server physical RAM and allocates **4096MB–8192MB** swap with `vm.swappiness=10`. Replaces insufficient cloud provider defaults (e.g. 1GB swap) that trigger memory thrashing.
* **Reserved Kernel Memory**: Sets `vm.min_free_kbytes=131072` (reserves **128MB** of physical RAM strictly for kernel interrupt handlers and SSH socket allocations), preventing `fork(): Cannot allocate memory` lockouts.
* **I/O Throttling**: Configures `vm.dirty_background_ratio=5` and `vm.dirty_ratio=10` to stop dirty disk flushes from freezing system CPU cores.
* **NTP Time Synchronization (`systemd-timesyncd`)**: Enforces active time synchronization against Cloudflare (`time.cloudflare.com`), Google (`time.google.com`), and Debian pools, completely preventing clock drift that breaks Let's Encrypt certificate renewals and Cloudflare R2 / AWS S3 HMAC signatures.
* **OOM Deadlock Prevention**: Sets `vm.panic_on_oom=0` and `vm.oom_kill_allocating_task=1` to terminate the specific leaking process rather than locking the entire system.
* **Database & File Limits**: Sets `vm.max_map_count=262144` for databases/Elasticsearch, and raises system open file limits (`nofile`) to `65535`.

### 8. CI/CD Post-Deployment Health Check Utility
* Installs a standardized health check utility at `/home/$USER_NAME/project/healthcheck.sh`:
  * Supports testing HTTP endpoints: `./healthcheck.sh https://api.yourdomain.com 30`
  * Supports testing Docker container states: `./healthcheck.sh web-app-container 30`
  * Exit code `0` on success, `1` on timeout. Perfect for GitHub Actions deployment steps.

---

## ⚡ Usage

```bash
# Run from repository root:
chmod +x setup/setup.sh
sudo ./setup/setup.sh
```

---

## 🔒 Post-Setup Verification

> [!IMPORTANT]
> **Do not close your root terminal yet.** Open a **new terminal** on your local machine and verify SSH key login:
> ```bash
> ssh your_username@YOUR_SERVER_IP -p 22
> ```

Once verified, test running Docker without sudo:
```bash
docker ps
```
