# LEMP Stack Installer

One-command LEMP stack installer for Ubuntu 22.04 and 24.04. Sets up a production-ready web server with WordPress support, admin tools, and security hardening — no control panel required.

## What's Included

| Component | Version | Details |
|-----------|---------|---------|
| **Nginx** | Mainline (from nginx.org) | Vhosts, security headers, rate limiting, gzip |
| **MariaDB** | 11.4 | Secured root, InnoDB tuning, per-domain databases |
| **PHP** | 8.4 | 17 extensions, FPM tuned for production |
| **Redis** | Latest | Server + PHP extension |
| **Memcached** | Latest | Server + PHP extension (localhost-only) |
| **Composer** | Latest | SHA384 checksum verified |
| **Node.js** | 22 LTS | Via NodeSource |
| **Certbot** | Latest | Nginx plugin, auto-renewal via timer |
| **phpMyAdmin** | Latest | Randomized URL path for security |
| **File Browser** | Latest | Randomized URL path, WebSocket support |
| **fail2ban** | Latest | SSH + nginx jails |
| **UFW** | Built-in | SSH (auto-detected port) + 80 + 443 only |
| **Unattended Upgrades** | Built-in | Automatic security patches |
| **Swap** | Conditional | Created only if RAM < 4 GB |

## Quick Start

**On a fresh Ubuntu 22.04 or 24.04 server:**

```bash
curl -fsSL https://raw.githubusercontent.com/dathc0601/lemp-stack-installer/main/server-setup/bootstrap.sh | sudo bash
```

The installer will prompt you for:
1. **MariaDB root password** — press Enter to auto-generate (recommended)
2. **File Browser password** — press Enter to auto-generate (recommended)
3. **Domains** — enter one per line, empty line to finish

Everything else is automatic. Credentials are saved to `/root/.server-credentials` (mode 600).

### After Installation

Issue SSL certificates for your domains:

```bash
sudo certbot --nginx -d example.com -d www.example.com
```

## Day-2 Management

The installer creates two commands for ongoing server management:

### `lemp` — interactive menu (recommended)

Just type `lemp` and pick from a numbered menu — no commands to memorize:

```bash
sudo lemp
```

```
═══════════════════════════════════════════════════════════
             LEMP Stack Manager v2.1.0-dev
                Ubuntu 24.04
───────────────────────────────────────────────────────────
Status: OK | Disk: 2.7/25 GB | RAM: 139/821 MB | Swap: 120/1024 MB
───────────────────────────────────────────────────────────

  1) Manage sites              (domains, backups)
  2) Manage databases          (list, info, add, delete, import, export)
  3) Manage SSL                (issue, renew, remove certificates)
  4) Manage SSH/SFTP           (port, passwords, fail2ban)
  5) Manage admin apps         (users, paths, auth retries)
  6) Manage cache              (Redis, Memcached, OPcache)
  7) Manage swap               (view, add, remove /swapfile)
  8) Manage PHP                (php.ini, pool, version)
  9) Manage web applications   (install WordPress, Laravel)
 10) Server status             (services, disk, memory, SSL)

  0) Exit

─// Enter your choice (0-10) [Ctrl+C=Exit]:
```

Picking **Manage sites** opens a sub-menu with all site/domain actions:

```
───────────────────────────────────────────────────────────
  » 1. Manage sites
───────────────────────────────────────────────────────────

  1) List sites                (configured domains + SSL)
  2) Add domain                (vhost + database)
  3) Remove domain
  4) Backup                    (all domains or one)
  5) Restore                   (from backup path)

  0) Back to main menu
```

Picking **Manage databases** opens a sub-menu for day-2 MariaDB operations — separate from the per-domain databases created by `add-domain`. Use this for standalone databases (staging copies, manual apps), rotating a DB user's password, surgically exporting one DB to `.sql.gz`, or importing a dump into an existing DB. A live status header shows MariaDB version, service state, and the total DB count/size. Deleting a DB that's linked to a configured domain warns loudly first.

