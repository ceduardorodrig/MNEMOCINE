---
tags: [homelab, service, steniobot, docker, env, ssl]
---

# StênioBOT

AI-powered minutes bot for institutional meetings.

**Server:** kavure (Swarm manager, role: core) — migrated from psicopompo on 07/08/2026
**Stack:** `sae-core` (Docker Swarm) on kavure; GPU workers on psicopompo (role: gpu)
**Port:** `9090` (published on the kavure host for monitoring via Tailscale)
**Internal URL:** `http://api:9090` (overlay network `sumaenima_sumaenima-net`)
**Tailscale URL:** `http://100.124.146.77:9090`
**Funnel:** `{{TAILSCALE_FUNNEL_DOMAIN}}` → `https` (via tunnel on ybyra)

## Stack (Docker Swarm)

| Service | Image | Ports | Role |
|---|---|---|---|
| sae-core_api | sumaenima-server:latest | `0.0.0.0:9090` | Rust Axum 0.8 application + React 19 WASM client |
| sae-core_db | postgres:16-alpine | — | Main database |
| sae-core_valkey | valkey/valkey:8-alpine | — | Distributed cache + session |
| sae-core_backup | sumaenimahub-backup-sentinel:latest | `0.0.0.0:9092` | Automatic backup (Borg + pg_dump) |

### Standalone Containers (outside the Swarm, on the overlay network)

| Container | Role |
|---|---|
| steniobot_vision | Computer vision service (overlay) |
| steniobot_audio | Audio/transcription service (overlay) |

## Volumes

### Volumes (kavure — bind mounts in /srv/data/sumaenimahub/)

| Volume/Dir | Container | Persists |
|---|---|---|
| `/srv/data/sumaenimahub/volumes/sumaenimahub_postgres_data/_data` | sae-core_db | PostgreSQL data |
| `/srv/data/sumaenimahub/volumes/sumaenimahub_umami_data/_data` | sae-core_umami-db | Umami data |
| `/srv/data/sumaenimahub/volumes/sumaenimahub_valkey_data/_data` | sae-core_valkey | Valkey cache |
| `/srv/data/sumaenimahub/backup` | sae-core_backup | NFS backup → psicopompo `/mnt/BACKUP/sumaenima-server-kavure/` |

### Bind mounts (kavure)

| Host (kavure) | Container | Purpose |
|---|---|---|
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/app` | `/app` | Code |
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/logs` | `/app/logs` | Application logs |
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/migrations` | `/app/migrations:ro` | Alembic scripts |

> The LLM model cache (`llm_model_cache`, ~36G) lives **on psicopompo** (GPU workers mount it locally) — kavure does NOT mount it. The API uses ONNX embeddings downloaded on demand.

## Essential Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | `postgresql://stenio_user:{{DB_PASSWORD}}@db:5432/stenio_db` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth |
| `GOOGLE_REDIRECT_URI` | OAuth callback (e.g: `https://{{TAILSCALE_FUNNEL_DOMAIN}}/api/auth/callback`) |
| `STENIOBOT_OWNER_EMAIL` | Admin account (token bypass — configure via .env) |
| `SECRET_KEY` | Fernet master key |
| `SECURE_COOKIES` | `true` in production (HTTPS) |
| `ALLOWED_WS_ORIGINS` | Allowed origins for WebSocket/CSRF |
| `VALKEY_URL` | `redis://valkey:6379/0` |
| `HF_TOKEN` | Hugging Face token (Gemma 3 download) |
| `PURIFIER_TYPE` | `gemma` (default), `rtx`, `mock` |
| `USE_LLM` | Enables LLM purification |

> Full template: `docs/environment.md` in the original repo.

## Local control (sumaenima-ctl)

The SUMAENIMA GPU workers and Swarm services **do not start automatically** with the system.
To control them manually (`sumaenima-ctl` runs on psicopompo and reaches the kavure Swarm over SSH):

```bash
sumaenima-ctl status   # Ver estado atual (Swarm no kavure + GPU local)
sumaenima-ctl start    # Ligar Swarm services (kavure) + GPU workers (psicopompo)
sumaenima-ctl stop     # Desligar tudo (scale Swarm to 0, down GPU workers)
```

The script is at `~/.local/bin/sumaenima-ctl` (already in PATH).

### What does not start automatically

- Swarm services `sae-core_*` / `sae-edge_*` → `replicas: 0` until `sumaenima-ctl start`
- GPU workers (steniobot-vision, steniobot-audio, ollama) → `restart: no` (auto-exit after 180s idle to free VRAM)

