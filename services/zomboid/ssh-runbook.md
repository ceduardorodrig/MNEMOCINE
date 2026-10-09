---
tags: [homelab, service, zomboid, tutorial]
---

# Project Zomboid — SSH Operations Runbook

Operational and maintenance procedures for the dedicated **Project Zomboid** server on kavure via SSH. Canonical architecture: [`project-zomboid.md`](project-zomboid.md).

## Access Endpoint

```bash
tailscale ssh kavure@kavure
```

## Operations Scripts (`/usr/local/bin/zomboid-*`)

| Script | Operational Function |
|---|---|
| `zomboid-start` | Starts the container daemon (`docker compose up -d`) |
| `zomboid-stop` | Graceful shutdown (issues RCON `save` followed by `docker compose down`) |
| `zomboid-restart` | Graceful restart (issues RCON `save`, restarts container, checks Workshop mods) |
| `zomboid-status` | Displays container state, bound UDP sockets, and resource utilization |
| `zomboid-save <cmd>` | Transmits raw command over Source RCON protocol (`save`, `broadcast`, etc.) |
| `zomboid-update` | Upgrades game binary build via SteamCMD after taking a compressed world backup |
| `zomboid-backup` | Synchronizes local backup archives to the off-box NAS target over NFS |

## Quick Command Reference

```bash
tailscale ssh kavure@kavure
zomboid-status
zomboid-restart          # Graceful: flushes world state and pulls Steam Workshop updates
zomboid-stop             # Graceful: saves world prior to container shutdown
zomboid-start
zomboid-save save        # Triggers manual world save via RCON
```

## Manual Docker Equivalent

```bash
cd /srv/data/zomboid
docker compose up -d              # Launch daemon
docker compose down               # Abrupt stop (prefer zomboid-stop)
docker compose restart pz-server  # Abrupt restart (prefer zomboid-restart)
docker compose ps                 # Container state
docker compose logs -f --tail 100 # Live log tail
```

> ⚠️ Running `docker compose restart` directly bypasses graceful save handlers (container PID 1 bash does not trap SIGTERM cleanly). Always use `zomboid-restart` or issue `zomboid-save save` first.

## Network Port Validation

```bash
zomboid-status
docker ps --filter name=pz-server
ss -lunpt | grep -E '16261|16262|27015'
```

| Port | Protocol | Purpose |
|---|---|---|
| 16261 | UDP | Primary gameplay connection |
| 16262 | UDP | Direct client connection |
| 27015 | TCP | Source RCON management interface |

## Source RCON Commands

```bash
zomboid-save save                                # Flushes world state to disk
zomboid-save 'servermsg "[SERVER] Alert text"'   # Displays broadcast banner across top of screen
zomboid-save "broadcast Chat message"            # Sends standard in-game chat message
zomboid-save quit                                # Triggers engine exit (Docker restarts container automatically)
```

> ⚠️ Always enclose messages in double quotes (`servermsg "message text"`). Without quotes, the game engine parses only the first word.

## Workshop Mod Updates

1. Execute `zomboid-restart` — upon initialization, the server checks the Steam Workshop and downloads updated mod archives.
2. Confirm updates inside the runtime server logs:
```bash
grep -iE "workshop|NeedsUpdate|DownloadPending|installed to" \
  /srv/data/zomboid/data/Logs/*DebugLog-server.txt | tail
```

## Binary Build Upgrades (SteamCMD)

```bash
zomboid-update
```

The script automatically executes a fast compressed backup (`tar` piped to `zstd -3 -T0`), pushes the snapshot to `/mnt/BACKUP/zomboid-server-kavure/archive/pre-update-<date>.tar.zst`, and triggers SteamCMD build verification.

> After a binary build upgrade, re-apply custom ZGC JVM tuning flags inside `ProjectZomboid64.json` before restarting:
```bash
python3 -c "import json;p='/srv/data/zomboid/pz-dedicated/ProjectZomboid64.json';d=json.load(open(p));flags=['-XX:+ZUncommit','-XX:ZUncommitDelay=60','-XX:SoftMaxHeapSize=4g'];a=d.setdefault('vmArgs',[]);[a.append(f) for f in flags if f not in a];json.dump(d,open(p,'w'),indent=2)"
zomboid-restart
```

## Automated Maintenance Timers

```ini
# hl-zomboid-restart.timer — 05:00, 11:00, 17:00, 23:00 BRT
# hl-zomboid-backup.timer  — 05:15 BRT
```

Host timezone is set to `America/Sao_Paulo`. If active players are connected during a scheduled restart interval, `hl-zomboid-restart.service` defers execution until the subsequent cycle.

## Troubleshooting

- **Client stuck on "Joining Game" screen:** Typically indicates a binary version mismatch (e.g. client on Build 42.20.3 while server runs 42.20.2). Verify `md5sum projectzomboid.jar` between client and server.
- **Container fails to start:** Inspect `docker logs pz-server --tail 100` and check for file permission issues under `/srv/data/zomboid/pz-dedicated/`.

## See Also
- [`project-zomboid.md`](project-zomboid.md) — Dedicated server specification
- [`zomboid-control-panel.md`](zomboid-control-panel.md) — Web administration console
- [`../../servers/kavure.md`](../../servers/kavure.md) — Hosting server node profile
