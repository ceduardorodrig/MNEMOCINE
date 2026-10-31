---
tags: [homelab, service, miracena, stack, docker, n8n, directus, wordpress, nuxt, kuaray]
pending: [HB-091, HB-092, HB-093]
---

# Miracena - Infrastructure Stack

**Server:** Kuaray (Dell Inspiron 14R — migrated on 04/10/2026 to relieve RAM pressure on Kavure)  
**Initial Deployment Date:** 10/09/2026 (Kavure) · **Kuaray Migration:** 04/10/2026  
**Canonical Project & Governance:** Miracena (Temporary homelab incubation)  
**Environment:** Kuaray node (dedicated isolated Docker Compose instance)  

> **31/10/2026 — Directus retired.** All data was migrated to the Frappe platform (counts and sums reconciled) and the
> `directus` service was removed from this Compose file. Rollback material kept until **2026-11-30** (HB-093): the volumes
> `miracena_directus_data` / `miracena_directus_database`, `env/directus.env`, and a final dump + export under
> `offbox/archive/directus-final-20261031/`. The Stênio daemon no longer depends on Directus. Sections below that describe
> Directus are historical.

## Deployed Stack

| Service | Container | Port | Image | RAM Limit | CPU Limit |
|---|---|---|---|---|---|
| PostgreSQL | miracena-postgres | 5432 (internal) | postgres:16-alpine | 1 GB | 0.5 |
| Redis | miracena-redis | 6379 (internal) | redis:7-alpine | 128 MB | 0.25 |
| ~~Directus~~ | ~~miracena-directus~~ | ~~8055~~ | **Retired 31/10/2026** (data migrated to the Frappe platform; volumes kept until 2026-11-30, HB-093) | — | — |
| Nuxt3 Frontend | miracena-nuxt | 3003 | node:22-alpine | 1 GB | 1.0 |
| Nginx Proxy Manager | miracena-nginx-proxy-manager | 81 (admin), 8180 (HTTP), 8445 (HTTPS) | jc21/nginx-proxy-manager:2.16.0 | 256 MB | 0.25 |
| WordPress | miracena-wordpress | 8085 | wordpress:6.6.2-php8.3-apache | 512 MB | 0.5 |
| MariaDB | miracena-mariadb | 3306 (internal) | mariadb:11 | 512 MB | 0.25 |
| n8n | miracena-n8n | 5678 | docker.n8n.io/n8nio/n8n:stable | 1 GB | 0.5 |
| Tailscale Tunnel | miracena-tunnel | 443 | tailscale/tailscale:latest | 128 MB | 0.25 |
| StenioSentinel | miracena-stenio | 9099 | ghcr.io/ceduardorodrig/stenio-sentinel:4 | 128 MB | 0.25 |

## Access Routes

### External (Public Internet via Tailscale Funnel)
- **Public Domain:** `https://miracena.chimaera-heptatonic.ts.net/`
- **Architecture:** Tailscale Funnel (ephemeral node `miracena` with `tag:edge`) → `miracena-nginx-proxy-manager:80`.
- **WAF & Split-Horizon Protection:**
  - Public visitors can access public website assets and front-facing content.
  - `/wp-admin` and `/wp-login.php` are **blocked with HTTP 403 Forbidden** on the public Funnel URL.
  - `/xmlrpc.php` and configuration files (`wp-config.php`, `readme.html`) return **HTTP 404 Not Found**.
  - Administration is accessible **exclusively via internal Tailnet direct IP** (`http://kuaray.chimaera-heptatonic.ts.net:8085/` or `100.94.209.99:8085`).

### Internal (Tailnet Only)
- **WordPress Admin & Direct:** http://kuaray.chimaera-heptatonic.ts.net:8085 (bound strictly to `100.94.209.99:8085`)
- **Nuxt3 Frontend:** http://kuaray.chimaera-heptatonic.ts.net:3003
- **Directus:** http://kuaray.chimaera-heptatonic.ts.net:8055
- **n8n:** http://kuaray.chimaera-heptatonic.ts.net:5678
- **NPM Admin:** http://kuaray.chimaera-heptatonic.ts.net:81
- **StenioSentinel (MCP SSE / Audit / Semântica):** http://kuaray.chimaera-heptatonic.ts.net:9099 (bound strictly to `100.94.209.99:9099`)

### Hardening & Containment (Enforced 2026-10-29, HB-083 & HB-084)
1. **Network Egress Firewall (`hl-miracena-egress-guard.service`):**
   - Systemd unit on host `kuaray` enforcing `iptables -t mangle -I PREROUTING` rules.
   - Any traffic originating from container bridge subnet `172.22.0.0/16` directed to homelab LAN (`192.168.0.0/16`) or Tailnet (`100.64.0.0/10`) is unconditionally DROPPED. Outbound internet egress remains functional.