### To bring it back up when needed

Ask an agent in chat to run `sumaenima-ctl start`.

## GPU

- **Runtime:** NVIDIA Container Toolkit (on psicopompo)
- **CUDA:** 12.2.2 (base image)
- **Minimum VRAM:** 6 GB (12 GB+ recommended)
- **Models:** faster-whisper (transcription) + Gemma 3 1B (LLM purification) — the cache lives on psicopompo

## Access

| Type | URL |
|---|---|
| Swarm overlay (other services) | `http://api:9090` |
| Tailscale (internal, kavure) | `http://100.124.146.77:9090` |
| Ybyra proxy (external edge) | `http://{{SUMAENIMA_DOMAIN}}/api/` |
| Funnel (public) | `https://{{TAILSCALE_FUNNEL_DOMAIN}}` |
| Health check | `http://100.124.146.77:9090/api/health` |
| API docs | `http://100.124.146.77:9090/docs` (Swagger) |

## Backup

| Data | Method |
|---|---|
| Code + git | Main repo at `/mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/` (GitHub) + deploy copy at `/srv/data/sumaenimahub/SUMAENIMA-HUB/` (kavure) |
| PostgreSQL database | Automatic daily backup at 03:00 via sentinel (Borg + pg_dump → psicopompo NFS) |

> **How it runs (29/08/2026):** systemd timer `hl-sumaenima-backup.timer` (kavure) → `/usr/local/bin/sumaenima-backup` (failsafe/retry/ntfy `/backup`) → `docker exec sae-core_backup python3 /app/scripts/backup/sentinel.py`. Marker `/app/logs/.backup_last_run` touched by the host (root); health file `/srv/health/sumaenima-backup-last-ok` (covered by Grafana's `BackupNotRun` alert via the textfile collector). The container's internal crond was **removed on 29/08** (the image runs as `appuser` since v2.22.0 and could not read `/etc/crontabs/root`).
| Logs | Bind mount in `./logs/` — manual backup |
| .env | In the repo (kavure `/srv/data/sumaenimahub/SUMAENIMA-HUB/.env` + psicopompo) |
| Model cache | On psicopompo (`llm_model_cache`) — can be downloaded again (`{{HF_TOKEN}}`) |

## Recovery

1. Clone the repo: `git clone https://github.com/ceduardorodrig/SUMAENIMA-HUB.git`
2. Copy `.env` from the backup (or use `.env.template` as the base)
3. Export env vars: `export $(grep -v '^#' .env | xargs)`
4. Deploy the stack (on kavure): `docker stack deploy -c provisioning/stacks/core.yml sae-core`
5. Migrations: `docker exec $(docker ps --filter name=sae-core_api -q) python3 -m alembic upgrade head`
6. Check health: `curl http://100.124.146.77:9090/api/health`
7. GPU workers (psicopompo): `sumaenima-ctl start`

> Detailed recovery: `docs/deployment.md` in the original repo (sections "Proteção de dados em renomeação de pasta" and "Recovery de volume órfão").

## Canonical Documentation

The detailed documentation for the transcription and minutes stack lives in the **Sumænimá Hub** repository (`docs/`):

| Module / Guide | Content |
|---|---|
| `deployment.md` | Deploy, migrations, recovery, checklist |
| `environment.md` | Environment variables and SOPS secrets |
| `connectivity.md` | Tailscale connectivity, Funnel and load balancing |
| `observability.md` | Prometheus metrics, Loki/Grafana, JSON logs |
| `security.md` | Security matrix and data isolation |
| `ci-github.md` | GitHub Actions CI/CD workflows |
| `alembic-workflow.md` | Migrations and database versioning |
| `architecture.md` | v3.0 architecture (100% Rust Axum backend) |

## Dependencies

- Docker Swarm (manager: kavure) + Docker Compose v2 (GPU workers on psicopompo)
- NVIDIA Container Toolkit (psicopompo)
- Tailscale (Funnel for public access — tunnel on ybyra)
- PostgreSQL 16 (app) + PostgreSQL 15 (Umami) — on kavure
- Valkey 8 (cache) — on kavure

## See also
- [[kavure]] — Swarm core where the stack runs
- [[kavure-disaster-recovery]] — Core server recovery
- [[psicopompo]] — GPU workers + build-node
- [[adguard-home]] — DNS
