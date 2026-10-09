---
tags: [homelab, service, steniobot, docker, env, ssl]
---

# StênioBOT

AI-powered minute-taking, transcription, and meeting summarization bot for institutional governance.

**Server:** kavure (Swarm manager, role: core) — migrated from psicopompo on 07/08/2026  
**Stack:** `sae-core` (Docker Swarm) on kavure; GPU workers on psicopompo (role: gpu)  
**Port:** `9090` — **Overlay `sae-net` only** (VIP `10.0.2.20:9090`). **Not published on host**: verified 02/10/2026 (`docker service inspect sae-core_api` → `Endpoint.Ports: null`; `ss -ltn` on kavure lacks 9090; `curl 100.124.146.77:9090` → connection refused)  
**Internal URL:** `http://api:9090` (inside `sae-net` overlay)  
~~**Tailscale Direct URL:** `http://100.124.146.77:9090`~~ — **Deprecated/decommissioned**; reached via edge reverse proxy: `http://ybyra.chimaera-heptatonic.ts.net/api/health` (**200** verified 02/10/2026)  
**Funnel:** `{{TAILSCALE_FUNNEL_DOMAIN}}` → `https` (via edge tunnel on ybyra)  

## Stack (Docker Swarm)

| Service | Image | Ports | Function |
|---|---|---|---|
| sae-core_api | sumaenima-server:latest | **`—`** (overlay only; VIP `10.0.2.20:9090` — *not* published on host) | Rust Axum 0.8 backend + React 19 WASM Client |
| sae-core_db | postgres:16-alpine | — | Primary relational database |
| sae-core_valkey | valkey/valkey:8-alpine | — | Distributed cache + session store |
| sae-core_backup | sumaenimahub-backup-sentinel:latest | `0.0.0.0:9092` | Automated backup daemon (Borg + pg_dump) |

### Standalone Containers (Outside Swarm, attached to overlay network)

| Container | Function |
|---|---|
| steniobot_vision | Computer vision service (overlay attached) |
| steniobot_audio | Audio processing and transcription bridge (overlay attached) |

## Storage & Volumes

### Kavure Volumes (Bind Mounts under /srv/data/sumaenimahub/)

| Volume / Path | Container | Stored Data |
|---|---|---|
| `/srv/data/sumaenimahub/volumes/sumaenimahub_postgres_data/_data` | sae-core_db | PostgreSQL storage |
| `/srv/data/sumaenimahub/volumes/sumaenimahub_umami_data/_data` | sae-core_umami-db | Umami analytics storage |
| `/srv/data/sumaenimahub/volumes/sumaenimahub_valkey_data/_data` | sae-core_valkey | Valkey cache persistence |
| `/srv/data/sumaenimahub/backup` | sae-core_backup | NFS backup target → psicopompo `/mnt/BACKUP/sumaenima-server-kavure/` |

### Bind Mounts (kavure)

| Host (kavure) | Container | Target |
|---|---|---|
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/app` | `/app` | Application code |
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/logs` | `/app/logs` | Application logs |
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/migrations` | `/app/migrations:ro` | Database migration scripts |

> LLM model cache (`llm_model_cache`, ~36GB) lives **on psicopompo** (mounted locally by GPU workers) — kavure does NOT mount it. The API utilizes lightweight ONNX embeddings downloaded on demand.

## Core Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | `postgresql://stenio_user:{{DB_PASSWORD}}@db:5432/stenio_db` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth credentials |
| `GOOGLE_REDIRECT_URI` | OAuth callback endpoint (e.g. `https://{{TAILSCALE_FUNNEL_DOMAIN}}/api/auth/callback`) |
| `STENIOBOT_OWNER_EMAIL` | Admin account bypass token |
| `SECRET_KEY` | Master Fernet encryption key |
| `SECURE_COOKIES` | `true` in production (HTTPS) |
| `ALLOWED_WS_ORIGINS` | Permitted origins for WebSocket & CSRF verification |
| `VALKEY_URL` | `redis://valkey:6379/0` |
| `HF_TOKEN` | Hugging Face token (Gemma 3 retrieval) |
| `PURIFIER_TYPE` | `gemma` (default), `rtx`, `mock` |
| `USE_LLM` | Enables LLM transcript purification |

> Comprehensive template: `docs/environment.md` in upstream repository.

## Local Control (sumaenima-ctl)

SUMAENIMA GPU workers and Swarm services do **not start automatically** at boot.
To manage services manually (`sumaenima-ctl` runs on psicopompo and manages kavure Swarm via SSH):

```bash
sumaenima-ctl status   # View current state (kavure Swarm + local GPU)
sumaenima-ctl start    # Spin up Swarm services (kavure) + GPU workers (psicopompo)
sumaenima-ctl stop     # Tear down everything (scale Swarm to 0, down GPU workers)
```

