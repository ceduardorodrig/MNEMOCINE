---
tags: [homelab, service, miracena, stack, docker, n8n, wordpress, kuaray]
pending: [HB-091, HB-092]
---

# Miracena - Infrastructure Stack

**Server:** Kuaray (Dell Inspiron 14R — migrated on 04/10/2026 to relieve RAM pressure on Kavure)  
**Initial Deployment Date:** 10/09/2026 (Kavure) · **Kuaray Migration:** 04/10/2026  
**Canonical Project & Governance:** Miracena (Temporary homelab incubation)  
**Environment:** Kuaray node (dedicated isolated Docker Compose instance)  

> **02/11/2026:** the Nuxt dashboard (`miracena-nuxt`) was retired and deleted; `miracena-redis` was removed and its data deleted.

> **31/10/2026 — Previous platform retired.** Its data was migrated to the Frappe platform (counts and sums reconciled) and its
> service was removed from this Compose file. Rollback material is kept until **2026-11-30** (HB-093): two Docker volumes, an env
> file, extension sources and a final dump + export under `offbox/archive/`. Exact names are in the HB-093 backlog item.

## Deployed Stack

| Service | Container | Port | Image | RAM Limit | CPU Limit |
|---|---|---|---|---|---|
| PostgreSQL | miracena-postgres | 5432 (internal) | postgres:16-alpine | 1 GB | 0.5 |


| Nginx Proxy Manager | miracena-nginx-proxy-manager | 81 (admin), 8180 (HTTP), 8445 (HTTPS) | jc21/nginx-proxy-manager:2.16.0 | 256 MB | 0.25 |
| WordPress | miracena-wordpress | 8085 | wordpress:6.6.2-php8.3-apache | 512 MB | 0.5 |
| MariaDB | miracena-mariadb | 3306 (internal) | mariadb:11 | 512 MB | 0.25 |
| n8n | miracena-n8n | 5678 | docker.n8n.io/n8nio/n8n:stable | 1 GB | 0.5 |
| Tailscale Tunnel (active since 2026-11-05: Funnel published for the platform) | miracena-tunnel | 443 | tailscale/tailscale:latest | 128 MB | 0.25 |
| StenioSentinel | miracena-stenio | 9099 | ghcr.io/ceduardorodrig/stenio-sentinel:4 | 128 MB | 0.25 |

## Access Routes

### External (Public Internet via Tailscale Funnel) — historical
> **Status (2026-11-05): active, and verified from outside.** The `miracena-tunnel` sidecar is up with `# Funnel on` serving `https://miracena.chimaera-heptatonic.ts.net` → NPM → Frappe. Verified the same day: `dig @8.8.8.8` returns the Tailscale relay addresses, `curl --resolve` to the relay returns 200 with a valid certificate for the name. The WordPress stack this entry exposed in the past was retired on 2026-10-31; today the destination is the Miracena platform. Rule for opening/closing: `HB-091` in the homelab backlog; Miracena side in [`clients/miracena/plataforma/public-access.md`](../../clients/miracena/plataforma/public-access.md). One caveat worth keeping: a `curl` without `--resolve` answers from MagicDNS inside the tailnet and does **not** test the Funnel.

- **Public Domain (historical):** `https://miracena.chimaera-heptatonic.ts.net/`
- **Architecture:** Tailscale Funnel (ephemeral node `miracena` with `tag:edge`) → `miracena-nginx-proxy-manager:80`.
- **WAF & Split-Horizon Protection:**
  - Public visitors can access public website assets and front-facing content.
  - `/wp-admin` and `/wp-login.php` are **blocked with HTTP 403 Forbidden** on the public Funnel URL.
  - `/xmlrpc.php` and configuration files (`wp-config.php`, `readme.html`) return **HTTP 404 Not Found**.
  - Administration is accessible **exclusively via internal Tailnet direct IP** (`http://kuaray.chimaera-heptatonic.ts.net:8085/` or `100.94.209.99:8085`).

### Internal (Tailnet Only)
- **WordPress Admin & Direct:** http://kuaray.chimaera-heptatonic.ts.net:8085 (bound strictly to `100.94.209.99:8085`)

- **n8n:** http://kuaray.chimaera-heptatonic.ts.net:5678
- **NPM Admin:** http://kuaray.chimaera-heptatonic.ts.net:81
- **StenioSentinel (MCP SSE / Audit / Semântica):** http://kuaray.chimaera-heptatonic.ts.net:9099 (bound strictly to `100.94.209.99:9099`)

### Hardening & Containment (Enforced 2026-10-29, HB-083 & HB-084)
1. **Network Egress Firewall (`hl-miracena-egress-guard.service`):**
   - Systemd unit on host `kuaray` enforcing `iptables -t mangle -I PREROUTING` rules.
   - Any traffic originating from container bridge subnet `172.22.0.0/16` directed to homelab LAN (`192.168.0.0/16`) or Tailnet (`100.64.0.0/10`) is unconditionally DROPPED. Outbound internet egress remains functional.