```
───────────────────────────────────────────────────────────
  » 2. Manage databases
───────────────────────────────────────────────────────────

  MariaDB: 10.11.6 — active
  Databases: 4 user DBs, 58.3 MB total

  1) List databases              (name, size, tables, linked domain)
  2) Database info               (detailed: charset, users, last export)
  3) Add database                (create DB + user + password)
  4) Change DB user password     (rotate password for a DB user)
  5) Delete database             (drop DB + user + credentials block)
  6) Import database             (load .sql/.sql.gz into existing DB)
  7) Export database             (dump DB to /var/backups/databases/*.sql.gz)

  0) Back to main menu
```

Picking **Manage SSL** opens a sub-menu with Let's Encrypt actions. Each action that needs a domain shows a numbered picker filtered by SSL state — pick `2) Issue SSL` and you'll only see domains that don't yet have a certificate:

```
───────────────────────────────────────────────────────────
  » 3. Manage SSL
───────────────────────────────────────────────────────────

  1) List SSL certificates     (domains with/without SSL, expiry)
  2) Issue SSL                 (Let's Encrypt via certbot)
  3) Remove SSL                (delete certificate)
  4) Renew SSL                 (force renewal for one, or check all)

  0) Back to main menu
```

Picking **Manage SSH/SFTP** opens a sub-menu for server access hardening. The SSH port change uses a two-phase safety gate: the new port is opened alongside the old one, and you're prompted to verify a test login from a separate terminal *before* the old port is closed — so a typo'd port or firewall misconfig won't lock you out.

```
───────────────────────────────────────────────────────────
  » 4. Manage SSH/SFTP
───────────────────────────────────────────────────────────

  1) Change SSH port           (sshd drop-in + UFW + fail2ban)
  2) Change root password      (root SSH/console login)
  3) Change user password      (passwd for a Linux user)
  4) fail2ban max retries      (failed logins before ban)

  0) Back to main menu
```

Picking **Manage admin apps** opens a sub-menu for the installer's admin tools — phpMyAdmin (HTTP basic-auth wrapper + path obscurity) and File Browser (native user DB). Every user operation asks which app to target, so the two identity stores stay independent. The default `admin` user and a 24-char random password are created at install time and written to `/root/.server-credentials`.

```
───────────────────────────────────────────────────────────
  » 5. Manage admin apps
───────────────────────────────────────────────────────────

  1) Change admin paths        (rotate /pma-<hex> and /files-<hex>)
  2) List admin users          (phpMyAdmin + File Browser)
  3) Add admin user            (pick app, username, password)
  4) Change admin password     (pick app, user, new password)
  5) Delete admin user         (pick app, user)
  6) Auth login retries        (fail2ban [nginx-http-auth] maxretry)

  0) Back to main menu
```

Picking **Manage cache** opens a sub-menu for the three cache layers the stack exposes to application code — **Redis** (object cache / sessions), **Memcached** (session / object cache), and **Zend OPcache** (PHP bytecode). The sub-menu shows a live status header (active/inactive/enabled) so you know the current state before picking an action. Toggling a service is a true on/off (saves RAM on tiny VPSes); "Reset OPcache" reloads PHP-FPM to flush compiled bytecode without disabling the extension.

```
───────────────────────────────────────────────────────────
  » 6. Manage cache
───────────────────────────────────────────────────────────

  Status:
    Redis      : active
    Memcached  : active
    OPcache    : enabled (FPM)

  1) Toggle Redis              (enable/disable redis-server)
  2) Toggle Memcached          (enable/disable memcached)
  3) Toggle OPcache            (opcache.enable in php.ini)
  4) Reset OPcache             (reload FPM to flush bytecode)
  5) Clear all caches          (flush Redis + Memcached + OPcache)

  0) Back to main menu
```

Picking **Manage swap** opens a sub-menu for managing the `/swapfile` backing store — the same file the installer creates when RAM < 4 GB. Use this to add swap on a VPS that started without it, resize an existing swap (remove → add), or remove swap entirely. The sub-menu shows a live status header with current swap size/usage, swappiness, and available RAM. `Add swap` refuses to clobber an already-active file — it's resize-via-remove-first, which avoids partial states. `Remove swap` warns loudly when used swap exceeds available RAM (where `swapoff` is likely to OOM).