Script path: `~/.local/bin/sumaenima-ctl` (in PATH).

### Auto-start Exceptions

- Swarm services `sae-core_*` / `sae-edge_*` → `replicas: 0` until `sumaenima-ctl start`
- GPU workers (steniobot-vision, steniobot-audio, ollama) → `restart: no` (auto-exit after 180s idle to release VRAM)

## GPU Acceleration

- **Runtime:** NVIDIA Container Toolkit (on psicopompo)
- **CUDA:** 12.2.2 (base container image)
- **Minimum VRAM:** 6 GB (12 GB+ recommended)
- **Models:** faster-whisper (transcription) + Gemma 3 1B (LLM purification) — model cache persisted on psicopompo

## Access Routes

| Route | URL |
|---|---|
| Swarm Overlay (Internal) | `http://api:9090` ✅ |
| ~~Tailscale Direct (kavure)~~ | ~~`http://100.124.146.77:9090`~~ **Not published on host** (02/10/2026) |
| Ybyra Proxy (External Edge) | `http://{{SUMAENIMA_DOMAIN}}/api/` ✅ |
| Tailscale Funnel (Public) | `https://{{TAILSCALE_FUNNEL_DOMAIN}}` |
| **Canonical Health Check** | `http://ybyra.chimaera-heptatonic.ts.net/api/health` → **200** (backup: `:9092/health` via sentinel) |
| API Documentation (Swagger) | Via edge route: `…/api/docs` (direct `:9090/docs` unexposed) |

## Backup Strategy

| Asset | Backup Method |
|---|---|
| Codebase + Git | Primary repository at `/mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/` (GitHub) + deploy clone at `/srv/data/sumaenimahub/SUMAENIMA-HUB/` (kavure) |
| PostgreSQL Database | Daily automated backup at 03:00 via sentinel daemon (Borg + pg_dump → psicopompo NFS) |

> **Execution Workflow (29/08/2026):** Systemd timer `hl-sumaenima-backup.timer` (kavure) → `/usr/local/bin/sumaenima-backup` (failsafe/retry/ntfy `/backup`) → `docker exec sae-core_backup python3 /app/scripts/backup/sentinel.py`. Marker `/app/logs/.backup_last_run` updated by host root; health stamp written to `/srv/health/sumaenima-backup-last-ok` (tracked by Grafana `BackupNotRun` alert). Container-internal crond was **removed on 29/08** (image runs as non-root `appuser` since v2.22.0).

| Asset | Storage |
|---|---|
| Application Logs | Bind mount in `./logs/` |
| `.env` Configuration | In repository root (kavure `/srv/data/sumaenimahub/SUMAENIMA-HUB/.env` + psicopompo) |
| Model Cache | Persisted on psicopompo (`llm_model_cache`) — can be re-fetched via Hugging Face token |

## Recovery Runbook

1. Clone repository: `git clone https://github.com/ceduardorodrig/SUMAENIMA-HUB.git`
2. Decrypt environment: Extract `.env` from sops store
3. Load variables: `export $(grep -v '^#' .env | xargs)`
4. Deploy Swarm stack (on kavure): `docker stack deploy -c provisioning/stacks/core.yml sae-core`
5. Run migrations: `docker exec $(docker ps --filter name=sae-core_api -q) python3 -m alembic upgrade head`
6. Verify service health: `curl http://ybyra.chimaera-heptatonic.ts.net/api/health`
7. Spin up GPU workers (psicopompo): `sumaenima-ctl start`

## Canonical Architecture Documentation

Upstream documentation for transcription and minute-taking resides in **Sumænimá Hub** repository (`docs/`):

| Guide | Scope |
|---|---|
| `deployment.md` | Deployment, migrations, recovery runbook, checklists |
| `environment.md` | Environment configuration & SOPS secret handling |
| `connectivity.md` | Tailscale routing, Funnel, and load balancing |
| `observability.md` | Prometheus metrics, Loki/Grafana, JSON structured logging |
| `security.md` | Security boundary matrix and tenant data isolation |
| `ci-github.md` | GitHub Actions CI/CD pipeline automation |
| `alembic-workflow.md` | Database migrations and schema versioning |
| `architecture.md` | v3.0 Architecture (100% Rust Axum backend) |

## Dependencies

- Docker Swarm (manager: kavure) + Docker Compose v2 (GPU workers on psicopompo)
- NVIDIA Container Toolkit (psicopompo)
- Tailscale (Funnel for public ingress — tunnel termination on ybyra)
- PostgreSQL 16 (core app) + PostgreSQL 15 (Umami analytics) — kavure
- Valkey 8 (cache) — kavure

## See also
- [[kavure]] — Swarm core manager hosting the application stack
- [[kavure-disaster-recovery]] — Core node disaster recovery runbook
- [[psicopompo]] — GPU inference worker and build host
- [[adguard-home]] — Local DNS resolution
