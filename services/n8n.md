---
tags: [homelab, service, n8n, automation, miracena, kuaray, kavure]
---

# n8n

Visual workflow automation — self-hosted Zapier alternative. Connects Gmail, Sheets, AI models, webhooks, and homelab services.

There are **two independent n8n instances** in the homelab, each with its own PostgreSQL and lifecycle:

| Instance | Host | Container | Stack | Database | Purpose |
|---|---|---|---|---|---|
| **n8n (Homelab)** | **kavure** | `n8n` | standalone (`/srv/data/n8n/`) | own `n8n-postgres` (volume `n8n_postgres_data`) | Homelab automation |
| **n8n (Miracena)** | **kuaray** | `miracena-n8n` | inside the Miracena stack (`/srv/data/miracena/`) | shared `miracena-postgres` (database `n8n`) | Miracena client workflows |

> **2026-10-09 — Homelab n8n reactivated on kavure.** The standalone stack at `/srv/data/n8n/` (stopped since the n8n consolidation into Miracena on 10/09) was brought back up and is now **healthy**. It is a **separate** service from the Miracena n8n and has its own tile in [Homepage](homepage.md) — `n8n Homelab` (Kavure group). Its dedicated daily backup was **re-enabled**: `hl-n8n-backup.timer` (05:25) → `pg_dump -U n8n -d n8n` → NAS `/mnt/BACKUP/n8n-server-kavure/daily/`. The `offbox` NFS mount (`/srv/data/n8n/offbox`), removed on 09/10, was **restored** in `/etc/fstab`.

---

## n8n (Homelab) — kavure

**Server:** kavure  
**Port:** `5678`  
**URL:** `http://kavure.chimaera-heptatonic.ts.net:5678`

- **Compose:** `/srv/data/n8n/compose.yml` (`name: n8n`; services `n8n` + `postgres`), healthcheck `wget -q -O /dev/null http://127.0.0.1:5678/healthz`. Port published **tailnet-only** (`100.124.146.77:5678:5678`, tightened 09/10/2026 from `0.0.0.0`).
- **Database:** own PostgreSQL (`n8n-postgres`, volume `n8n_postgres_data`).
- **Metrics:** `N8N_METRICS=true` (Prometheus `/metrics`).
- **Backup:** `hl-n8n-backup.timer` (daily 05:25, `Persistent=true`) → `/usr/local/bin/n8n-backup` → `pg_dump -U n8n -d n8n | gzip` → `/mnt/BACKUP/n8n-server-kavure/daily/n8n-<date>.sql.gz` (retention 14 days). Health stamp `/srv/health/n8n-backup-last-ok` (added 09/10/2026 to the unit; covered by `BackupNotRun`) + logs via the script's `ntfy /backup` topic.

> **Prometheus (09/10/2026):** the `n8n` scrape job targets **both** instances — Homelab (`100.124.146.77:5678`) and Miracena (`100.94.209.99:5678`) — each relabeled with its `instance`; the `n8nDown` alert covers either one.

---

## n8n (Miracena) — kuaray

**Server:** kuaray (part of the Miracena stack)  
**Port:** `5678`  
**Internal URL:** `http://kuaray.chimaera-heptatonic.ts.net:5678` · `http://100.94.209.99:5678`  
**Basic Auth:** Active (`N8N_BASIC_AUTH_*` — see sops store)

> **Migrated (10/09/2026):** From standalone stack (`/srv/data/n8n/`) into the Miracena stack (`/srv/data/miracena/`). Shares PostgreSQL instance with Directus (isolated databases: `n8n` and `miracena`). Empty database upon migration (0 workflows, 0 credentials).

> **Migrated (04/10/2026):** Entire Miracena stack (including n8n) moved from kavure → **kuaray** (freeing RAM/disk). Side effects resolved on 09/10: the Prometheus `n8n` job was still scraping the old kavure target (causing `n8nDown`/`PrometheusDown` alerts every 4h, target updated to `100.94.209.99:5678`) and kavure's `hl-n8n-backup.timer` failed daily (unit **disabled**). _Note (10/09): that timer was since **re-enabled** for the reactivated Homelab instance — it now stages dumps of the kavure `n8n-postgres`, not the Miracena database._

### Stack

| Container | Image | Function |
|---|---|---|
| miracena-n8n | `docker.n8n.io/n8nio/n8n:stable` | Workflow execution engine |
| miracena-postgres | `postgres:16-alpine` | Shared database instance (`n8n` database) |

- **Shared PostgreSQL** with Directus — same container instance, separate databases. Minimizes overhead in memory-constrained environments.
- **`N8N_ENCRYPTION_KEY`** (in `.env`): Encrypts saved credentials within workflows. **Loss of this key = unrecoverable credentials** even if the database remains intact. Backed up in KeePass.
- `N8N_DEFAULT_BINARY_DATA_MODE=database`: Binary payloads/attachments stored directly in PostgreSQL → `pg_dump` captures complete state.
- `N8N_METRICS=true`: Exposes `/metrics` endpoint for Prometheus scraping.
- `EXECUTIONS_DATA_PRUNE=true` + `MAX_AGE=336h`: Execution data pruned automatically (prevents disk saturation).
- **Basic Auth** enabled: UI access enforces user/password authentication (`N8N_BASIC_AUTH_USER`/`PASSWORD` from secret store).

### Access

- **Tailnet:** `http://kuaray.chimaera-heptatonic.ts.net:5678`
- **Funnel:** Not exposed publicly (security policy) — evaluate public webhooks on an isolated case-by-case basis.
- First access: Create the **owner** account in the UI (n8n admin user).

### Backup

- **Shared PostgreSQL:** `pg_dump` of the `n8n` database via `docker exec miracena-postgres pg_dump -U n8n n8n` — runs on **kuaray** via `hl-miracena-backup.timer` (05:35 → NFS `miracena-server-kavure/daily/postgres-n8n-<date>.sql.gz`).
- **Restore:** Bring up the stack with matching `N8N_ENCRYPTION_KEY` → `zcat n8n-<date>.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n`. Test recovery periodically.
- Quick workflow export: `docker exec miracena-n8n n8n export:workflow --all --output=/home/node/.n8n/export`.

### Maintenance

- **Updates:** Coordinated with the Miracena stack on kuaray (see [`miracena-stack`](miracena-stack.md)). Run a manual PostgreSQL dump prior to major upgrades.
- **Logs:** `docker logs miracena-n8n` / via Loki (kavure centralizes logs across nodes).

## See also

- [[miracena-stack]] — Full stack architecture (shared PostgreSQL)
- [[homepage]] — `n8n` and `n8n Homelab` tiles
- [[monitoring]] — Prometheus scraping `/metrics` from n8n
- [[searxng]] — Can serve as a search provider for automated workflow pipelines (JSON format)
