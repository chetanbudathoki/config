# 🚀 Push-Clean (Zero Git History Purge & Push)

Automated utility scripts for **Linux, macOS, and Windows** that allow you to push code changes to a public GitHub repository as a **single, fresh, squashed commit** while **completely wiping all previous Git commit history**.

---

## 🎯 Why Use Push-Clean?

When publishing or syncing a repository publicly, past commit history may accidentally contain:
- Old commits that once had private API keys, IP addresses, or secrets.
- Redundant debugging history or internal developer notes.
- Incomplete iterations.

**Push-Clean** creates a detached `--orphan` branch with no parent history, stages current workspace files, commits them cleanly, replaces `main`, and force-pushes to GitHub. The remote repository retains **only 1 commit** with zero past trail.

---

## 📁 Available Scripts

| OS / Shell | Script Path | Description |
| :--- | :--- | :--- |
| **Linux & macOS** | [`config/push-clean/push-clean.sh`](file:///d:/projects/cb/config/push-clean/push-clean.sh) | Portable POSIX Bash script with terminal status outputs. |
| **Windows (PowerShell)** | [`config/push-clean/push-clean.ps1`](file:///d:/projects/cb/config/push-clean/push-clean.ps1) | Native PowerShell script (PowerShell 5.1 & PowerShell Core 7+). |
| **Windows (CMD / Batch)** | [`config/push-clean/push-clean.bat`](file:///d:/projects/cb/config/push-clean/push-clean.bat) | Classic Command Prompt script (can be double-clicked or called via CMD). |

---

## 💻 How to Use

### 1. Linux & macOS (`bash`)

```bash
# Make script executable (first time only)
chmod +x ./push-clean/push-clean.sh

# Run with custom commit message:
./push-clean/push-clean.sh "Production release v1.0"

# Or run with default timestamped message:
./push-clean/push-clean.sh
```

---

### 2. Windows (`PowerShell`)

```powershell
# If you are inside the config folder:
.\push-clean\push-clean.ps1 "Production release v1.0"

# Or run with default timestamped message:
.\push-clean\push-clean.ps1
```

> **Note**: If your PowerShell execution policy blocks local scripts, run:
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
> ```

---

### 3. Windows (`CMD` / Command Prompt)

```cmd
:: If you are inside the config folder:
push-clean\push-clean.bat "Production release v1.0"

:: Or run with default timestamped message:
push-clean\push-clean.bat
```

---

## ⚙️ How It Works Under The Hood

1. **Safety Pre-Check**: Checks if `config.yml` contains sample placeholders (`AAAA`, `your_access_key`) or alerts if private credentials might be present.
2. **Orphan Branch**: Creates a standalone orphan branch with no ancestors:
   ```bash
   git checkout --orphan temp-orphan-<id>
   ```
3. **Stage & Commit**: Stages current tracked/untracked files and creates 1 commit:
   ```bash
   git add -A
   git commit -m "<Commit Message>"
   ```
4. **Branch Replacement**: Deletes old local `main` pointer and renames orphan to `main`:
   ```bash
   git branch -D main
   git branch -m main
   ```
5. **Force Push**: Overwrites the remote GitHub branch:
   ```bash
   git push -f origin main
   ```

---

## 🔒 Security Best Practice Checklist Before Pushing

- [ ] Ensure `.gitignore` ignores sensitive logs, cache files, and private keys (`*.pem`, `*.key`).
- [ ] Ensure `config.yml` contains template dummy credentials (never live VPS secrets).
- [ ] All live production secrets should be set directly on the VPS or via GitHub Repository Secrets.
