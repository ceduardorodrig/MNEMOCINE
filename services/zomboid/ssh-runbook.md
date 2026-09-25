---
tags: [homelab, service, zomboid, tutorial]
---

# Zomboid — SSH Runbook

Manual operation of the **Project Zomboid** server on kavure via SSH. Source of truth: [`project-zomboid.md`](project-zomboid.md).

## Access

```bash
tailscale ssh kavure@kavure
```

## Operations scripts (`/usr/local/bin/zomboid-*`)

| Script | What it does |
|---|---|
| `zomboid-start` | Starts the server (`docker compose up -d`) |
| `zomboid-stop` | **Graceful** shutdown (RCON save + `docker compose down`) |
| `zomboid-restart` | **Graceful** restart (RCON save + `docker restart`; re-downloads/updates mods on boot) |
| `zomboid-status` | Container status + UDP ports |
| `zomboid-save <cmd>` | Sends an RCON command (save, broadcast, players…) |
| `zomboid-update` | Updates the **build** (save backup + FORCEUPDATE/steamcmd) |
| `zomboid-backup` | Off-box backup of the panel → psicopompo |

## Quick commands

```bash
tailscale ssh kavure@kavure
zomboid-status
zomboid-restart          # gracioso: salva o mundo + atualiza mods do Workshop
zomboid-stop             # gracioso: save antes de desligar
zomboid-start
zomboid-save save        # save manual via RCON
```

## Manual Docker equivalent

```bash
cd /srv/data/zomboid
docker compose up -d              # start
docker compose down               # stop (abrupto — prefira zomboid-stop)
docker compose restart pz-server  # restart (abrupto — prefira zomboid-restart)
docker compose ps                 # status
docker compose logs -f            # console
docker compose logs -f --tail 100
```

> ⚠️ Running `docker compose restart` directly is a **hard kill** (entry.sh does not trap SIGTERM) — that's why the `zomboid-restart`/`zomboid-stop` scripts save via RCON first.

## Status / ports

```bash
zomboid-status
docker ps --filter name=pz-server
ss -lunpt | grep -E '16261|16262|27015'
```

| Port | Protocol | Use |
|---|---|---|
| 16261 | UDP | Game |
| 16262 | UDP | Direct connect |
| 27015 | TCP | RCON |

## RCON

```bash
zomboid-save save                                # salva o mundo
zomboid-save 'servermsg "[SERVER] Aviso global"' # banner no topo da tela (avisos)
zomboid-save "broadcast Mensagem no chat"        # mensagem no chat
zomboid-save players                             # lista players (RCON não retorna saída neste build)
zomboid-save quit                                # sai do jogo → Docker reinicia o container (unless-stopped)
```

