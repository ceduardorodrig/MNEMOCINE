---
tags: [homelab, service, steniobot, docker, env, ssl]
---

# StênioBOT

Bot de relatoria com IA para reuniões institucionais.

**Servidor:** kavure (Swarm manager, role: core) — migrado do psicopompo em 07/08/2026
**Stack:** `sae-core` (Docker Swarm) no kavure; GPU workers no psicopompo (role: gpu)
**Porta:** `9090` (publicada no host do kavure para monitoria via Tailscale)
**URL interna:** `http://api:9090` (overlay network `sumaenima_sumaenima-net`)
**URL Tailscale:** `http://100.124.146.77:9090`
**Funnel:** `{{TAILSCALE_FUNNEL_DOMAIN}}` → `https` (via tunnel no ybyra)

## Stack (Docker Swarm)

| Service | Imagem | Portas | Função |
|---|---|---|---|
| sae-core_api | sumaenima-server:latest | `0.0.0.0:9090` | Aplicação Rust Axum 0.8 + React 19 WASM Client |
| sae-core_db | postgres:16-alpine | — | Banco de dados principal |
| sae-core_valkey | valkey/valkey:8-alpine | — | Cache distribuído + sessão |
| sae-core_backup | sumaenimahub-backup-sentinel:latest | `0.0.0.0:9092` | Backup automático (Borg + pg_dump) |

### Containers Avulsos (fora do Swarm, na rede overlay)

| Container | Função |
|---|---|
| steniobot_vision | Serviço de visão computacional (overlay) |
| steniobot_audio | Serviço de áudio/transcrição (overlay) |

## Volumes

### Volumes (kavure — bind mounts em /srv/data/sumaenimahub/)

| Volume/Dir | Container | Persiste |
|---|---|---|
| `/srv/data/sumaenimahub/volumes/sumaenimahub_postgres_data/_data` | sae-core_db | Dados PostgreSQL |
| `/srv/data/sumaenimahub/volumes/sumaenimahub_umami_data/_data` | sae-core_umami-db | Dados Umami |
| `/srv/data/sumaenimahub/volumes/sumaenimahub_valkey_data/_data` | sae-core_valkey | Cache Valkey |
| `/srv/data/sumaenimahub/backup` | sae-core_backup | Backup NFS → psicopompo `/mnt/BACKUP/sumaenima-server-kavure/` |

### Bind mounts (kavure)

| Host (kavure) | Container | Finalidade |
|---|---|---|
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/app` | `/app` | Código |
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/logs` | `/app/logs` | Logs da aplicação |
| `/srv/data/sumaenimahub/SUMAENIMA-HUB/migrations` | `/app/migrations:ro` | Scripts Alembic |

> O cache de modelos LLM (`llm_model_cache`, ~36G) vive **no psicopompo** (GPU workers montam local) — o kavure NÃO o monta. A API usa embeddings ONNX baixados sob demanda.

## Variáveis de Ambiente Essenciais

| Variável | Descrição |
|---|---|
| `DATABASE_URL` | `postgresql://stenio_user:{{DB_PASSWORD}}@db:5432/stenio_db` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | OAuth Google |
| `GOOGLE_REDIRECT_URI` | Callback OAuth (ex: `https://{{TAILSCALE_FUNNEL_DOMAIN}}/api/auth/callback`) |
| `STENIOBOT_OWNER_EMAIL` | Conta admin (bypass de tokens — configurar via .env) |
| `SECRET_KEY` | Chave mestra Fernet |
| `SECURE_COOKIES` | `true` em produção (HTTPS) |
| `ALLOWED_WS_ORIGINS` | Origens permitidas para WebSocket/CSRF |
| `VALKEY_URL` | `redis://valkey:6379/0` |
| `HF_TOKEN` | Token Hugging Face (download Gemma 3) |
| `PURIFIER_TYPE` | `gemma` (default), `rtx`, `mock` |
| `USE_LLM` | Habilita purificação LLM |

> Template completo: `docs/environment.md` no repo original.

## Controle local (sumaenima-ctl)

Os GPU workers e Swarm services do SUMAENIMA **não iniciam automaticamente** com o sistema.
Para controlar manualmente (o `sumaenima-ctl` roda no psicopompo e acessa o Swarm do kavure via SSH):

```bash
sumaenima-ctl status   # Ver estado atual (Swarm no kavure + GPU local)
sumaenima-ctl start    # Ligar Swarm services (kavure) + GPU workers (psicopompo)
sumaenima-ctl stop     # Desligar tudo (scale Swarm to 0, down GPU workers)
```

O script está em `~/.local/bin/sumaenima-ctl` (já no PATH).

### O que não inicia automaticamente