```
───────────────────────────────────────────────────────────
  » 7. Manage swap
───────────────────────────────────────────────────────────

  Swap: /swapfile (2.0G file, 167M used, prio -2) — active
  Swappiness: 10, vfs_cache_pressure: 100
  Memory: 3.8G total, 2.1G available

  1) View swap                 (detailed swapon + fstab + sysctl)
  2) Add swap                  (create /swapfile, fstab entry, swappiness)
  3) Remove swap               (swapoff, delete /swapfile, clean fstab)

  0) Back to main menu
```

Picking **Manage PHP** opens a sub-menu for PHP runtime tuning and version management — php.ini directives, FPM pool sizing, and switching to a different PHP minor version without a full reinstall. A live status header shows the active version, FPM service state, the six most impactful php.ini values, and the shared pool configuration. `Change PHP version` installs the target version from `ppa:ondrej/php`, copies the user's current ini + pool tuning forward, rewrites every vhost's `fastcgi_pass` socket path, and reloads nginx — old packages are left installed so rollback is one more `php-version` call away. Per-domain pools and per-domain PHP versions are intentionally out of scope (the stack uses a single shared FPM pool).

```
───────────────────────────────────────────────────────────
  » 8. Manage PHP
───────────────────────────────────────────────────────────

  PHP: 8.4.11 (active) — php8.4-fpm: active
  php.ini: memory_limit=512M, upload=256M, exec=600, tz=UTC
  Pool www.conf: pm=dynamic, max_children=20, start=4, spare=2-6

  1) PHP.ini config            (memory, upload, post, exec-time, input-vars, timezone)
  2) PHP pool config           (pm mode, worker counts — shared www pool)
  3) Change PHP version        (install + switch active version, regenerate vhosts)

  0) Back to main menu
```