> **⚠️ `servermsg` ALWAYS with quotes** (`servermsg "mensagem"`): without quotes PZ shows only the first token (fix 10/08/2026). Use single quotes in the shell and double quotes inside the message.
> **Player count:** RCON `players` returns no data on this build — to check online players use `sudo -n /usr/local/libexec/zomboid-playercount` (reads the panel's `performance_history`, ~1 min of lag).

> **Standard warnings (07/08/2026):** the `zomboid-restart` (20s), `zomboid-stop` (10s) and `zomboid-update` scripts emit a `servermsg` **before** the action, warning that the server is going down (~1 min to save/update mods). The banner is **non-fatal** (if RCON fails, the action proceeds anyway).

> The script reads the RCON password from `/srv/data/zomboid/.env` and connects to `127.0.0.1`/`pz-server:27015`. The command is `argv[1]` — use quotes for commands with spaces.

> **Remote restart:** an RCON `quit` makes the game exit and the container restarts on its own (`restart: unless-stopped`), re-downloading the mods on boot — you can do it from the **panel console** on your phone (see [`onboarding`](onboarding.md)). Prefer `zomboid-restart` when possible (it saves first, explicitly).

## Mod update

1. `zomboid-restart` — on boot the game queries the Steam Workshop and downloads the updates (not entry.sh; the game itself does it).
2. Confirm in the game log:

```bash
grep -iE "workshop|NeedsUpdate|DownloadPending|installed to" \
  /srv/data/zomboid/data/Logs/*DebugLog-server.txt | tail
```

3. In the panel (Zomboid Control Panel), mods should be free of "Mod update available". If it persists, check that the panel reads `/pz-server/steamapps/workshop` (= `workshop-mods/`, bind added on 07/08/2026).

## Build update (steamcmd)

```bash
zomboid-update
```

Flow: compressed save backup → psicopompo (`archive/pre-update-<data>.tar.zst` via `zstd -3 -T0`), recreate with `FORCEUPDATE=true` (steamcmd validate), comes up normally.

> **After the update, re-apply the ZGC flags** — steamcmd overwrites `ProjectZomboid64.json`:

```bash
python3 -c "import json;p='/srv/data/zomboid/pz-dedicated/ProjectZomboid64.json';d=json.load(open(p));flags=['-XX:+ZUncommit','-XX:ZUncommitDelay=60','-XX:SoftMaxHeapSize=4g'];a=d.setdefault('vmArgs',[]);[a.append(f) for f in flags if f not in a];json.dump(d,open(p,'w'),indent=2)"
zomboid-restart
```

## Backup

- **Off-box (primary):** `zomboid-backup` (systemd `hl-zomboid-backup.timer`, **05:15**, `Persistent=true`) mirrors the panel's zips over **NFS** (`/srv/data/zomboid/offbox/daily/` = psicopompo NAS). Failsafe: reachability + retry (3×/2min) + timeouts + **ntfy** on failure — see `project-zomboid.md`.
- **Panel (local):** daily autobackup **00:00**, retention 7, in `/srv/data/zomboid/data/backups/`.
- **Pre-update:** `zomboid-update` saves to `offbox/archive/pre-update-<data>.tar.zst` (NFS).
- Saves: `/srv/data/zomboid/data/Saves/Multiplayer/pzserver`

## Logs

```bash
# Log do jogo (boot atual)
ls -lt /srv/data/zomboid/data/Logs/*DebugLog-server.txt
tail -f /srv/data/zomboid/data/Logs/*DebugLog-server.txt

# Console do container
docker logs -f pz-server

# Logs de restart/backup
tail -f /var/log/zomboid-restart.log
tail -f /var/log/zomboid-backup.log
```

## Schedules (systemd timers)

```ini
# hl-zomboid-restart.timer — 05:00, 11:00, 17:00, 23:00 (4x OnCalendar, Persistent=true)
# hl-zomboid-backup.timer  — 05:15 (Persistent=true)
```

- **Host timezone:** `America/Sao_Paulo` (configured on 07/08/2026 — before, the host was on UTC and the restarts ran 3h earlier).
- **watchtower** (`ops` stack container, **03:00 BRT**): updates the images of all containers, **including `pz-server`** — recreates the container with no RCON save (stop-timeout 30s); protected by autosave + panel/off-box backups.

## Web panel (Zomboid Control Panel)

- **URL:** `http://kavure.chimaera-heptatonic.ts.net:3001`
- **Features:** RCON console, players, live map, mod manager, backup, save/broadcast scheduler, events/weather.
- It does **not** start/stop the container (a false "stopped" is expected — the lifecycle belongs to Docker, via `zomboid-*`).
- **Mods:** the panel reads the workshop at `/pz-server/steamapps/workshop` (bind of `workshop-mods/`). On 07/08/2026 it was fixed: the old copy in `pz-dedicated/steamapps/workshop` (which caused a permanent "Mod update available") was removed.

## Troubleshooting

- **Stuck on "Joining Game" in the client?** Version mismatch (e.g. Build 42.20.2 vs 42.20.3).
  - In the client (`console.txt`), `BufferUnderflowException: ChunkNotReadyPacket.parse` shows up.
  - Fix: run `zomboid-update` on `kavure` or sync `projectzomboid.jar` with a hash identical to the client's.
- **Server won't come up?** `docker logs pz-server --tail 100` + `zomboid-status`.
- **World not saved?** `zomboid-save save`; restore via the panel (backups) or the off-box `daily/`.
- **High RAM at idle?** `zomboid-stop` frees it all; the 4x/day restart (05/11/17/23) clears the heap.

## See also
- [[project-zomboid]] — Project Zomboid server (Docker on kavure)
- [[zomboid-control-panel]] — Web panel
- [[kavure]] — Target server
- [[kavure-disaster-recovery]] — Full restore from the off-box