- Swarm services `sae-core_*` / `sae-edge_*` → `replicas: 0` até `sumaenima-ctl start`
- GPU workers (steniobot-vision, steniobot-audio, ollama) → `restart: no` (auto-exit por idle 180s p/ liberar VRAM)

### Para religar quando necessário

Peça no chat para um agente executar `sumaenima-ctl start`.

## GPU

- **Runtime:** NVIDIA Container Toolkit (no psicopompo)
- **CUDA:** 12.2.2 (imagem base)
- **VRAM mínima:** 6 GB (recomendado 12 GB+)
- **Modelos:** faster-whisper (transcrição) + Gemma 3 1B (purificação LLM) — cache vive no psicopompo

## Acesso

| Tipo | URL |
|---|---|
| Overlay Swarm (outros serviços) | `http://api:9090` |
| Tailscale (interno, kavure) | `http://100.124.146.77:9090` |
| Proxy Ybyra (borda externa) | `http://{{SUMAENIMA_DOMAIN}}/api/` |
| Funnel (público) | `https://{{TAILSCALE_FUNNEL_DOMAIN}}` |
| Health check | `http://100.124.146.77:9090/api/health` |
| API docs | `http://100.124.146.77:9090/docs` (Swagger) |

## Backup

| Dado | Método |
|---|---|
| Código + git | Repo principal em `/mnt/NVME_PCI/agentic-ai/sumaenimahub/sumaenima-hub/` (GitHub) + cópia de deploy em `/srv/data/sumaenimahub/SUMAENIMA-HUB/` (kavure) |
| Banco PostgreSQL | Backup automático diário 03:00 via sentinel (Borg + pg_dump → NFS psicopompo) |

> **Como roda (29/08/2026):** systemd timer `hl-sumaenima-backup.timer` (kavure) → `/usr/local/bin/sumaenima-backup` (failsafe/retry/ntfy `/backup`) → `docker exec sae-core_backup python3 /app/scripts/backup/sentinel.py`. Marcador `/app/logs/.backup_last_run` tocado pelo host (root); health file `/srv/health/sumaenima-backup-last-ok` (coberto pelo alerta `BackupNotRun` do Grafana via textfile collector). O crond interno do container foi **removido em 29/08** (a imagem roda como `appuser` desde v2.22.0 e não lia `/etc/crontabs/root`).
| Logs | Bind mount em `./logs/` — backup manual |
| .env | No repo (kavure `/srv/data/sumaenimahub/SUMAENIMA-HUB/.env` + psicopompo) |
| Modelos cache | No psicopompo (`llm_model_cache`) — pode ser baixado novamente (`{{HF_TOKEN}}`) |

## Recovery

1. Clonar repo: `git clone https://github.com/ceduardorodrig/SUMAENIMA-HUB.git`
2. Copiar `.env` do backup (ou usar `.env.template` como base)
3. Exportar env vars: `export $(grep -v '^#' .env | xargs)`
4. Deploy stack (no kavure): `docker stack deploy -c provisioning/stacks/core.yml sae-core`
5. Migrations: `docker exec $(docker ps --filter name=sae-core_api -q) python3 -m alembic upgrade head`
6. Verificar health: `curl http://100.124.146.77:9090/api/health`
7. GPU workers (psicopompo): `sumaenima-ctl start`

> Recovery detalhado: `docs/deployment.md` no repo original (seções "Proteção de dados em renomeação de pasta" e "Recovery de volume órfão").

## Documentação Canônica

A documentação detalhada da stack de relatoria e transcrição reside no repositório **Sumænimá Hub** (`docs/`):

| Módulo / Guia | Conteúdo |
|---|---|
| `deployment.md` | Deploy, migrações, recovery, checklist |
| `environment.md` | Variáveis de ambiente e segredos SOPS |
| `connectivity.md` | Conectividade Tailscale, Funnel e balanceamento |
| `observability.md` | Métricas Prometheus, Loki/Grafana, logs JSON |
| `security.md` | Matriz de segurança e isolamento de dados |
| `ci-github.md` | Workflows CI/CD GitHub Actions |
| `alembic-workflow.md` | Migrações e versionamento de banco |
| `architecture.md` | Arquitetura v3.0 (100% Rust backend Axum) |

## Dependências

- Docker Swarm (manager: kavure) + Docker Compose v2 (GPU workers no psicopompo)
- NVIDIA Container Toolkit (psicopompo)
- Tailscale (Funnel para acesso público — tunnel no ybyra)
- PostgreSQL 16 (app) + PostgreSQL 15 (Umami) — no kavure
- Valkey 8 (cache) — no kavure

## See also
- [[kavure]] — Core do Swarm onde a stack roda
- [[kavure-disaster-recovery]] — Recovery do servidor core
- [[psicopompo]] — GPU workers + build-node
- [[adguard-home]] — DNS
