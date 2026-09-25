---
tags: [homelab, servico, miracena, stack, docker, n8n, directus, wordpress, nuxt, kavure]
---

# Miracena - Infrastructure Stack

**Server:** Kavure (Dell OptiPlex 3060 SFF)
**Deploy Date:** 10/09/2026
**Canonical Project & Governance:** Miracena (temporary incubation in the Homelab)
**Environment:** Kavure Server (isolated dedicated instance)

## Deployed Stack

| Service | Container | Port | Image | RAM Limit | CPU Limit |
|---------|-----------|-------|--------|------------|------------|
| PostgreSQL | miracena-postgres | 5432 (internal) | postgres:16-alpine | 1 GB | 0.5 |
| Redis | miracena-redis | 6379 (internal) | redis:7-alpine | 128 MB | 0.25 |
| Directus | miracena-directus | 8055 | directus/directus:latest | 2 GB | 1.0 |
| Nuxt3 Frontend | miracena-nuxt | 3003 | node:22-alpine | 1 GB | 1.0 |
| Nginx Proxy Manager | miracena-nginx-proxy-manager | 81 (admin), 8180 (HTTP), 8445 (HTTPS) | jc21/nginx-proxy-manager:latest | 256 MB | 0.25 |
| WordPress | miracena-wordpress | 8085 | wordpress:latest | 512 MB | 0.5 |
| MariaDB | miracena-mariadb | 3306 (internal) | mariadb:11 | 512 MB | 0.25 |
| n8n | miracena-n8n | 5678 | docker.n8n.io/n8nio/n8n:stable | 1 GB | 0.5 |
| Tailscale Tunnel | miracena-tunnel | — | tailscale/tailscale:latest | 128 MB | 0.25 |

## Access

### External (via Tailscale Funnel — public, no Tailscale required)
- **WordPress (site):** https://miracena.chimaera-heptatonic.ts.net/

### Internal (via Tailscale — requires Tailscale connected)
- **Nuxt3 Frontend:** http://kavure.chimaera-heptatonic.ts.net:3003
- **WordPress:** http://kavure.chimaera-heptatonic.ts.net:8085
- **Directus:** http://kavure.chimaera-heptatonic.ts.net:8055
- **n8n:** http://kavure.chimaera-heptatonic.ts.net:5678
- **NPM Admin:** http://kavure.chimaera-heptatonic.ts.net:81

### Credentials

#### Nginx Proxy Manager
- **Email:** ceduadorodrig@gmail.com
- **Password:** (in .env — NPM_ADMIN_PASSWORD / SOPS)
- **URL:** http://kavure.chimaera-heptatonic.ts.net:81

#### n8n
- **User:** edu
- **Password:** (in .env — N8N_BASIC_AUTH_PASSWORD)
- **Status:** ✅ Configured (10/09/2026)

#### Directus
- **Email:** ceduadorodrig@gmail.com
- **Password:** (in .env — ADMIN_PASSWORD)
- **Static Token:** `miracena-admin-token-2026` (for API/CLI)
- **Status:** ✅ Configured (10/09/2026)
- **Schema:** 21 collections, 28 relations via direct SQL
- **Test data:** 6 members, 3 guilds, 3 cabals, 3 contacts, 2 squads, 3 projects, 2 deals, 4 tasks, 3 OKRs, 5 key results, 2 invoices, 1 payment, 3 assets, 2 peer reviews
- **Roles:** Admin (built-in), Member (full CRUD), Client (read-only), Public (assets/guilds/cabals)
- **Policies:** Miracena Member (full CRUD), Miracena Client (read-only), Miracena Public (read-only on assets)
- **Permissions:** 103 custom permissions (Member: CRUD on 23 collections, Client: read on 8 collections, Public: read on 3 collections)
- **Dashboards:** 4 dashboards (Visão Geral, OKRs & Progresso, Financeiro, Asset Bank) with 21 panels
- **Flows:** 3 active flows (Novo Membro, Tarefa Criada, Proposta Criada) — free tier limit reached

#### WordPress
- **Setup:** http://kavure.chimaera-heptatonic.ts.net:8085 (first access creates the admin)
- **Status:** ⏳ Awaiting configuration

## Shared PostgreSQL

A single PostgreSQL (`miracena-postgres`) serves **two separate databases**:

| Database | User | Service |
|----------|---------|---------|
| `miracena` | `miracena` | Directus |
| `n8n` | `n8n` | n8n |

**Rationale:** homelab with limited RAM (12 GB); sharing the instance reduces overhead. Isolated databases, no cross-reference. Accepted pattern for non-critical environments.

## Tailscale Funnel

The `miracena-tunnel` container connects to the tailnet as hostname `miracena` and exposes NPM via Funnel on port 443.

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

**Tailscale MagicDNS limitation:** subdomains (`site.miracena.xxx`, `cms.miracena.xxx`) do not resolve — DNS only registers the node hostname (`miracena.chimaera-heptatonic.ts.net`). Internal services (Directus, n8n) remain reachable through the mapped ports at `kavure.chimaera-heptatonic.ts.net:{porta}`.