2. **Least-Privilege Secret Envs (HB-082 / HB-085):**
   - Containers no longer mount or inherit the master monolithic `.env`.
   - Directus mounts `/srv/data/miracena/env/directus.env` (chmod 0600).
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
   - Command `--requirepass` enforced in `docker-compose.yml` with authenticated healthcheck (`redis-cli -a ... ping`).

### Credentials

#### Nginx Proxy Manager
- **Email:** ceduadorodrig@gmail.com
- **Password:** (in `.env` — `NPM_ADMIN_PASSWORD` / SOPS store)
- **URL:** http://kuaray.chimaera-heptatonic.ts.net:81

#### n8n
- **User:** edu
- **Password:** (in `.env` — `N8N_BASIC_AUTH_PASSWORD`)
- **Status:** ✅ Configured (10/09/2026)

#### Directus
- **Email:** ceduadorodrig@gmail.com
- **Password:** (in `.env` — `ADMIN_PASSWORD`)
- **Static Token:** in the SOPS store as `MIRACENA_DIRECTUS_TOKEN` (for API / CLI access) — retrieve with `/mnt/NVME_PCI/secrets/sops-decrypt.sh MIRACENA_DIRECTUS_TOKEN`; never inline the value in this note
- **Status:** ✅ Configured (10/09/2026)
- **Schema:** 21 collections, 28 relationships via direct SQL
- **Seed Data:** 6 members, 3 guilds, 3 cabals, 3 contacts, 2 squads, 3 projects, 2 deals, 4 tasks, 3 OKRs, 5 key results, 2 invoices, 1 payment, 3 assets, 2 peer reviews
- **Roles:** Admin (built-in), Member (full CRUD), Client (read-only), Public (assets/guilds/cabals)
- **Policies:** Miracena Member (full CRUD), Miracena Client (read-only), Miracena Public (read-only on assets)
- **Permissions:** 103 custom permissions (Member: CRUD across 23 collections, Client: read on 8 collections, Public: read on 3 collections)
- **Dashboards:** 4 dashboards (Overview, OKRs & Progress, Financial, Asset Bank) with 21 metric panels
- **Flows:** 3 active flows (New Member, Task Created, Proposal Created) — reached free tier limit

#### WordPress
- **Setup:** http://kuaray.chimaera-heptatonic.ts.net:8085 (initial login initializes admin user)
- **Status:** ⏳ Pending configuration

## Shared PostgreSQL Instance

A single PostgreSQL container (`miracena-postgres`) hosts **two isolated databases**:

| Database | User | Service |
|---|---|---|
| `miracena` | `miracena` | Directus |
| `n8n` | `n8n` | n8n |

**Rationale:** Memory-constrained environment (12 GB on Kavure / 5.7 GB on Kuaray); sharing a single database engine minimizes daemon overhead. Databases remain completely segregated without cross-references.

## Tailscale Funnel

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

**Tailscale MagicDNS Constraint:** Custom subdomains (`site.miracena.xxx`, `cms.miracena.xxx`) do not resolve automatically — DNS registers strictly the root node hostname (`miracena.chimaera-heptatonic.ts.net`). Internal tools (Directus, n8n) are reached via their mapped ports on `kuaray.chimaera-heptatonic.ts.net:{port}`.

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
├── nuxt/                       # Nuxt3 frontend application
│   ├── app/                    # Application source code
│   ├── assets/                 # Styles and static assets
│   ├── package.json            # Node dependencies
│   ├── nuxt.config.ts          # Nuxt configuration
│   └── docker-compose.yml      # Nuxt container definition
├── wordpress/                  # WordPress runtime
│   └── html/                   # WordPress core files
└── backups/                    # Local temporary backup staging
```

## Docker Network

```
miracena_default (172.x.x.x/16)
├── miracena-postgres
├── miracena-redis
├── miracena-directus
├── miracena-nuxt
├── miracena-nginx-proxy-manager
├── miracena-wordpress
├── miracena-mariadb
├── miracena-n8n
├── miracena-tunnel
└── miracena-stenio
```

## Management Commands

```bash
# Container status
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep miracena

# Service logs
docker logs miracena-directus -f
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
| 3003 | Nuxt3 Frontend | — |
| 8055 | Directus | — |
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
| PostgreSQL (Directus + n8n) | `pg_dump` → gzip | Daily at 05:35 BRT |
| MariaDB (WordPress) | `mariadb-dump` → gzip | Daily at 05:35 BRT |
| WordPress files | `rsync --delete` | Daily at 05:35 BRT |
| Directus uploads (retention only, until 2026-11-30 — HB-093) | `rsync --delete` | Daily at 05:35 BRT |
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

# Restore PostgreSQL databases
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-miracena-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U miracena -d miracena
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-n8n-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n

