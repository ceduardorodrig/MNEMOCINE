---
tags: [homelab, service, zomboid, gaming]
---

# Project Zomboid — Dedicated Server Specification

Dedicated server deployment for **Project Zomboid (Build 42)**.

**Current Host:** kavure (**Docker** — `danixu86/project-zomboid-dedicated-server`)  
**Previous Host:** psicopompo (LinuxGSM) — **DECOMMISSIONED** (systemd units, users, and cron triggers purged 2026-08-06; see [`zomboid-psicopompo-handoff.md`](zomboid-psicopompo-handoff.md))  

## Overview

- **Build Version:** Build 42 (**public / stable**)
- **Orchestration:** **Docker Compose** on kavure
- **Network Ports:** `16261` (gameplay), `16262` (direct connection) — UDP; `27015` — TCP (Source RCON)
- **Player Capacity:** 15 slots
- **Mod Index:** **125 Workshop items + 148 Mod IDs** (Full KI5 B42 multiplayer vehicle collection enrolled)
- **Management Portal:** Zomboid Control Panel (see [`zomboid-control-panel.md`](zomboid-control-panel.md))

## Filesystem Layout on Host (kavure)

| Component | Filesystem Path | Container Target |
|---|---|---|
| Stack Definition | `/srv/data/zomboid/` | `docker-compose.yml` + `.env` |
| Save Data & Config | `/srv/data/zomboid/data/` | `/home/steam/Zomboid` |
| Workshop Mod Cache | `/srv/data/zomboid/workshop-mods/` | `/home/steam/pz-dedicated/steamapps/workshop` |
| Application Daemon | `pz-server` container | Image: `danixu86/project-zomboid-dedicated-server` |

> **Workshop Mod Storage:** LinuxGSM historically cached items under `linuxgsm/serverfiles/steamapps/workshop/`, not in `Zomboid/Workshop/`. In this container deployment, that hierarchy maps directly to `workshop-mods/`.

## Lifecycle Management & Operational Scripts

Quick operational CLI helpers deployed to `/usr/local/bin/`:

```bash
zomboid-start      # Launches the container stack
zomboid-stop       # Executes graceful shutdown (RCON save + docker compose down)
zomboid-restart    # Executes graceful restart (RCON save + container restart)
zomboid-status     # Displays runtime container metrics and port listeners
zomboid-save       # Issues RCON "save" command via Source RCON Python client
```

> **`zomboid-restart` Graceful Handshake:**  
> The container's internal entry script does not catch SIGTERM cleanly (PID 1 bash forwards directly to hard-kill on raw `docker compose restart`). The `zomboid-restart` script issues an explicit `save` command via RCON prior to container restart, logging events to `/var/log/zomboid-restart.log`.

Manual Docker equivalent:
```bash
cd /srv/data/zomboid
docker compose up -d              # Start daemon
docker compose down               # Stop daemon
docker compose restart pz-server  # Raw restart
docker compose logs -f            # Live log tail
```

## Architectural Decoupling: Game Daemon vs. Control Panel

The Zomboid Control Panel runs in a distinct container namespace and does not manipulate external container states directly. Responsibilities are divided as follows:

| Capability | Control Panel UI | Host Docker Stack | Execution Standard |
|---|---|---|---|
| RCON / Console / In-game Administration | ✅ | — | Executed through web UI console |
| Active Players / Live Map / Mod Catalog / Backups | ✅ | — | Managed via RCON + PanelBridge |
| **Container Lifecycle (Start / Stop / Restart)** | ❌ | ✅ | CLI scripts (`zomboid-start/stop/restart`) |
| **Process Status (Running / Stopped)** | ❌ (False stopped) | ✅ | Validated via `zomboid-status` |
| **Game Binary Updates** | ❌ | ✅ | Executed via `zomboid-update` |
| **Automated Restart Schedule** | ❌ | ✅ | Systemd timer `hl-zomboid-restart.timer` |

## Environment Configuration (`.env`)

| Environment Variable | Operational Value | Purpose |
|---|---|---|
| `STEAMAPPBRANCH` | `public` | Build 42 stable branch |
| `SERVERNAME` | `pzserver` | Matches persistent world config (`pzserver.ini`) |
| `PUBLIC` | `true` | Enables public browser visibility |
| `MAX_MEMORY` | `6144m` | Maximum JVM heap ceiling (`-Xmx6g`) |
| `MIN_MEMORY` | `1024m` | Dynamic initial JVM heap allocation (`-Xms1g`) |
| `RCONPASSWORD` | (Stored in SOPS) | Secret authentication token for RCON and CLI scripts |
| `SELF_MANAGED_MODS` | `true` | Prevents automated scripts from overwriting custom mod definitions |

### JVM Memory Management (ZGC Tuning)

Configured inside `ProjectZomboid64.json` (`/srv/data/zomboid/pz-dedicated/`):
- `-XX:+ZUncommit`: Returns unallocated memory pages back to host operating system.
- `-XX:ZUncommitDelay=60`: Accelerates memory reclamation cycle (default 300s).
- `-XX:SoftMaxHeapSize=4g`: Soft threshold targeting ≤ 4 GB heap during normal gameplay, bursting up to 6 GB (`-Xmx6g`) only during peak zombie horde simulations.

## Automated Maintenance Windows (4× Daily Restart)

Configured via `hl-zomboid-restart.timer` running at **05:00, 11:00, 17:00, and 23:00 BRT**:

- **Workshop Synchronization:** Every reboot triggers SteamCMD checks, pulling mod updates before initializing game world physics.
- **Heap Refresh:** Cleanses fragmented memory allocation and garbage collection heaps.
- **Player-Respecting Automation:** Systemd service executes with `Environment=RESPECT_PLAYERS=1`. If active players are detected on the server via `zomboid-playercount`, the restart cycle is cleanly deferred until the subsequent maintenance window.
- **Advance Warning:** Approximately 20 seconds before restart, a broadcast banner warns connected players (`[SERVER] Server restart in ~20s...`).

## Compressed RAM Swap (zram)

Kavure utilizes compressed in-memory swap (**zram**) exclusively, avoiding disk-bound swap file latency:
- Block device: `/dev/zram0` (11.5 GB allocated, 100% of physical RAM capacity).
- Compression algorithm: `zstd`.
- Traditional on-disk `/swap.img` was deactivated and deleted on 2026-08-06.

## Backup & Disaster Recovery Architecture

- **Off-Box NAS Mirror (Primary):** `zomboid-backup` triggers at **05:15 BRT** (`hl-zomboid-backup.timer`), synchronizing daily zip archives to the primary NAS over NFS (`/srv/data/zomboid/offbox/daily/` → psicopompo `/mnt/BACKUP/zomboid-server-kavure/`).
  - Strict failsafe: TCP port 2049 reachability probes fail-fast if NAS is offline, retrying up to 3 times before pushing mobile alerts via ntfy (`/backup`).
- **Pre-Update Compression:** `zomboid-update` generates a dedicated `tar.zst` snapshot stored in `offbox/archive/pre-update-<date>.tar.zst`.
- **Local Control Panel Backups:** Generates local rolling archives daily at midnight (`backupSchedule: 0 0 * * *`) with a 7-day retention limit.

## See Also
- [`../../servers/kavure.md`](../../servers/kavure.md) — Kavure dedicated services node profile
- [`zomboid-control-panel.md`](zomboid-control-panel.md) — Web administration interface
- [`onboarding.md`](onboarding.md) — Player onboarding guide