## File Structure

```
/srv/data/miracena/
├── docker-compose.yml          # Stack principal
├── .env                        # Variáveis sensíveis
├── postgres/                   # Dados PostgreSQL
│   └── init/                   # Scripts de inicialização
│       └── init-multiple-dbs.sh
├── nginx-proxy-manager/        # Configurações NPM
│   ├── data/                   # Dados NPM (SQLite)
│   └── letsencrypt/            # Certificados SSL
├── tailscale/                  # Config Tailscale tunnel
│   └── serve.json              # Config de Funnel/Serve
├── nuxt/                       # Frontend Nuxt3
│   ├── app/                    # Código da aplicação
│   ├── assets/                 # CSS e assets
│   ├── package.json            # Dependências
│   ├── nuxt.config.ts          # Configuração Nuxt
│   └── docker-compose.yml      # Container Nuxt
├── wordpress/                  # Código WordPress
│   └── html/                   # Arquivos WordPress
└── backups/                    # Backups locais
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
└── miracena-tunnel
```

## Useful Commands

```bash
# Status dos containers
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep miracena

# Logs
docker logs miracena-directus -f
docker logs miracena-wordpress -f
docker logs miracena-n8n -f
docker logs miracena-tunnel -f

# Reiniciar stack
cd /srv/data/miracena && docker compose restart

# Parar stack
cd /srv/data/miracena && docker compose down

# Atualizar imagens
cd /srv/data/miracena && docker compose pull && docker compose up -d

# Verificar Funnel
docker exec miracena-tunnel tailscale funnel status

# Verificar status Tailscale
docker exec miracena-tunnel tailscale status
```

## Ports on Kavure

| Port | Service | Conflict? |
|-------|---------|-----------|
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

## Automatic Backups

### Structure

| Component | Method | Frequency |
|------------|--------|------------|
| PostgreSQL (Directus + n8n) | `pg_dump` → gzip | Daily 05:35 BRT |
| MariaDB (WordPress) | `mariadb-dump` → gzip | Daily 05:35 BRT |
| WordPress files | `rsync --delete` | Daily 05:35 BRT |
| Directus uploads | `rsync --delete` | Daily 05:35 BRT |
| NPM config | `rsync --delete` | Daily 05:35 BRT |

### Destination

- **NAS:** `/mnt/BACKUP/miracena-server-kavure/daily/` (psicopompo)
- **Mount point:** `/srv/data/miracena/offbox` (NFS via autofs)
- **Timer:** `hl-miracena-backup.timer` (05:35 BRT, `Persistent=true`)
- **Script:** `/usr/local/bin/miracena-backup`
- **Health file:** `/srv/health/miracena-backup-last-ok`
- **Log:** `/var/log/miracena-backup.log`
- **ntfy:** `/backup` topic on failure

### Commands

```bash
# Executar backup manualmente
sudo /usr/local/bin/miracena-backup

# Verificar timer
systemctl list-timers hl-miracena-backup.timer

# Ver logs
journalctl -u hl-miracena-backup.service -f
cat /var/log/miracena-backup.log

# Restaurar PostgreSQL
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-miracena-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U miracena -d miracena
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-n8n-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n

# Restaurar MariaDB
zcat /mnt/BACKUP/miracena-server-kavure/daily/mariadb-wordpress-YYYY-MM-DD.sql.gz | docker exec -i miracena-mariadb mariadb -u root -p"$MYSQL_ROOT_PASSWORD" wordpress
```

## Next Steps

1. **Configure roles & policies** in Directus (Admin, Member, Client, Public)
2. **Create dashboards (Insights)** in Directus — OKR progress, squad velocity, revenue, peer review, asset bank
3. **Configure flows (automations)** — notifications, calendar sync, AI agent triggers
4. **Configure WordPress** (first access via http://kavure.chimaera-heptatonic.ts.net:8085)
5. **Enable SSL** via Let's Encrypt on NPM (if an own domain is available)
6. **Migrate to VPS** once sized (Hostinger Business plan does not support it)

## Notes

- **n8n migrated:** from the standalone stack (`/srv/data/n8n/`) to the Miracena stack. Empty database (0 workflows, 0 credentials) — no data migration needed.
- **Shared PostgreSQL:** Directus and n8n use the same instance with separate databases.
- **Tailscale Funnel:** exposes WordPress publicly over HTTPS. Directus and n8n reachable internally via ports.
- **Resource limits:** Total allocated ~6.6 GB RAM (works with 12 GB available).
- **CGNAT environment:** no public IP, external access exclusively via Tailscale.
- **Directus Flatland:** 21 collections created (squads, guilds, cabals, peer reviews, OKRs, tasks, projects, deals, contacts, invoices, assets, etc.) with 28 relations via direct SQL (the API returned 500 because of a UUID vs integer type mismatch).
- **Nuxt3 Frontend:** Container `miracena-nuxt` on port 3003, connected to Directus via `NUXT_PUBLIC_DIRECTUS_URL`. Dashboard with stats, recent tasks and OKRs.
- **Directus Access Control:** 3 custom roles (Member, Client, Public) with policies and 103 custom permissions. Free tier limited to 3 flows — Novo Membro, Tarefa Criada, Proposta Criada.
- **Directus Insights:** 4 dashboards with 21 panels (metrics, lists) for overview, OKRs, finance and asset bank.

## Governance Enforced in Directus (11/09/2026)

### Extension infra

- `docker-compose.yml`: directus with `EXTENSIONS_AUTO_RELOAD=true` + `MARKETPLACE_TRUST=all` + volume `./directus/extensions:/directus/extensions`
- **Custom hook `miracena-workflow`**: workflow enforcement on all API item operations
  - Canonical source: `/srv/data/miracena/directus/src/miracena-workflow/`
  - Build: inside the `miracena-nuxt` container (Node 22), pointing at `/srv/data/miracena/directus/src/miracena-workflow` (same folder mounted at `/app`); `npm run build` produces `dist/`
  - **Requirement:** the API extension package.json needs `directus:extension: {type, path, source}` — the `source` field is mandatory (if missing, error "Current directory is not a valid Directus extension")
  - Deploy: copies `dist/` + `package.json` to `/directus/extensions/miracena-workflow/`
  - **Important:** the Directus 12 runtime does not resolve `@directus/errors` from the hook's `import` — you must vendor it into `dist/node_modules/@directus/errors` (copy from the build's node_modules)

