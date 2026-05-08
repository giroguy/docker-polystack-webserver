# docker-polystack-webserver

A production-ready Docker Compose stack for running **multiple sites and services of different types** on a single VPS — static HTML, React/Vite, WordPress, Node.js/Express, and Go services all managed from one place with a simple CLI.

## What Makes This Different

Most Docker setups handle one type of site. This handles them all:

| Type | Example | Served by |
|------|---------|-----------|
| Static HTML | marketing site | Nginx directly |
| React / Vite | SPA app | Nginx directly |
| WordPress | blog, CMS | Nginx + PHP-FPM |
| Node.js | Express API, OAuth service | PM2 in node container |
| Go service | SSE service, chat backend | PM2 (pre-built binary) |

## Stack

- **Nginx** — reverse proxy, SSL termination, static file serving
- **PHP-FPM** — shared across all WordPress sites
- **MySQL 8** — shared DB server, one database per WordPress site
- **Node 20 + PM2** — all Node.js and Go services in one container
- **Redis** — session/token storage for Node services
- **SFTP** — key-only file access on port 2222
- **Certbot** — automatic Let's Encrypt SSL renewal

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/giroguy/docker-polystack-webserver.git /srv/server
cd /srv/server
cp .env.example .env
nano .env   # fill in passwords
```

Generate secure passwords:
```bash
openssl rand -base64 32   # run once per password
```

### 2. Make scripts executable

```bash
chmod +x site scripts/backup.sh
```

### 3. Start the stack

```bash
docker compose up -d
docker compose ps   # verify all containers running
```

### 4. Add your first site

```bash
./site add --name mysite --domain mysite.com --type static
```

Then deploy your files to `static/mysite/` and run:

```bash
./site ssl --domain mysite.com --www
```

---

## The `./site` CLI

Manages sites without touching Docker or restarting containers.

```bash
./site add --name mysite --domain mysite.com --type static
./site add --name myapp  --domain myapp.com  --type react
./site add --name myblog --domain myblog.com --type wordpress
./site add --name myapi  --domain api.mysite.com --type node --port 3001
./site add --name myfull --domain myfull.com --type fullstack --port 3001

./site ssl --domain mysite.com         # Let's Encrypt cert
./site ssl --domain mysite.com --www   # includes www subdomain
./site remove --name mysite
./site list
```

**What it does:**
- Generates Nginx vhost from template
- Creates site directory (`static/<name>/` or `wordpress/<name>/`)
- Reloads Nginx with zero downtime
- Auto-updates the site registry (`.sites`)

**Note:** The `ssl` command only auto-updates nginx configs for sites managed via `./site add`. Hand-crafted configs (multi-service vhosts) are never touched automatically.

---

## Site Types

### Static HTML or React

```bash
./site add --name mysite --domain mysite.com --type static
# Deploy files to: static/mysite/
```

React apps (`--type react`) use `try_files` for client-side routing — same nginx config, just note your build output goes to `static/mysite/`.

### WordPress

```bash
./site add --name myblog --domain myblog.com --type wordpress
```

Then:
1. Create the database in `mysql/init/01-create-databases.sql` and restart MySQL
2. Deploy WordPress files to `wordpress/myblog/`
3. Configure `wp-config.php` to use `getenv()` for DB credentials:

```php
define('DB_NAME',     'myblog');
define('DB_USER',     getenv('MYSQL_USER'));
define('DB_PASSWORD', getenv('MYSQL_PASSWORD'));
define('DB_HOST',     'mysql');
define('WP_HOME',     'https://myblog.com');
define('WP_SITEURL',  'https://myblog.com');
```

### Node.js Service

1. Deploy service files to `node/<service-name>/`
2. Add entry to `node/ecosystem.config.js`
3. Install dependencies: `docker exec node sh -c "cd /app/<service-name> && npm install"`
4. Reload PM2: `docker exec node pm2 reload ecosystem.config.js --update-env`

### Go Service

1. Build binary on CI (GitHub Actions) with `CGO_ENABLED=0 GOOS=linux GOARCH=amd64`
2. Deploy binary to `go/<service-name>/`
3. Add entry to `node/ecosystem.config.js` with `interpreter: 'none'`

### Full-stack Vite + Express

```bash
./site add --name myapp --domain myapp.com --type fullstack --port 3001
```

Serves static frontend from `static/myapp/` and proxies `/api` to the Express service on the specified port. Vite dev proxy and Nginx both use `/api` — no code changes needed between environments.

---

## Directory Structure

```
docker-polystack-webserver/
├── docker-compose.yml
├── .env                          # secrets (not in git)
├── .env.example                  # template
├── site                          # CLI for managing sites
├── .sites                        # site registry (auto-managed)
├── nginx/
│   ├── conf.d/                   # vhost configs (one per site)
│   └── templates/                # templates used by ./site add
├── static/                       # static + React site files
├── wordpress/                    # WordPress site files
├── node/                         # Node/PM2 config
│   ├── Dockerfile                # node:20-alpine + Go + PM2
│   └── ecosystem.config.js       # PM2 app registry
├── go/                           # Go service binaries
├── php/                          # PHP-FPM config
├── mysql/
│   ├── init/                     # SQL files run on first boot
│   └── my.cnf                    # MySQL tuning for small VPS
├── sftp/
│   └── authorized_keys           # SFTP access (one key per line)
└── scripts/
    └── backup.sh                 # nightly DB backup via rsync