2. **Least-Privilege Secret Envs (HB-082 / HB-085):**
   - Containers no longer mount or inherit the master monolithic `.env`.
   - n8n mounts `/srv/data/miracena/env/n8n.env` (chmod 0600).
   - WordPress mounts `/srv/data/miracena/env/wordpress.env` (chmod 0600).
   - Tunnel mounts `/srv/data/miracena/env/tunnel.env` (chmod 0600).
   - Stenio mounts `/srv/data/miracena/env/stenio.env` (chmod 0600).
3. **WordPress Core & Application Hardening:**
   - Image pinned: `wordpress:6.6.2-php8.3-apache`.
   - PHP script execution permanently blocked in `/srv/data/miracena/wordpress/html/wp-content/uploads/.htaccess`.
   - Dashboard file editor permanently disabled via `define('DISALLOW_FILE_EDIT', true);` in `wp-config.php`.
   - High-risk plugins (`wp-file-manager`) banned by StênioSentinel (`SEC-WORDPRESS-BANNED-PLUGIN`).
   - Contaminated backups and compromised accounts permanently eradicated and isolated in quarantine.
4. **Redis Authentication:**
   - Historical: `miracena-redis` was removed on 2026-11-02 (unused, data deleted).

### Credentials

#### Nginx Proxy Manager
- **Email:** ceduadorodrig@gmail.com
- **Password:** (in `.env` — `NPM_ADMIN_PASSWORD` / SOPS store)
- **URL:** http://kuaray.chimaera-heptatonic.ts.net:81

#### n8n
- **User:** edu
- **Password:** (in `.env` — `N8N_BASIC_AUTH_PASSWORD`)
- **Status:** ✅ Configured (10/09/2026)

#### WordPress
- **Setup:** http://kuaray.chimaera-heptatonic.ts.net:8085 (initial login initializes admin user)
- **Status:** ⏳ Pending configuration

## PostgreSQL Instance

The `miracena-postgres` container now serves **n8n only** (database `n8n`, user `n8n`). A legacy `miracena` database from the
previous platform still exists on the instance and is still dumped by `miracena-backup` until HB-093 is completed (live check 02/11/2026).

**Rationale:** Memory-constrained environment (5.7 GB on Kuaray); a single database engine minimizes daemon overhead.

## Tailscale Funnel (historical)

> **Historical: disabled since 2026-10-29** (key revoked after the WordPress incident; the container is stopped and behind compose profile `tunnel`). Reopening is planned, see `HB-091` and [`clients/miracena/plataforma/public-access.md`](../../clients/miracena/plataforma/public-access.md). The design below (WordPress-era, port 443 to NPM) is kept as history and is not the current design.

The `miracena-tunnel` container attaches to the tailnet with hostname `miracena` and exposes NPM via Funnel on port 443.

**serve.json:**
```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://miracena-nginx-proxy-manager:80" } }
    }
  },
  "AllowFunnel": { "${TS_CERT_DOMAIN}:443": true }
}
```

**Tailscale MagicDNS Constraint:** Custom subdomains (`site.miracena.xxx`, `cms.miracena.xxx`) do not resolve automatically — DNS registers strictly the root node hostname (`miracena.chimaera-heptatonic.ts.net`). Internal tools (n8n) are reached via their mapped ports on `kuaray.chimaera-heptatonic.ts.net:{port}`.

## Directory Structure

```
/srv/data/miracena/
├── docker-compose.yml          # Core stack definition
├── .env                        # Decrypted secret configuration
├── postgres/                   # PostgreSQL data & init
│   └── init/                   # Multi-database init scripts
│       └── init-multiple-dbs.sh
├── nginx-proxy-manager/        # NPM data & certificates
│   ├── data/                   # NPM SQLite database
│   └── letsencrypt/            # SSL certificates
├── tailscale/                  # Tailscale tunnel state
│   └── serve.json              # Tailscale Funnel configuration
├── wordpress/                  # WordPress runtime
│   └── html/                   # WordPress core files
└── backups/                    # Local temporary backup staging
```

## Docker Network

```
miracena_default (172.x.x.x/16)
├── miracena-postgres


├── miracena-nginx-proxy-manager
├── miracena-wordpress
├── miracena-mariadb
├── miracena-n8n
├── miracena-tunnel
└── miracena-stenio
```

## Read-only agent account (2026-11-05)

The Frappe site has one machine account, created so an agent can verify a delivery without asking a person for
credentials. The account is `agente.leitura@miracena.com`, with role **Miracena Auditor** + Desk User: it reads,
it does not write.

- **API key, not password.** Frappe authenticates an API key per request (`frappe/auth.py:639`), so no session,
  cookie or TOTP is in the path of an API call. Use `scripts/miracena-api.sh <path>` in the vault.
