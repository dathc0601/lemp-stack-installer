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

  1) Manage sites              (domains, backups, WordPress)
  2) Manage SSL                (issue, renew, remove certificates)
  3) Manage SSH/SFTP           (port, passwords, fail2ban)
  4) Manage admin apps         (users, paths, auth retries)
  5) Manage cache              (Redis, Memcached, OPcache)
  6) Server status             (services, disk, memory, SSL)

  0) Exit

─// Enter your choice (0-6) [Ctrl+C=Exit]:
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
  6) Install WordPress         (on a domain)

  0) Back to main menu
```

Picking **Manage SSL** opens a sub-menu with Let's Encrypt actions. Each action that needs a domain shows a numbered picker filtered by SSL state — pick `2) Issue SSL` and you'll only see domains that don't yet have a certificate:

```
───────────────────────────────────────────────────────────
  » 2. Manage SSL
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
  » 3. Manage SSH/SFTP
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
  » 4. Manage admin apps
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
  » 5. Manage cache
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
sudo lemp-manage wp-install example.com              # Install WordPress on a domain

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
