# 🧹 Debian OS Debloater & System Maintenance (`clean/`)

The `clean/` module provides both **one-time OS debloating** and **continuous automated hygiene** for Debian VPS servers. It strips cloud-image bloat, caps journal and logrotate retention, monitors RAM/Swap to prevent OOM lockouts, and keeps disk usage permanently bounded.

---

## 🗑️ What Gets Cleaned & Automated

### 1. One-Time OS Debloater (Purging Unneeded Daemons)
Fresh cloud images from hosting providers (Hetzner, DigitalOcean, Linode, Proxmox templates) often bundle unnecessary daemons that consume background RAM and listen on open ports:
* **`cups`, `cups-daemon`, `cups-browsed`**: Printer spooler daemons not required on cloud servers.
* **`avahi-daemon`**: mDNS zero-configuration network discovery daemon.
* **`rpcbind`**: Legacy SunRPC portmapper prone to remote vulnerabilities and unnecessary memory overhead.
* **`exim4`, `exim4-base`, `exim4-config`**: Debian default mail transfer agent (Docker apps send email via external SMTP/Sendgrid APIs).
* **`modemmanager`**: Cellular modem service.
* **`multipath-tools`**: Multipath disk daemon (unneeded on single virtual disk VPS).
* **`bluez`**: Bluetooth daemon.
* **`snapd`**: Removed so Docker CE native engine is used exclusively without duplicate container runners.

### 2. Strict Log Retention & Zero-Pileup Policy
* **`systemd-journald` Cap**:
  * Configured in `/etc/systemd/journald.conf.d/00-journal-size.conf`.
  * `SystemMaxUse=50M` (hard cap of 50MB across all journals on disk).
  * `RuntimeMaxUse=25M` (caps in-memory volatile journal).
  * `SystemMaxFileSize=10M` (individual log archives capped to 10MB).
  * `MaxRetentionSec=7day` (logs older than 7 days are automatically purged).
* **Global `logrotate` Hardening**:
  * Configured in `/etc/logrotate.d/00-global-retention`.
  * Rotates standard system logs (`syslog`, `auth.log`, `daemon.log`, `kern.log`, etc.) **daily**, gzip-compresses them, and deletes archives older than **7 days** (`rotate 7`).
  * Triggers immediate rotation if a single file reaches 15MB (`maxsize 15M`).
* **Automated `/tmp` & `/var/tmp` Sweeper**:
  * Configured via `/etc/tmpfiles.d/tmp-cleanup.conf`.
  * Purges `/tmp` files older than 3 days and `/var/tmp` files older than 7 days.

### 3. Automated Hygiene Utilities (Installed to `/usr/local/bin`)

| Utility | Location | What It Does |
| :--- | :--- | :--- |
| **`docker-version-cleanup.sh`** | `/usr/local/bin/docker-version-cleanup.sh` | • **Dual-Version Retention**: Preserves only Active (latest) and Fallback (previous) version stacks.<br>• **Auto-Deletes Older Stacks**: If versions `v0.0.1`, `v0.0.2`, and `v0.0.3` exist, `v0.0.1` is stopped (`down -v`) and deleted.<br>• Cleans orphaned service containers exceeding 2 versions.<br>• Prunes dangling Docker images. |
| **`disk-cleanup.sh`** | `/usr/local/bin/disk-cleanup.sh` | • Runs `journalctl --vacuum-time=7d --vacuum-size=50M`.<br>• Cleans APT archive cache (`apt-get clean && apt-get autoclean`).<br>• Deletes rotated `.gz` logs older than 7 days.<br>• Purges stale `/tmp` and `/var/tmp` files older than 3 days.<br>• Prunes dangling Docker BuildKit caches older than 7 days (`docker builder prune`). |
| **`ram-cleanup.sh`** | `/usr/local/bin/ram-cleanup.sh` | • **At ≥85% RAM**: Drops filesystem pagecache (`drop_caches`).<br>• **At ≥85% Swap**: Evicts caches and frees Docker memory to prevent CPU thrashing.<br>• **At ≥92% RAM**: Prunes Docker builder storage.<br>• **At ≥90% Root Disk**: Triggers emergency `docker system prune -f`.<br>• Prunes stopped/dead containers older than 48 hours. |
| **`ufw-cleanup.sh`** | `/usr/local/bin/ufw-cleanup.sh` | Audits open UFW firewall ports against active listening processes and Docker bindings, safely removing orphaned rules while protecting whitelisted ports (`22`, `80`, `443`, `81`). |

### 4. Continuous Crontab Maintenance Schedule
The root crontab is automatically configured to execute hygiene tasks on fixed schedules:

```cron
# RAM & Swap watchdog (Runs every 30 minutes)
*/30 * * * * /usr/local/bin/ram-cleanup.sh >/dev/null 2>&1

# Daily Docker version stack cleaner (Keeps only Active + Fallback, e.g. deletes 0.0.1 if 0.0.2 and 0.0.3 exist)
30 3 * * * /usr/local/bin/docker-version-cleanup.sh >/dev/null 2>&1

# Daily automated disk and log cleanup (Every day at 04:00 AM)
0 4 * * * /usr/local/bin/disk-cleanup.sh >/dev/null 2>&1

# Daily low-impact memory and filesystem sync (Every day at 04:30 AM)
30 4 * * * /usr/local/bin/ram-cleanup.sh && sync >/dev/null 2>&1

# Weekly deep Docker prune (Sundays at 03:00 AM)
0 3 * * 0 docker system prune -af >/dev/null 2>&1

# Weekly self-cleaning firewall audit (Sundays at 04:30 AM)
30 4 * * 0 /usr/local/bin/ufw-cleanup.sh >/dev/null 2>&1
```

---

## ⚡ Usage

### Standalone Run (Manual First Run on Fresh VPS)
You can run `clean/clean.sh` as your very first command after cloning the repository:

```bash
chmod +x clean/clean.sh
sudo ./clean/clean.sh
```

### Automated Integration with `setup.sh`
When running `sudo ./setup/setup.sh`, it automatically checks for and executes `clean/clean.sh`, ensuring all debloat and scheduled cron maintenance are active without manual intervention.

---

## 📊 Expected RAM Usage Benchmark (Debian)

| Server State | Typical Idle RAM | What Is Running |
| :--- | :--- | :--- |
| **Stock Fresh Debian VPS** *(from Cloud Provider)* | **~180MB – 260MB** | Systemd, `exim4` (MTA), `rpcbind`, `avahi-daemon`, `multipathd`, journal logs, and package caches. |
| **After Running `clean/clean.sh`** | **~60MB – 95MB** | Bare-metal Linux kernel, `sshd`, and core `systemd` only. |
| **After `setup.sh` + Docker** *(Idle)* | **~140MB – 190MB** | Core Debian OS + Docker CE daemon + `containerd` + Fail2ban + UFW firewall. |
| **With Nginx Proxy Manager** (`nginx.sh`) | **~260MB – 340MB** | Full stack + NodeJS runtime inside NPM + SQLite engine + Nginx reverse proxy. |

---

## 🔧 Manual Emergency Commands

If you ever need to manually force immediate memory or disk reclamation:

```bash
# Emergency RAM cache drop:
sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches

# Immediate disk & log vacuum:
sudo /usr/local/bin/disk-cleanup.sh

# Force deep Docker cleanup (unused images, containers, networks, build caches):
sudo docker system prune -af --volumes
```