Picking **Manage web applications** opens a sub-menu for deploying content frameworks onto any existing domain — **WordPress** (CMS, ~40% of the web) or **Laravel** (PHP framework, artisan/eloquent stack). Both actions ask which domain to install onto via a numbered picker. The status header shows how many domains already have an app installed vs raw (nginx-only) and the active Composer/PHP versions. WordPress uses WP-CLI when present, falling back to a curl tarball + `wp-config.php` sed. Laravel runs `composer create-project laravel/laravel`, writes `.env` with the domain's DB credentials, generates `APP_KEY`, and rewrites the vhost's `root` directive to `<site_root>/public` (Laravel's document root) before reloading nginx. Composer is not pinned to a specific Laravel version — it auto-resolves the highest release compatible with the active PHP (Laravel 11 needs PHP 8.2+; 10 works on 8.1), so you can keep a legacy-PHP domain on Laravel 10 by switching PHP first via `Manage PHP → Change version`.

```
───────────────────────────────────────────────────────────
  » 9. Manage web applications
───────────────────────────────────────────────────────────

  Apps: 2 WordPress, 1 Laravel — 3 of 5 domains
  Composer: 2.7.9 — PHP: 8.4.11

  1) Install WordPress         (on an existing domain)
  2) Install Laravel           (on an existing domain)

  0) Back to main menu
```

The menu prompts for any required arguments (domain name, backup path, etc.) and returns to the appropriate menu after each action.

### `lemp-manage` — CLI (for scripting / automation)

Same functionality, non-interactive:

```bash
# Sites
sudo lemp-manage status                              # Service status, disk, memory, SSL expiry
sudo lemp-manage list-sites                          # List all configured domains
sudo lemp-manage add-domain example.com              # Add a domain (vhost + database)
sudo lemp-manage remove-domain example.com           # Remove a domain
sudo lemp-manage backup                              # Backup all domains
sudo lemp-manage backup example.com                  # Backup a single domain
sudo lemp-manage restore /var/backups/server-setup/2025-01-15/example.com example.com

# SSL (Let's Encrypt)
sudo lemp-manage ssl-list                            # List certs + expiry for every domain
sudo lemp-manage ssl-issue example.com               # Issue a cert (auto-includes www.example.com if in vhost)
sudo lemp-manage ssl-remove example.com              # Delete cert; prompts to regenerate vhost
sudo lemp-manage ssl-renew example.com               # Force-renew one cert
sudo lemp-manage ssl-renew                           # Renew-check all certs (only near-expiry ones renew)

# SSH / SFTP
sudo lemp-manage ssh-port                            # Change SSH port (interactive, two-phase safety gate)
sudo lemp-manage ssh-port 2222                       # Same, pre-seeded new port
sudo lemp-manage ssh-root-password                   # Change the root password (silent prompt, min 12 chars)
sudo lemp-manage sftp-user-password deploy           # Change an existing user's password
sudo lemp-manage fail2ban-maxretry 3                 # Set fail2ban [DEFAULT] maxretry (1-20)

# Admin apps (phpMyAdmin + File Browser)
sudo lemp-manage appadmin-list                       # List admin users for both apps
sudo lemp-manage appadmin-add pma alice              # Add 'alice' to phpMyAdmin basic-auth
sudo lemp-manage appadmin-add fb bob                 # Add 'bob' to File Browser
sudo lemp-manage appadmin-password pma alice         # Change alice's phpMyAdmin password
sudo lemp-manage appadmin-remove pma alice           # Remove alice (refuses if last user)
sudo lemp-manage appadmin-paths                      # Rotate /pma-<hex> and /files-<hex>
sudo lemp-manage appadmin-maxretry 3                 # Tune [nginx-http-auth] maxretry (1-20)

# Cache (Redis, Memcached, OPcache)
sudo lemp-manage cache-redis-toggle                  # Flip Redis service state
sudo lemp-manage cache-redis-toggle off              # Stop + disable at boot
sudo lemp-manage cache-memcached-toggle on           # Start + enable at boot
sudo lemp-manage cache-opcache-toggle                # Flip OPcache (edits FPM + CLI php.ini, reloads FPM)
sudo lemp-manage cache-opcache-reset                 # Flush compiled bytecode (reloads php-fpm)
sudo lemp-manage cache-clear                         # Flush Redis + Memcached + reset OPcache

# Databases (standalone DB management — separate from domain-linked DBs)
sudo lemp-manage db-list                             # List user DBs (size, tables, domain link)
sudo lemp-manage db-info staging_copy                # Show charset, users, last export, size
sudo lemp-manage db-add staging_copy                 # Create DB + user + password; writes [db:...] block
sudo lemp-manage db-user-password staging_copy       # Rotate the DB user's password
sudo lemp-manage db-remove staging_copy              # Drop DB + dedicated users + credentials block
sudo lemp-manage db-export staging_copy              # Dump to /var/backups/databases/*.sql.gz
sudo lemp-manage db-import /path/to/dump.sql.gz staging_copy

# Swap (manage /swapfile — day-2 counterpart to the install-time swap module)
sudo lemp-manage swap-view                           # Show swapon + fstab + sysctl + free
sudo lemp-manage swap-add                            # Create /swapfile (prompts for size)
sudo lemp-manage swap-add 2G                         # Non-interactive: 2 GB swap file
sudo lemp-manage swap-remove                         # swapoff + delete + clean fstab

# PHP (runtime + version management — day-2 counterpart to modules/40-php.sh)
sudo lemp-manage php-config                          # Edit memory_limit, upload, timezone, ... (interactive)
sudo lemp-manage php-pool                            # Tune shared FPM pool (pm mode, max_children, ...)
sudo lemp-manage php-version                         # Pick target version from a numbered list
sudo lemp-manage php-version 8.3                     # Non-interactive: switch to 8.3 (installs if needed)

# Web apps (deploy a CMS or framework onto an existing domain)
sudo lemp-manage wp-install example.com              # Install WordPress (WP-CLI preferred, curl fallback)
sudo lemp-manage laravel-install example.com         # composer create-project laravel/laravel + .env + vhost rewrite
```

## Security

- **No default passwords** — empty input generates 24+ char random passwords
- **Credentials stored in `/root/.server-credentials`** (mode 600), never echoed to stdout
- **phpMyAdmin and File Browser use randomized URL paths** (`/pma-<hex>`, `/files-<hex>`)
- **Default catch-all vhost returns 444** — admin tools unreachable via IP or unknown hostnames
- **Security headers** on every vhost (HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)
- **Rate limiting** on `wp-login.php`, phpMyAdmin, and File Browser endpoints
- **SSH port auto-detected** — supports `/etc/ssh/sshd_config.d/*.conf` drop-ins (Ubuntu 24.04)
- **`expose_php = Off`**, **`server_tokens off`** — no version leaks
- **fail2ban** protects SSH and nginx against brute-force attacks
- **Automatic security updates** via unattended-upgrades

## Project Structure

```
server-setup/
├── install.sh                 # Entry point
├── bootstrap.sh               # curl-pipe remote installer
├── manage.sh                  # Day-2 ops dispatcher
├── lib/
│   ├── core.sh                # Constants, logging, traps, FD setup
│   ├── utils.sh               # Password generation, apt wrappers, template engine
│   ├── preflight.sh           # OS detection, root check, SSH port detection
│   ├── input.sh               # Interactive prompts
│   ├── credentials.sh         # Credentials file management
│   └── state.sh               # Installation state tracking
├── modules/
│   ├── 10-base.sh             # Base system packages
│   ├── 20-nginx.sh            # Nginx mainline
│   ├── 25-firewall.sh         # UFW firewall
│   ├── 30-mariadb.sh          # MariaDB
│   ├── 40-php.sh              # PHP 8.4 + FPM
│   ├── 45-redis.sh            # Redis server
│   ├── 45a-memcached.sh       # Memcached server + php-memcached
│   ├── 50-composer.sh         # Composer
│   ├── 55-nodejs.sh           # Node.js
│   ├── 60-certbot.sh          # Certbot
│   ├── 70-phpmyadmin.sh       # phpMyAdmin
│   ├── 75-filebrowser.sh      # File Browser
│   ├── 80-fail2ban.sh         # fail2ban
│   ├── 85-unattended-upgrades.sh  # Auto security updates
│   ├── 90-swap.sh             # Conditional swap
│   ├── 95-domains.sh          # Nginx vhosts
│   └── 99-databases.sh        # Per-domain databases
├── manage/
│   ├── _menu.sh              # Interactive TUI shown by `lemp`
│   ├── add-domain.sh
│   ├── remove-domain.sh
│   ├── list-sites.sh
│   ├── backup.sh
│   ├── restore.sh
│   ├── wp-install.sh
│   ├── laravel-install.sh
│   ├── ssl-list.sh
│   ├── ssl-issue.sh
│   ├── ssl-remove.sh
│   ├── ssl-renew.sh
│   ├── ssh-port.sh
│   ├── ssh-root-password.sh
│   ├── sftp-user-password.sh
│   ├── fail2ban-maxretry.sh
│   ├── appadmin-list.sh
│   ├── appadmin-add.sh
│   ├── appadmin-password.sh
│   ├── appadmin-remove.sh
│   ├── appadmin-paths.sh
│   ├── appadmin-maxretry.sh
│   ├── cache-redis-toggle.sh
│   ├── cache-memcached-toggle.sh
│   ├── cache-opcache-toggle.sh
│   ├── cache-opcache-reset.sh
│   ├── cache-clear.sh
│   ├── db-list.sh
│   ├── db-info.sh
│   ├── db-add.sh
│   ├── db-user-password.sh
│   ├── db-remove.sh
│   ├── db-import.sh
│   ├── db-export.sh
│   ├── swap-view.sh
│   ├── swap-add.sh
│   ├── swap-remove.sh
│   ├── php-config.sh
│   ├── php-pool.sh
│   ├── php-version.sh
│   └── status.sh
├── templates/                 # Nginx/systemd/PHP configs with {{PLACEHOLDER}} markers
└── tests/
    └── test-modules.sh        # Module contract verifier
```

## Idempotency

The installer tracks which modules have been installed in `/var/lib/server-setup/state`. Re-running the bootstrap command updates the installer and skips already-completed modules:

```bash
# Safe to re-run — updates the installer, skips installed modules
curl -fsSL https://raw.githubusercontent.com/dathc0601/lemp-stack-installer/main/server-setup/bootstrap.sh | sudo bash
```

## Requirements

- **Ubuntu 22.04 or 24.04** (other distros are not supported)
- **Root access** (the script must run as root)
- **Fresh server recommended** — re-running on an existing server will skip installed modules but may overwrite credentials

## Manual Installation

If you prefer not to pipe to bash:

```bash
git clone https://github.com/dathc0601/lemp-stack-installer.git /opt/server-setup
cd /opt/server-setup/server-setup
sudo bash install.sh
```

## License

MIT — see [LICENSE](LICENSE) for details.
