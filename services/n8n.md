---
tags: [homelab, servico, n8n, automacao, miracena, kavure]
---

# n8n

Visual automation (workflows) — a "homegrown Zapier". Connects Gmail, Sheets, AI, webhooks and homelab services.

**Server:** kavure (part of the Miracena stack)
**Port:** `5678`
**Internal URL:** `http://kavure.chimaera-heptatonic.ts.net:5678`
**Basic Auth:** enabled (`N8N_BASIC_AUTH_*` — see the sops store)

> **Migrated (10/09/2026):** from the standalone stack (`/srv/data/n8n/`) to the Miracena stack (`/srv/data/miracena/`). Shares PostgreSQL with Directus (separate databases: `n8n` and `miracena`). Empty database at migration time (0 workflows, 0 credentials).

## Stack

| Container | Image | Role |
|---|---|---|
| miracena-n8n | `docker.n8n.io/n8nio/n8n:stable` | Workflow engine |
| miracena-postgres | `postgres:16-alpine` | Shared database (database `n8n`) |

- **Shared PostgreSQL** with Directus — same instance, separate databases. Reduces overhead in an environment with limited RAM (12 GB).
- **`N8N_ENCRYPTION_KEY`** (in .env): encrypts the credentials saved in workflows. **Losing it = unreadable credentials** even with the database intact. Backed up in KeePass.
- `N8N_DEFAULT_BINARY_DATA_MODE=database`: attachments/binary data stay in Postgres → `pg_dump` captures everything.
- `N8N_METRICS=true`: exposes `/metrics` (Prometheus) — consumed by the observability stack.
- `EXECUTIONS_DATA_PRUNE=true` + `MAX_AGE=336h`: limited execution retention (does not fill the disk).
- **Basic Auth** enabled: UI access requires a user/password (`N8N_BASIC_AUTH_USER`/`PASSWORD` from the store).

## Access

- **Tailnet:** `http://kavure.chimaera-heptatonic.ts.net:5678`
- **Funnel:** not exposed publicly (security) — public webhooks evaluated case by case.
- First access: create the **owner** account in the UI (n8n admin user).

## Configuration

```yaml
# /srv/data/miracena/docker-compose.yml (resumo do n8n)
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
      - ./postgres/init:/docker-entrypoint-initdb.d  # cria database n8n
```

The `.env` holds all the variables (PostgreSQL, Directus, WordPress, n8n). Secrets via the sops store.

## Backup

- **Shared PostgreSQL:** `pg_dump` of the `n8n` database via `docker exec miracena-postgres pg_dump -U n8n n8n`.
- **Restore:** bring the stack up with the same `N8N_ENCRYPTION_KEY` → `zcat n8n-<data>.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n`. Test it periodically.
- Quick workflow export: `docker exec miracena-n8n n8n export:workflow --all --output=/home/node/.n8n/export`.

## Maintenance

- **Update:** kavure's watchtower manages it (`:stable`). Before a major update, run a manual PostgreSQL backup.
- **Logs:** `docker logs miracena-n8n` / via Loki (once observability is active).

## See also
- [[miracena-stack]] — Full stack (shared PostgreSQL)
- [[monitoring]] — Prometheus consumes n8n's `/metrics`
- [[searxng]] — can become the search engine in workflows (JSON format)
