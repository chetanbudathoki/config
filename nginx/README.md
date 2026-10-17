# 🌐 Nginx Proxy Manager & Backup Module (`nginx/`)

The `nginx/` module is an independent installer that deploys **Nginx Proxy Manager (NPM)** and configures automated offsite backups to **Cloudflare R2 / S3**.

---

## 🏗️ Architecture

```
Internet (HTTP:80 / HTTPS:443 / Admin:81)
                  │
                  ▼
         [UFW Firewall + Docker]
                  │
                  ▼
       ┌───────────────────────┐
       │  Nginx Proxy Manager  │ (Runs in /home/$USER_NAME/nginx)
       └───────────┬───────────┘
                   │ (Internal Docker Network: proxy-network)
      ┌────────────┼────────────┐
      ▼            ▼            ▼
 ┌──────────┐ ┌──────────┐ ┌──────────┐
 │  App A   │ │  App B   │ │  App C   │ (Deployed via CI/CD in ~/project)
 └──────────┘ └──────────┘ └──────────┘
```

---

## 📂 Directory Layout

Nginx Proxy Manager is deployed in the service user's home directory:
```
/home/$USER_NAME/nginx/
├── docker-compose.yml
├── data/           # SQLite databases, proxy host configs, SSL keys
└── letsencrypt/    # SSL/TLS certificates and renew tokens
```

---

## 🗄️ Automated Weekly Offsite Backups

If S3 / Cloudflare R2 credentials are configured in `config.yml`, `nginx.sh`:
1. Installs `awscli` and configures root credentials in `/root/.aws/credentials`.
2. Generates `/usr/local/bin/backup-vps.sh`.
3. Detects server public IP and formats it as a slug (e.g. `192-0-2-1`).
4. Compresses `/home/$USER_NAME/nginx` and uploads snapshots to:
   ```text
   s3://<bucket>/<ip-slug>/<username>/nginx/nginx_<timestamp>.tar.gz
   ```
5. Schedules a weekly cron job on **Sunday at 02:00 AM**.

---

## ⚡ Usage

```bash
# From repository root:
chmod +x nginx/nginx.sh
sudo ./nginx/nginx.sh
```

---

## 🔗 Connecting CI/CD Applications to Nginx

Any app running in `~/project/<app>` connects to NPM through the external Docker network `proxy-network`:

```yaml
version: '3.8'

services:
  web:
    image: my-app:latest
    restart: always
    networks:
      - proxy-network

networks:
  proxy-network:
    external: true
```

In Nginx Proxy Manager Web Console (`http://<SERVER_IP>:81`):
1. **Forward Hostname**: `web` (use the Docker service name)
2. **Forward Port**: `3000` (internal container port)
3. **SSL**: Request Let's Encrypt with Force SSL.