### Workflow rules (hook `miracena-workflow`)

| Collection | Rule | Error |
|---|---|---|
| `tasks` | status `done` requires `deliverable_url` | `INCOMPLETE_WORKFLOW 400` |
| `tasks` | status `in_progress` requires `assignee` | `INCOMPLETE_WORKFLOW 400` |
| `projects` | status `ativo` requires `squad` + `client` | `INCOMPLETE_WORKFLOW 400` |
| `deals` | stage `won` requires `project` | `INCOMPLETE_WORKFLOW 400` |

Test suite 11/09/2026: 6/6 correct (blocks and passes).

### Consolidation to 25 collections (free tier limit)

The Directus 12 free tier limits you to **25 custom collections even when self-hosted** (HTTP 403 error `LIMIT_EXCEEDED`). Consolidation done:

| Removed collection | Where it went |
|---|---|
| `licenses` | fields `license_type`, `license_cost`, `purchase_date` in `assets` |
| `deliverables` | fields `deliverable_url`, `deliverable_note` in `tasks` |
| `milestones` | covered by `tasks` with deadlines |
| `pdps` | fields `pdi_goals`, `pdi_actions` in `members` |
| `payments` | fields `payment_method`, `payment_date` in `invoices` |

New governance collections created (guides in the `note` field of each collection, visible in the Data Studio):

- `sprints` — biweekly cycle, planned/in_progress/completed status; squad + objective
- `daily_syncs` — daily async (done_yesterday, plan_today, blockers mandatory)
- `retrospectives` — sprint retro (what_went_well, what_improve, actions)
- `decisions` — decision log (strategic/tactical/operational, reversible, review_date)
- `guild_sessions` — guild sessions (feeds the Shared Knowledge metric)
- `checklists` — pending items of the living framework (remaining categories in cadeia_valor/processo/infra/acesso/marketing/juridico)
- `links` — centralization of clients, tools, templates, references

`Miracena Member` permissions applied: full CRUD on the 7 new collections (28 permissions).

### Granular roles (11/09/2026 — access control)

New **Freelancer** role (external editors/freelancers) created:

| Role | Policy | What it sees | What it does NOT see |
|---|---|---|---|
| Admin | Administrator | everything | — |
| Member | Miracena Member | full CRUD (internal team) | — |
| **Freelancer** | Miracena Freelancer | read: tasks, projects, members, assets, guilds, sprints, links · update: tasks, daily_syncs · create: daily_syncs | **403:** invoices, profit_share, deals, contacts, proposals, peer_reviews, okrs, key_results, decisions, checklists, cabals, guild_sessions · cannot create tasks |
| Client | Miracena Client | read: projects/invoices/deals (API only) | app modules |

Validated with a test user (13 checks, everything passed — user deleted after the test).

**Free tier limitation:** restricting *fields per permission* returns `custom_permission_rules_enabled is a restricted resource` — there is no way to hide the freelancer's emails from the members directory via a DB override (it is not enforced even after changing the table). In Miracena's transparency culture, an open directory is acceptable.

**Dashboards per role:** in Directus 12 `module_listing` (hiding modules per role) was **removed** — the module bar is global (`directus_settings.module_bar`). Dashboards are visible to any user with app_access (collection panels without permission return an empty error in the UI). Definitive solution planned: **dashboards per role in the Nuxt3 front** (per-role routes with the Directus SDK), which honors the same API permissions — the front only reads what the permission allows.

### Backup of the extensions directory

The hook in `/srv/data/miracena/directus/extensions/` **is not covered by the `miracena-backup` rsync** (which only copies uploads, database, wordpress, NPM). The canonical source in `src/miracena-workflow` allows a rebuild. If you install Marketplace extensions, add an rsync line to `/usr/local/bin/miracena-backup`.
