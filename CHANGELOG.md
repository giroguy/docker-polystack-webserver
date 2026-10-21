# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/): **major** for changes that need action on existing servers, **minor** for new features, **patch** for fixes.

## [2.0.0] - 2026-10-21

**Breaking:** `php-fpm` no longer loads `.env`, so a `wp-config.php` that reads its database login with `getenv('MYSQL_USER')` / `getenv('MYSQL_PASSWORD')` stops working. Follow [Upgrading from 1.x](#upgrading-from-1x) **before** pulling this release onto an existing server.

### Security
- PHP pinned to `php:8.2.35-fpm-alpine`, which fixes php2shell (CVE-2026-109618 and CVE-2026-109619, unauthenticated RCE in PHP-FPM). The Dockerfile now pins an exact patch release, so a rebuild can't silently stay on an unpatched image.
- `php.ini` sets `display_errors=Off`, `display_startup_errors=Off` and `log_errors=On`. Errors go to `docker logs php-fpm` instead of being printed into pages with server paths.
- `php-fpm` no longer gets the server's `.env`, so a compromised WordPress site can't read the MySQL root password, the Redis password or the session secrets.
- The WordPress nginx template refuses to run any `.php` file under `wp-content/uploads` (blocks uploaded backdoors).

### Changed
- Each WordPress site now gets its own MySQL user with access to its own database only. The shared `wordpress` user is gone from `mysql/init/01-create-databases.sql`, and `MYSQL_USER` / `MYSQL_PASSWORD` are gone from `.env.example`.
- README → WordPress: per-site database users, a `wp-config.php` with the site's own login, `DISALLOW_FILE_EDIT` and `FORCE_SSL_ADMIN`, file ownership so PHP can write only to `uploads`, and plugin and core updates through wp-cli.

### Added
- README → **Updating PHP**: how to bump the pinned version, how to build the image on another machine when the server is small (1–2 GB), and why nginx must be reloaded after recreating `php-fpm` or `node`.

### Upgrading from 1.x

Do these steps in order. Steps 1 and 2 work on 1.x, so the sites stay up throughout.

1. **Create a MySQL user for each WordPress site.** Generate a password with `openssl rand -hex 24` and save it in your password manager:
   ```bash
   docker exec -it mysql mysql -u root -p -e "CREATE USER 'myblog_wp'@'%' IDENTIFIED BY 'PASTE_PASSWORD'; GRANT ALL ON myblog.* TO 'myblog_wp'@'%'; FLUSH PRIVILEGES;"
   ```
2. **Change each site's `wp-config.php`** from `getenv(...)` to that site's literal login (`DB_USER` and `DB_PASSWORD`). Reload a page on each site to confirm it still connects.
3. **Pull v2.0.0 and rebuild the PHP image.** On a small server, build on another machine and copy the image across, as described in README → Updating PHP.
4. **Recreate `php-fpm` without `.env`, then reload nginx:**
   ```bash
   docker compose up -d --no-build --no-deps php-fpm
   docker exec nginx nginx -t && docker exec nginx nginx -s reload
   docker exec php-fpm sh -c 'env | cut -d= -f1'   # should list no MYSQL_/REDIS_/SESSION_ names
   ```
5. **Set file ownership** for each site (see README → WordPress, step 4).
6. **Protect existing sites.** The template change only affects sites created from now on. Add this line above `location ~ \.php$ {` in each existing WordPress vhost in `nginx/conf.d/`, then run `nginx -t` and reload:
   ```nginx
   location ~* ^/wp-content/uploads/.*\.php$ { deny all; }
   ```
7. **Optional cleanup:** once no site uses it, `DROP USER 'wordpress'@'%';`, and remove `MYSQL_USER` and `MYSQL_PASSWORD` from `.env`.

## [1.1] - 2026-08-11

### Added
- nginx reloads itself when certbot renews a certificate. Certbot's deploy hook touches a sentinel file (`.renewed`) on the shared webroot; nginx checks it every 5 minutes and runs `nginx -s reload` when it changes. No container restart, and no Docker socket for certbot.

### Fixed
- The example vhost is shipped as `example-static.conf.txt`, so nginx doesn't load it on a fresh start.

### Documentation
- README clone URL points at the real repository.

## [1.0] - 2026-05-08

### Added
- First release. A Docker Compose stack for running static, React/Vite, WordPress, Node.js and Go sites on one VPS: nginx, PHP-FPM, MySQL 8, Node 20 + PM2, Redis, SFTP and certbot.
- The `./site` CLI for adding, removing and listing sites, with Let's Encrypt SSL.
- GitHub Actions deploy templates, and a nightly MySQL backup script.

[2.0.0]: https://github.com/giroguy/docker-polystack-webserver/compare/v1.1...v2.0.0
[1.1]: https://github.com/giroguy/docker-polystack-webserver/compare/v1.0...v1.1
[1.0]: https://github.com/giroguy/docker-polystack-webserver/releases/tag/v1.0
