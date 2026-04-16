# LEMP Stack Installer

One-command LEMP stack installer for Ubuntu 22.04 and 24.04. Sets up a production-ready web server with WordPress support, admin tools, and security hardening — no control panel required.

## What's Included

| Component | Version | Details |
|-----------|---------|---------|
| **Nginx** | Mainline (from nginx.org) | Vhosts, security headers, rate limiting, gzip |
| **MariaDB** | 11.4 | Secured root, InnoDB tuning, per-domain databases |
| **PHP** | 8.4 | 17 extensions, FPM tuned for production |
| **Redis** | Latest | Server + PHP extension |
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

The installer creates a `lemp-manage` command for ongoing server management:

```bash
lemp-manage status                              # Service status, disk, memory, SSL expiry
lemp-manage list-sites                           # List all configured domains
lemp-manage add-domain example.com               # Add a domain (vhost + database)
lemp-manage remove-domain example.com            # Remove a domain
lemp-manage backup                               # Backup all domains
lemp-manage backup example.com                   # Backup a single domain
lemp-manage restore /var/backups/server-setup/2025-01-15/example.com example.com
lemp-manage wp-install example.com               # Install WordPress on a domain
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
│   ├── add-domain.sh
│   ├── remove-domain.sh
│   ├── list-sites.sh
│   ├── backup.sh
│   ├── restore.sh
│   ├── wp-install.sh
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
