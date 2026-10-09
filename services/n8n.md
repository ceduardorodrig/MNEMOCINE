---
tags: [homelab, service, n8n, automation, miracena, kuaray]
---

# n8n

Visual workflow automation — self-hosted Zapier alternative. Connects Gmail, Sheets, AI models, webhooks, and homelab services.

**Server:** kuaray (part of the Miracena stack)  
**Port:** `5678`  
**Internal URL:** `http://kuaray.chimaera-heptatonic.ts.net:5678` · `http://100.94.209.99:5678`  
**Basic Auth:** Active (`N8N_BASIC_AUTH_*` — see sops store)  

> **Migrated (10/09/2026):** From standalone stack (`/srv/data/n8n/`) into the Miracena stack (`/srv/data/miracena/`). Shares PostgreSQL instance with Directus (isolated databases: `n8n` and `miracena`). Empty database upon migration (0 workflows, 0 credentials).

> **Migrated (04/10/2026):** Entire Miracena stack (including n8n) moved from kavure → **kuaray** (freeing RAM/disk). Side effects resolved on 09/10: the Prometheus `n8n` job was still scraping the old kavure target (causing `n8nDown`/`PrometheusDown` alerts every 4h, target updated to `100.94.209.99:5678`) and kavure's `hl-n8n-backup.timer` failed daily (unit **disabled** — database dumps are now executed by `hl-miracena-backup` on kuaray).

## Stack

| Container | Image | Function |
|---|---|---|
| miracena-n8n | `docker.n8n.io/n8nio/n8n:stable` | Workflow execution engine |
| miracena-postgres | `postgres:16-alpine` | Shared database instance (`n8n` database) |

- **Shared PostgreSQL** with Directus — same container instance, separate databases. Minimizes overhead in memory-constrained environments (12 GB RAM).
- **`N8N_ENCRYPTION_KEY`** (in `.env`): Encrypts saved credentials within workflows. **Loss of this key = unrecoverable credentials** even if the database remains intact. Backed up in KeePass.
- `N8N_DEFAULT_BINARY_DATA_MODE=database`: Binary payloads/attachments stored directly in PostgreSQL → `pg_dump` captures complete state.
- `N8N_METRICS=true`: Exposes `/metrics` endpoint for Prometheus scraping — ingested by the observability stack.
- `EXECUTIONS_DATA_PRUNE=true` + `MAX_AGE=336h`: Execution data pruned automatically (prevents disk saturation).
- **Basic Auth** enabled: UI access enforces user/password authentication (`N8N_BASIC_AUTH_USER`/`PASSWORD` from secret store).

## Access

- **Tailnet:** `http://kuaray.chimaera-heptatonic.ts.net:5678` (previously `kavure.*`, migrated 04/10)
- **Funnel:** Not exposed publicly (security policy) — evaluate public webhooks on an isolated case-by-case basis.
- First access: Create the **owner** account in the UI (n8n admin user).

## Configuration

```yaml
# /srv/data/miracena/docker-compose.yml (n8n summary; host: kuaray since 04/10)
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:stable
    container_name: miracena-n8n
    env_file: .env
    ports: ["5678:5678"]
    volumes: [n8n_data:/home/node/.n8n]
    depends_on:
      postgres: { condition: service_healthy }

  postgres:
    image: postgres:16-alpine
    container_name: miracena-postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d  # initializes n8n database
```

The `.env` file holds all environment variables (PostgreSQL, Directus, WordPress, n8n). Secrets managed via sops store.

## Backup

- **Shared PostgreSQL:** `pg_dump` of the `n8n` database via `docker exec miracena-postgres pg_dump -U n8n n8n` — runs on **kuaray** via `hl-miracena-backup.timer` (05:35 → NFS `miracena-server-kavure/daily/postgres-n8n-<date>.sql.gz`, verified on 09/10: daily dumps healthy).
  > ⚠️ kavure's `hl-n8n-backup.timer` (05:25) was orphaned following the 04/10 migration — producing 20-byte failed dumps and systemd failed states daily. **Disabled on 09/10/2026** (NFS mount `/srv/data/n8n/offbox` and fstab entry also removed).
- **Restore:** Bring up the stack with matching `N8N_ENCRYPTION_KEY` → `zcat n8n-<date>.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n`. Test recovery periodically.
- Quick workflow export: `docker exec miracena-n8n n8n export:workflow --all --output=/home/node/.n8n/export`.

## Maintenance

- **Updates:** Coordinated with the Miracena stack on kuaray (see [`miracena-stack`](miracena-stack.md)). Run a manual PostgreSQL dump prior to major upgrades.
- **Logs:** `docker logs miracena-n8n` / via Loki (kavure centralizes logs across nodes).

## See also
- [[miracena-stack]] — Full stack architecture (shared PostgreSQL)
- [[monitoring]] — Prometheus scraping `/metrics` from n8n
- [[searxng]] — Can serve as a search provider for automated workflow pipelines (JSON format)
