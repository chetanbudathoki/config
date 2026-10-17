# 🗑️ Purge & User Cleanup Module (`purge/`)

The `purge/` module completely removes non-root user accounts and cleans up their data from the server while safeguarding root access and preventing lockouts.

---

## 🔒 Lockout Protection Mechanism

Before deleting any account or files, `purge.sh`:
1. **Verifies SSH Keys**: Validates that at least 1 real, valid SSH public key exists in `config.yml` or `/root/.ssh/authorized_keys`. If missing or still using template placeholders on an empty root setup, it aborts immediately.
2. **Synchronizes Root Authorized Keys**: Merges the verified SSH keys into `/root/.ssh/authorized_keys` with strict `600` permissions.
3. **Guarantees Port 22**: Verifies UFW rules and opens port `22/tcp` so incoming SSH connections are allowed.
4. **Ensures Root SSH Access**: Confirms `/etc/ssh/sshd_config` permits root key login (`PermitRootLogin prohibit-password`) and adds `root` to `AllowUsers`.

---

## ⚡ Usage

```bash
# Purge ALL non-root human/service users (UID >= 1000):
sudo ./purge/purge.sh

# Purge only a specific user:
sudo ./purge/purge.sh <username>
```

---

## 🧹 What Gets Deleted for Target Users

- All running processes (`pkill -u <username>`).
- User account and entire home directory (`userdel -r <username>` and `rm -rf /home/<username>`).
- Sudoers privilege files (`/etc/sudoers.d/<username>`).
- Stale `/tmp` and `/var/tmp` files.
- Removes target user from `/etc/ssh/sshd_config` `AllowUsers`.

> [!NOTE]
> System packages (Docker, UFW, Fail2ban) and `root` account remain completely untouched.
