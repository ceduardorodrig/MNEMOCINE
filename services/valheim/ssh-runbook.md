---
tags: [homelab, service, valheim, tutorial]
---

# Valheim — SSH Runbook

Manual operation of the **Valheim** server on kavure via SSH. Source of truth: [`valheim-server.md`](valheim-server.md).

## Access

```bash
tailscale ssh kavure@kavure
```

## Operations scripts (`/usr/local/bin/valheim-*`)

| Script | What it does |
|---|---|
| `valheim-start` | Starts the server (`docker compose up -d`) |
| `valheim-stop` | Stops the server (`docker compose down`) |
| `valheim-restart` | Restarts the server (`docker compose restart`) |
| `valheim-status` | Container status + UDP ports + resources |
| `valheim-backup` | Off-box backup via rsync → psicopompo NFS |
| `valheim-playercount` | Shows connected players (via log) |

## Quick commands

```bash
tailscale ssh kavure@kavure
valheim-status
valheim-restart
valheim-stop
valheim-start
valheim-backup
```

## Manual Docker equivalent

```bash
cd /srv/data/valheim
docker compose up -d              # start
docker compose down               # stop (gracioso — salva antes via AUTO_BACKUP_ON_SHUTDOWN)
docker compose restart valheim    # restart (rápido — sem save explícito)
docker compose ps                 # status
docker compose logs -f            # console
docker compose logs -f --tail 100
```

> **Unlike Zomboid:** Valheim has no RCON — you cannot force a remote save via command. The container saves automatically every 30 min (`AUTO_BACKUP`) and before shutdown/update.

## Status / ports

```bash
valheim-status
docker ps --filter name=valheim-server
ss -lunpt | grep -E '2456|2457|2458'
```

| Port | Protocol | Use |
|---|---|---|
| 2456 | UDP | Game (primary) |
| 2457 | UDP | Game (backup) |
| 2458 | UDP | Game (backup) |

## Backup

- **Off-box (primary):** `valheim-backup` (rsync `--delete` from `/srv/data/valheim/saves/worlds_local/` → psicopompo NFS `/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`). Fixed on 13/09/2026 (the old path `config/backups/` did not exist in this setup).
- **Container (local):** `AUTO_BACKUP` every 30 min into `/home/steam/backups` (`./backups`, persisted since 13/09). Retention 7 days.
- **Pre-update:** `AUTO_BACKUP_ON_UPDATE=1` saves before updating
- **Pre-shutdown:** `AUTO_BACKUP_ON_SHUTDOWN=1` saves before shutting down
- World data: `/srv/data/valheim/saves/worlds_local/` (Fimbulvetr.db + Fimbulvetr.fwl + auto-backups)

## Logs

```bash
# Log do jogo
tail -f /srv/data/valheim/config/valheim_server.log

# Console do container
docker logs -f valheim-server

# Logs de restart/backup
tail -f /var/log/valheim-restart.log
tail -f /var/log/valheim-backup.log

# Últimas linhas com mods
docker logs valheim-server --tail 200 2>&1 | grep -iE 'BepInEx|Plugin|Error|Exception'
```

## Schedules (systemd timers)

```ini
# hl-valheim-restart.timer — 05:00 diário (Persistent=true)
# hl-valheim-backup.timer  — 05:30 diário (Persistent=true)
```

- **Host timezone:** `America/Sao_Paulo`
- **watchtower** (`ops` stack container, **03:00 BRT**): updates `valheim-server` — recreates the container with stop-timeout 30s; `AUTO_BACKUP_ON_UPDATE=1` saves first.

## Mod update

1. Edit `MODS:` in `/srv/data/valheim/docker-compose.yml`
2. `valheim-restart` — on boot BepInEx downloads/installs the mods automatically
3. Confirm in the log:

```bash
docker logs valheim-server --tail 100 2>&1 | grep -iE 'BepInEx|Plugin|Loading'
```

## Version update (steamcmd)

The `AUTO_UPDATE` cron running `0 3 * * *` (03:00) already does automatic updates. To do it manually:

```bash
cd /srv/data/valheim
docker compose down
docker compose up -d
# steamcmd roda no boot e atualiza se necessário
```

## Troubleshooting

- **Container won't come up?** `docker logs valheim-server --tail 100` + `valheim-status`
- **Corrupted world?** Restore from `/srv/data/valheim/saves/worlds_local/` (most recent backup) or from the off-box NFS
- **Broken mods?** Check `BepInEx/LogOutput.log` — compile errors indicate an incompatibility
- **Empty world (terrain only)?** `frame tag 0x48` in the log → SmoothServer Compression broke; see [[valheim-server#SmoothServer Compression incompatible with Valheim 1.0.12 (empty world)]]
- **High RAM?** Valheim uses ~1-2 GB at idle; `valheim-restart` clears the heap
- **Slow connection?** SmoothServer monitors peers — check the `[PeerTelemetry]` logs

## See also

- [[valheim-server]] — Valheim server (Docker on kavure)
- [[onboarding]] — Player guide
- [[kavure]] — Target server
- [[project-zomboid]] — Zomboid server (reference pattern)