- **Secrets live in the sops store** (`MIRACENA_AGENT_EMAIL`, `_PASSWORD`, `_API_KEY`, `_API_SECRET`,
  `_TOTP_SECRET`), never in the vault, never in a commit. The TOTP secret exists so a human flow can be completed
  if one is ever needed; the agent never types a code.
- **Visual gate.** For a screenshot, the same token goes into the browser session header
  (`cdp('Network.setExtraHTTPHeaders', {'Authorization': 'token <key>:<secret>'})`). The Desk renders the whole
  page; a "Session Expired" modal sits on top because the header path creates no session cookie — noise, not a
  page defect. Verified on `/desk/miracena/manual` at rc107.
- **Turn it off by disabling the User**; nothing else references the account.

## Management Commands

```bash
# Container status
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep miracena

# Service logs
docker logs miracena-wordpress -f
docker logs miracena-n8n -f
docker logs miracena-tunnel -f

# Restart stack
cd /srv/data/miracena && docker compose restart

# Stop stack
cd /srv/data/miracena && docker compose down

# Update images
cd /srv/data/miracena && docker compose pull && docker compose up -d

# Inspect Funnel status
docker exec miracena-tunnel tailscale funnel status

# Check Tailscale status
docker exec miracena-tunnel tailscale status
```

## Historical Ports on Kavure

| Port | Service | Notes |
|---|---|---|
| 80 | Pi-hole | — |
| 443 | Pi-hole | — |
| 81 | NPM Admin | — |
| 3000 | aiostreams | — |

| 8080 | SearXNG | — |
| 8085 | WordPress | — |
| 8180 | NPM HTTP | — |
| 8443 | aiostreams | — |
| 8444 | Crafty | — |
| 8445 | NPM HTTPS | — |
| 5678 | n8n | — |

## Automated Backups

### Strategy

| Component | Method | Frequency |
|---|---|---|
| PostgreSQL (`n8n` + legacy `miracena` database) | `pg_dump` → gzip | Daily at 05:35 BRT |
| MariaDB (WordPress) | `mariadb-dump` → gzip | Daily at 05:35 BRT |
| WordPress files | `rsync --delete` | Daily at 05:35 BRT |
| Legacy uploads volume of the previous platform (retention only, until 2026-11-30 — HB-093; the live script still copies it) | `cp -a` | Daily at 05:35 BRT |
| NPM configuration | `rsync --delete` | Daily at 05:35 BRT |
| Frappe platform site (DB + public/private files + site config) | `bench backup --with-files` → copied to `daily/frappe/` (7 days in the volume, 30 days on the NAS) | Daily at 05:35 BRT (added 31/10/2026; restore tested into a fresh site) |

### Storage & Schedule

- **NAS Target:** `/mnt/BACKUP/miracena-server-kavure/daily/` (psicopompo)
- **Mount Point:** `/srv/data/miracena/offbox` (NFS via autofs)
- **Timer:** `hl-miracena-backup.timer` (05:35 BRT, `Persistent=true`)
- **Script:** `/usr/local/bin/miracena-backup`
- **Health Stamp:** `/srv/health/miracena-backup-last-ok`
- **Log:** `/var/log/miracena-backup.log`
- **ntfy:** Posts to `/backup` on failure

### Recovery Commands

```bash
# Trigger manual backup
sudo /usr/local/bin/miracena-backup

# Check timer
systemctl list-timers hl-miracena-backup.timer

# View execution logs
journalctl -u hl-miracena-backup.service -f
cat /var/log/miracena-backup.log

# Restore the n8n PostgreSQL database
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-n8n-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n

# Restore MariaDB database
zcat /mnt/BACKUP/miracena-server-kavure/daily/mariadb-wordpress-YYYY-MM-DD.sql.gz | docker exec -i miracena-mariadb mariadb -u root -p"$MYSQL_ROOT_PASSWORD" wordpress
```

## Temporary evaluation containers (2026-10-30)

A separate Compose project (`miracena-frappe`, folder `/srv/data/miracena/frappe/`) runs the client's **platform** (promoted from
evaluation on 31/10/2026). It uses an immutable custom image with the client's app baked in, publishes a single **loopback** port
(`127.0.0.1:8081`, reach it with `ssh -L 8081:127.0.0.1:8081 kuaray`), has per-container memory limits (about 2.7 GB in
total), healthchecks on every service and the highest OOM score so the kernel kills it first if memory runs short. It has its
own network and no link to the stack above. A one-shot `migrate` service gates the backend on every deploy. Its definition,
runbook (deploy, backup, restore) and decision record live in the client's private repository; the daily backup is part of
`miracena-backup` (above). Access: a tailnet-only HTTPS proxy (`tailscale serve --bg --https=8446 http://127.0.0.1:8081`, undo `tailscale serve --https=8446 off`) makes it reachable from tailnet devices at `https://kuaray.chimaera-heptatonic.ts.net:8446`; it is **not** Funnel (nothing is exposed to the internet). Follow-ups: HB-092.
