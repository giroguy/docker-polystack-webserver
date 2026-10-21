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

1. **Create the database and its own user.** Each site gets a MySQL user that can only reach its own database. Generate a password with `openssl rand -hex 24` and keep it in your password manager. Then run this, replacing `PASTE_PASSWORD`:

   ```bash
   docker exec -it mysql mysql -u root -p -e "CREATE DATABASE myblog CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER 'myblog_wp'@'%' IDENTIFIED BY 'PASTE_PASSWORD'; GRANT ALL ON myblog.* TO 'myblog_wp'@'%'; FLUSH PRIVILEGES;"
   ```

   Also add the `CREATE DATABASE` line (not the user or password) to `mysql/init/01-create-databases.sql`, so it's recreated if the volume ever is. A command with a password in it stays in your shell history, so remove it afterwards (for example with `history -d`).

2. **Deploy the WordPress files** to `wordpress/myblog/`.

3. **Write `wp-config.php` with the site's own login.** The `php-fpm` container gets no `.env`, so PHP can't read the server's other secrets:

   ```php
   define('DB_NAME',     'myblog');
   define('DB_USER',     'myblog_wp');
   define('DB_PASSWORD', 'the password from step 1');
   define('DB_HOST',     'mysql');
   define('WP_HOME',     'https://myblog.com');
   define('WP_SITEURL',  'https://myblog.com');

   define('DISALLOW_FILE_EDIT', true);   // no theme/plugin code editor in wp-admin
   define('FORCE_SSL_ADMIN',    true);
   ```

   Get fresh keys and salts from https://api.wordpress.org/secret-key/1.1/salt/.

4. **Set ownership so PHP can only write to uploads.** PHP runs as `www-data`, which is uid 82 in the alpine image:

   ```bash
   chown -R deploy:deploy wordpress/myblog
   find wordpress/myblog -type d -exec chmod 755 {} +
   find wordpress/myblog -type f -exec chmod 644 {} +
   chown -R 82:82 wordpress/myblog/wp-content/uploads
   chown deploy:82 wordpress/myblog/wp-config.php && chmod 640 wordpress/myblog/wp-config.php
   ```

   PHP can't modify the site's code, so even a compromised plugin can't plant files outside `uploads`. The nginx template also refuses to run any `.php` file under `wp-content/uploads`. The trade-off is that plugin and core updates from wp-admin won't work. Run them with wp-cli instead:

   ```bash
   docker exec php-fpm wp --path=/var/www/wordpress/myblog --allow-root plugin update --all
   docker exec php-fpm wp --path=/var/www/wordpress/myblog --allow-root core update
   ```

   wp-cli writes those files as root, so re-run the `chown` lines afterwards.

### Updating PHP

`php/Dockerfile` pins an exact patch release (for example `php:8.2.35-fpm-alpine`), so a rebuild never silently stays on an unpatched image. When PHP ships a security release, bump the tag and rebuild. If the new tag isn't on Docker Hub yet, the build fails loudly. Official images usually appear a few hours after the php.net release.

**On a 1–2 GB VPS, build the image on another machine.** Compiling the extensions (opcache in particular) can use all the memory on a small server with no swap, to the point where SSH stops responding. Build on your laptop and copy the image across:

```bash
# on your machine (add --platform linux/amd64 if it's Apple silicon and the server is x86)
docker build --platform linux/amd64 -t server-php-fpm ./php
docker save server-php-fpm | gzip | ssh root@YOUR_SERVER "gunzip | docker load"

# on the server. Compose expects the image to be called <project folder>-php-fpm,
# which is server-php-fpm if you cloned into /srv/server as in Quick Start.
docker compose up -d --no-build --no-deps php-fpm
docker exec nginx nginx -s reload
docker exec php-fpm php -v
```

**Reload nginx whenever you recreate `php-fpm` or `node`.** The vhosts use `fastcgi_pass php-fpm:9000` and `proxy_pass http://node:…` with no `resolver`, so nginx keeps the old container IP until it reloads, and the sites return 502 in the meantime. Also, `nginx -t` fails with "host not found in upstream" while `php-fpm` is stopped, so start it first.

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