# Restore MariaDB database
zcat /mnt/BACKUP/miracena-server-kavure/daily/mariadb-wordpress-YYYY-MM-DD.sql.gz | docker exec -i miracena-mariadb mariadb -u root -p"$MYSQL_ROOT_PASSWORD" wordpress
```

## Enforced Directus Governance (11/09/2026)

### Extension Infrastructure

- `docker-compose.yml`: Directus configured with `EXTENSIONS_AUTO_RELOAD=true` + `MARKETPLACE_TRUST=all` + volume `./directus/extensions:/directus/extensions`
- **Custom Hook `miracena-workflow`**: Workflow state validation on all API item mutations
  - Canonical source: `/srv/data/miracena/directus/src/miracena-workflow/`
  - Build: Executed inside `miracena-nuxt` container (Node 22), targeting `/srv/data/miracena/directus/src/miracena-workflow`; `npm run build` generates `dist/`
  - **Requirement:** API extension `package.json` requires `directus:extension: {type, path, source}` — `source` field is mandatory
  - Deployment: Copies `dist/` + `package.json` to `/directus/extensions/miracena-workflow/`
  - **Runtime Note:** Directus 12 does not resolve `@directus/errors` from hook imports — vendor into `dist/node_modules/@directus/errors`

### Workflow Validation Rules (`miracena-workflow` hook)

| Collection | Rule | Error Returned |
|---|---|---|
| `tasks` | Status `done` requires `deliverable_url` | `INCOMPLETE_WORKFLOW 400` |
| `tasks` | Status `in_progress` requires `assignee` | `INCOMPLETE_WORKFLOW 400` |
| `projects` | Status `ativo` requires `squad` + `client` | `INCOMPLETE_WORKFLOW 400` |
| `deals` | Stage `won` requires `project` | `INCOMPLETE_WORKFLOW 400` |

Test suite executed 11/09/2026: 6/6 passed (proper rejection and passage).

### Consolidation to 25 Collections (Free Tier Constraint)

Directus 12 free tier enforces a **25 custom collection limit even on self-hosted instances** (HTTP 403 `LIMIT_EXCEEDED`). Collections consolidated:

| Removed Collection | Relocated Target |
|---|---|
| `licenses` | Fields `license_type`, `license_cost`, `purchase_date` in `assets` |
| `deliverables` | Fields `deliverable_url`, `deliverable_note` in `tasks` |
| `milestones` | Managed directly within `tasks` with target deadlines |
| `pdps` | Fields `pdi_goals`, `pdi_actions` in `members` |
| `payments` | Fields `payment_method`, `payment_date` in `invoices` |

New governance collections created:
- `sprints` — Bi-weekly sprint cycles (planned, in-progress, completed)
- `daily_syncs` — Asynchronous daily standups (done_yesterday, plan_today, blockers)
- `retrospectives` — Sprint retrospectives (what_went_well, what_improve, actions)
- `decisions` — Architectural decision log (strategic, tactical, operational, reversible, review_date)
- `guild_sessions` — Knowledge-sharing guild meetings
- `checklists` — Framework operational checklists
- `links` — Centralized client and tooling resources

### Granular Access Roles (11/09/2026)

**Freelancer** role (external contractors/editors) created:

| Role | Policy | Permissions | Restricted Access |
|---|---|---|---|
| Admin | Administrator | Full system access | None |
| Member | Miracena Member | Full CRUD (internal team) | None |
| **Freelancer** | Miracena Freelancer | Read: tasks, projects, members, assets, guilds, sprints, links · Update: tasks, daily_syncs · Create: daily_syncs | **403 Forbidden:** invoices, profit_share, deals, contacts, proposals, peer_reviews, okrs, key_results, decisions, checklists, cabals, guild_sessions |
| Client | Miracena Client | Read: projects, invoices, deals (API only) | Admin app modules |

### Extension Directory Backup Note

The custom hook in `/srv/data/miracena/directus/extensions/` **is not mirrored by `miracena-backup` rsync** (which covers uploads, databases, WordPress, and NPM). Canonical source code in `src/miracena-workflow` enables clean rebuilds.

## Temporary evaluation containers (2026-10-30)

A separate Compose project (`miracena-frappe`, folder `/srv/data/miracena/frappe/`) runs the client's **platform** (promoted from
evaluation on 31/10/2026). It uses an immutable custom image with the client's app baked in, publishes a single **loopback** port
(`127.0.0.1:8081`, reach it with `ssh -L 8081:127.0.0.1:8081 kuaray`), has per-container memory limits (about 2.7 GB in
total), healthchecks on every service and the highest OOM score so the kernel kills it first if memory runs short. It has its
own network and no link to the stack above. A one-shot `migrate` service gates the backend on every deploy. Its definition,
runbook (deploy, backup, restore) and decision record live in the client's private repository; the daily backup is part of
`miracena-backup` (above). Access: a tailnet-only HTTPS proxy (`tailscale serve --bg --https=8446 http://127.0.0.1:8081`, undo `tailscale serve --https=8446 off`) makes it reachable from tailnet devices at `https://kuaray.chimaera-heptatonic.ts.net:8446`; it is **not** Funnel (nothing is exposed to the internet). Follow-ups: HB-092.