```

---

## GitHub Actions Deploy Templates

Copy the right template to each site repo as `.github/workflows/deploy.yml`:

| Template | Use for |
|----------|---------|
| `static-react-deploy.yml` | Static HTML or React/Vite sites |
| `wordpress-deploy.yml` | WordPress sites |
| `node-deploy.yml` | Node.js services |
| `fullstack-deploy.yml` | Full-stack Vite + Express |

All templates use **SCP** (not git pull) — works with private repos without needing GitHub SSH access configured on the deploy user.

### Required GitHub secrets/variables per repo

| Name | Type | Value |
|------|------|-------|
| `SSH_DEPLOY_KEY` | Secret | Deploy user private key |
| `SERVER_HOST` | Variable | Server IP address |

---

## SFTP Access

Add public keys to `sftp/authorized_keys` (one per line), then:

```bash
docker compose restart sftp
```

Connect: `sftp -P 2222 deploy@YOUR_SERVER_IP`

---

## Nightly Database Backup

Backs up all MySQL databases and rsyncs them to any SSH-accessible remote server (NAS, VPS, cloud storage with sshfs, etc.).

Edit `scripts/backup.sh` to set your remote host, user, path, and SSH key.

One-time setup:
```bash
ssh-keygen -t ed25519 -f /root/.ssh/nas_backup -N ""
cat /root/.ssh/nas_backup.pub   # add to NAS authorized_keys
```

Add cron job:
```bash
0 2 * * * /srv/server/scripts/backup.sh >> /var/log/backup.log 2>&1
```

---

## SSL

### Let's Encrypt (direct DNS)

```bash
./site ssl --domain mysite.com
./site ssl --domain mysite.com --www   # include www
```

### Cloudflare Origin Certificate (proxied domains)

1. Generate origin cert in Cloudflare dashboard
2. Drop `.pem` and `.key` into `nginx/ssl/`
3. Reference them in the vhost config

---

## MySQL Access via Sequel Ace / TablePlus

MySQL is exposed on `127.0.0.1:3306` (localhost only). Connect via SSH tunnel:

- **MySQL Host:** `127.0.0.1`
- **Port:** `3306`
- **SSH Host:** your server IP
- **SSH User:** `root`
- **SSH Key:** your local machine key

---

## Tested On

- Ubuntu 22.04 LTS
- Any VPS with 1GB+ RAM (DigitalOcean, Linode, Hetzner, Vultr, etc.)
- Docker 24+, Docker Compose v2

## License

MIT
