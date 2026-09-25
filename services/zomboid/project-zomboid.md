---
tags: [homelab, service, zomboid, gaming]
---

# Project Zomboid

Dedicated **Project Zomboid (Build 42)** server.

**Current server:** kavure (**Docker** — `danixu86/project-zomboid-dedicated-server`)
**Previous server:** psicopompo (LinuxGSM) — **SHUT DOWN** (service/timers/user disabled on 06/08/2026; data left untouched on disk — see [[zomboid-psicopompo-handoff]])

## Summary

- **Version:** Build 42 (**stable**)
- **Management:** **Docker Compose** on kavure (before: LinuxGSM)
- **Ports:** `16261` (game), `16262` (direct connection) — UDP; `27015` — TCP (RCON)
- **Max players:** 15
- **Mods:** **125 Workshop + 148 Mod IDs** (15/08: **full KI5 B42 MP collection** added — 39 new items; collection ID `3652192243` is invalid in `WorkshopItems=` and was removed; the total includes multi-mod packs: Mini Mk2 → 4, Jeep YJ → 2, Cadillac Miller-Meteor → `59meteor`+`ECTO1`)
- **Admin/Panel:** Zomboid Control Panel (see [`zomboid-control-panel`](zomboid-control-panel.md))

## Current location (kavure — Docker)

| Item | Path |
|---|---|
| Stack | `/srv/data/zomboid/` (docker-compose.yml + .env) |
| Data (saves/config) | `/srv/data/zomboid/data/` (volume → `/home/steam/Zomboid`) |
| Workshop Mods | `/srv/data/zomboid/workshop-mods/` (volume → `/home/steam/pz-dedicated/steamapps/workshop`) |
| Container | `pz-server` (image `danixu86/...`) |

> **⚠️ Workshop mods live in `linuxgsm/serverfiles/steamapps/workshop/`** on LinuxGSM, **not** in `Zomboid/Workshop/` (which stays empty). In the migration, that path was mapped to `workshop-mods/`.

> **Installing new mods (10/08/2026):** just add the ID in `WorkshopItems=` + the mod.info `id=` in `Mods=` on `pzserver.ini` and restart (the game downloads from Workshop on boot; it may need 2 restarts). **Staircast and ZombieBuddy were removed on 10/08** (Staircast required the ZombieBuddy Java framework, which in turn required manual installation on every player's client — dropped). See [`onboarding`](onboarding.md).

> **⚠️ Workshop collections do NOT work in `WorkshopItems=`** (only individual item IDs, semicolon-separated). On 15/08/2026 the KI5 collection (`3652192243`) was removed and its 39 missing items were added individually (`pzserver.ini.bak-20260815` has the previous state). To install a collection: extract the individual IDs → `WorkshopItems=`, restart (download), read `mod.info`/`id=` of each new item → `Mods=`, restart again.

> **Panel and workshop (07/08/2026):** Zomboid Control Panel reads the mods via a bind of `workshop-mods/` at `/pz-server/steamapps/workshop` (overlay in the panel's compose). The old copy at `pz-dedicated/steamapps/workshop/` — which caused a permanent "Mod update available" — was **removed** (1.3G). See [`zomboid-control-panel`](zomboid-control-panel.md).

## Management (Docker)

**Quick commands (scripts on kavure):**

```bash
zomboid-start      # inicia o servidor
zomboid-stop       # para o servidor
zomboid-restart    # reinicia o servidor (save RCON + docker restart)
zomboid-status     # mostra status + porta
zomboid-save       # envia comando RCON "save" (client Source RCON em Python)
```

> **`zomboid-restart` is graceful:** it runs `save` via RCON before the restart, because the container's entry.sh **does not trap SIGTERM** (PID1 = bash → java gets hard-killed if you use `docker compose restart` directly). The log is at `/var/log/zomboid-restart.log`.

Manual equivalent (in `/srv/data/zomboid`):

```bash
cd /srv/data/zomboid
docker compose up -d            # start
docker compose down             # stop
docker compose restart pz-server # restart
docker compose logs -f          # console
docker compose ps               # status
```

> **⚠️ The panel (Zomboid Control Panel) does NOT control start/stop** — PZ runs in a separate container, and the panel cannot see processes from other containers (a constant "stopped" status is a false negative). The lifecycle is managed by Docker via `zomboid-*`. The panel is for RCON/console/players/mods/backup.

## Architecture Limitations (PZ in a separate container)

> **Context:** the panel controls the server by spawning `start-server.sh` as a host process. With PZ in a separate Docker container, there is a split of responsibilities:

| Capability | Panel | Docker | How to do it |
|---|---|---|---|
| RCON / console / admin commands | ✅ | — | panel (RCON connected) |
| Online players / map / mods / config / backup | ✅ | — | panel (RCON + PanelBridge) |
| **Start / Stop / Restart** | ❌ | ✅ | `zomboid-start/stop/restart` |
| **Real status (running/stopped)** | ❌ (false "stopped") | ✅ | `zomboid-status` |
| **Game update (Build)** | ❌ | ✅ | `zomboid-update` |
| **Scheduled restart (Scheduler)** | ❌ | ✅ | systemd timer `hl-zomboid-restart.timer` (kavure) |
| **Install a new server (wizard)** | ❌ | ✅ | via Docker |

**Reading:** the panel administers **the game** (players, map, mods, config, backups, commands); **Docker manages the process** (start/stop/status/update). The panel's "stopped" indicator is expected and does not signal a failure.

**To update mods:** just `zomboid-restart` (PZ downloads Workshop updates on startup — confirmed in the original LinuxGSM docs and the Danixu container).

## Configuration (`.env` — LOCAL, do not commit)

| Variable | Value | Note |
|---|---|---|
| `STEAMAPPBRANCH` | `public` | Build 42 (stable — renamed from `stable` to `public` by Valve in 08/2026) |
| `SERVERNAME` | `pzserver` | Must match the migrated `pzserver.ini` |
| `PUBLIC` | `true` | Visible in the browser |
| `MAX_MEMORY` | `6144m` | Heap ceiling (Xmx) |
| `MIN_MEMORY` | `1024m` | Initial heap (Xms) — **dynamic growth** (1G→6G on demand) |
| `RCONPASSWORD` | (generated) | RCON for the panel + `zomboid-save` |
| `SELF_MANAGED_MODS` | `true` | Does not overwrite `Mods=`/`WorkshopItems=` |

### Memory (JVM)

- `-Xms${MIN_MEMORY} -Xmx${MAX_MEMORY}` applied by entry.sh → `-Xms1024m -Xmx6144m` (confirmed in `ps`).
- **Dynamic:** the JVM starts at ~1 GB and only "commits" RAM as the heap grows — it does not reserve 6 GB while idle.
- **ZGC flags** (in `ProjectZomboid64.json`, host volume `/srv/data/zomboid/pz-dedicated/`):
  - `-XX:+ZUncommit` — returns RAM to the OS (ON by default, explicit for clarity)
  - `-XX:ZUncommitDelay=60` — speeds up the return (default 300s)
  - `-XX:SoftMaxHeapSize=4g` — **4 GB "soft" target**: ZGC tries to keep the heap ≤ 4 GB (more active GC), growing up to 6 GB (Xmx) only if needed to avoid stalling. It is ZGC's native knob for "use the minimum with a safety ceiling".
  - ⚠️ **`-XX:Min/MaxHeapFreeRatio` are NOT ZGC knobs** (they belong to Parallel/G1) — no proven effect here (source: Oracle ZGC docs + openjdk/zgc analysis).
  - ⚠️ **`zomboid-update` (steamcmd `validate`) overwrites the JSON** → **reapply the flags after any update**. The backup of the flagless state is kept in `ProjectZomboid64.json.bak`.
- **Realistic expectation:** the loaded world + 65 mods pull ~5–7 GB RSS at peak; `SoftMaxHeapSize=4g` encourages using less while idle, but with `PauseEmpty=true` the world stays paused yet **resident** — the idle gain is modest (the memory is live set, not waste). To zero out RAM while idle, `zomboid-stop` is the only real way.
- **⚠️ Memory only changes via `.env` + `docker compose up -d`** (recreate) for Xms/Xmx; JVM flags in `ProjectZomboid64.json` + `zomboid-restart`. `docker compose restart` does **not re-read** the `.env`. The panel's memory field **does not affect the container**.

## Scheduled maintenance (restart 4x/day)

Restart at **05:00, 11:00, 17:00 and 23:00** (exactly 6h apart — 4x/day, more chances to check/update mods) via systemd timer **`hl-zomboid-restart.timer`** (4× `OnCalendar`, `Persistent=true`):

```ini
# /etc/systemd/system/hl-zomboid-restart.timer
[Timer]
OnCalendar=*-*-* 05:00:00
OnCalendar=*-*-* 11:00:00
OnCalendar=*-*-* 17:00:00
OnCalendar=*-*-* 23:00:00
Persistent=true
```

> **Timezone (07/08/2026):** the kavure host is on **`America/Sao_Paulo`** — the timer fires on Brasília time. Before that the host was on **UTC** and the restarts ran 3h earlier (04:00/16:00 BRT), which looked like a "missing restart" at 19h. `zomboid-backup` (05:15) also follows the timezone.

**Effects:**
- **Mods updated:** every restart re-executes entry.sh → PZ re-downloads/updates Workshop items on startup.
- **Fresh world + RAM:** resets the heap and clears accumulated state.
- **Player warning:** ~20s beforehand, a `servermsg` (banner) warns `"[SERVER] Reinício em ~20s - servidor fica fora ~1 min para salvar o mundo e atualizar os mods"` (⚠️ always with **quotes** — without quotes PZ only shows the first token; fixed 10/08/2026). Same pattern in `zomboid-stop` (10s) and `zomboid-update`.
- **Respect players (10/08/2026):** `hl-zomboid-restart.service` runs with `Environment=RESPECT_PLAYERS=1` — if a player is online at that time, the restart is **skipped** ("players online - restart ADIADO"). Counted by the `zomboid-playercount` helper (+ NOPASSWD sudoers, reads the panel's `performance_history.playerCount`, ~1 min of lag).
- **Safe:** `PauseEmpty=true` already pauses the world when there are no players; `zomboid-restart` runs an RCON `save` first.
- **Game build does not change** on a normal restart (only with `zomboid-update`/`FORCEUPDATE` **or** when watchtower pulls a new image — see below).

## Image auto-update (watchtower)

> Since **07/08/2026** watchtower (`/srv/data/ops/`) checks images **daily at 03:00 (BRT)** and updates **all** containers — **including `pz-server`** (user's decision: the server is always up to date).

- When the `danixu86/project-zomboid-dedicated-server` image has a new build, the container is recreated **without an RCON save** (stop-timeout 30s) — the world is protected by autosave + panel backup (00:00) + off-box (05:15).
- The `STEAMAPPBRANCH=stable` in `.env` is honored → even with a new image, the installed build is **stable**, not unstable.
- The `.env` **is re-read** on container recreation (unlike `docker compose restart`), and the `pz-dedicated/` volume persists (ZGC flags in `ProjectZomboid64.json` are not wiped by watchtower).

## zram (swap compressed in RAM)

Kavure uses **zram** as its only swap (no slow swapfile):

| Item | Value |
|---|---|
| Device | `/dev/zram0` (zram-tools) |
| Size | 11.5 GB (**100% of physical RAM**) |
| Algorithm | `zstd` |
| Priority | 100 |
| Config | `/etc/default/zramswap` (`ALGO=zstd`, `PERCENT=100`, `PRIORITY=100`) |
| Service | `zramswap.service` (enabled) |

- The `/swap.img` (4 GB on disk) was **removed** (swapoff + fstab + delete) on 06/08/2026 — decided not to use slow disk swap.
- zram is compressed: 11.5 GB of physical swap takes up less real RAM (zstd compression).

## Migration (completed 06/08/2026)

1. ✅ Safety backup on psicopompo at `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/`
2. ✅ Local server stopped (`zomboid.service` inactive — consistent world)
3. ✅ `rsync -aHAX` of `Zomboid/` → `data/` and of `workshop/` → `workshop-mods/`
4. ✅ **Integrity check:** `rsync -n --checksum` → 0 differences
5. ✅ Container `pz-server` up — **`SERVER STARTED`**, world loaded (`isNewGame=false`), ports 16261/16262/27015
6. ✅ RCON enabled + **fixed in the panel** (`rconHost=pz-server`)
7. ✅ **PanelBridge active** (`PanelBridge.lua` installed, `Mod connected`)
8. ✅ Zomboid Control Panel configured (auto-scan) + autobackup enabled
9. ✅ Operation scripts `zomboid-{start,stop,restart,status,update}` + `zomboid-save`
10. ✅ **Post-migration tweaks (06/08):** `STEAMAPPBRANCH=stable` (prevent upgrade to unstable), `MIN_MEMORY=1024m` (dynamic heap), graceful `zomboid-restart` (RCON save), restart timer (since 07/08: **4x/day** 05/11/17/23, `hl-zomboid-restart.timer`) + **off-box backup 01:15** (`zomboid-backup`), **zram 100% RAM** (swapfile removed), **ZGC flags** (`ZUncommit`, `ZUncommitDelay=60`, `SoftMaxHeapSize=4g`), build `42.20.2` at parity with the original

### Players after the migration

- **Nothing is lost:** characters, inventory, base, `players.db` (accounts and **admin permissions**), config — everything migrated with checksum, 0 differences.
- **What players need to do (only):** accept kavure on Tailscale + update the server IP in the game to `100.124.146.77` (or find it in the browser).
- **Admins:** status tied to the account in `players.db` (migrated) — **they remain admins** with no reconfiguration.
- **Cleanup on psicopompo:** you can delete `zomboid.service`/serverfiles **while keeping the backup** `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/` + the `daily/` mirror as a safety net.

## Backup

**Naming convention (AGENTS.md):** `/mnt/BACKUP/{servico}-server-{host}/` → `zomboid-server-kavure/`.

- **Off-box (primary):** **`zomboid-backup`** (timer **05:15** on kavure, `hl-zomboid-backup.timer`) mirrors the panel's zips → **NAS over NFS**: `/srv/data/zomboid/offbox/` = psicopompo `/mnt/BACKUP/zomboid-server-kavure/` (NFSv4 mount via `autofs`/systemd — see [`network/nfs`](../../network/nfs.md)).
  - ⚠️ **NFS mount check:** on kavure the point `/srv/data/zomboid/offbox` uses `autofs`. `findmnt -n -o FSTYPE` returns `autofs` and `nfs4`. Scripts should use `findmnt -n -o FSTYPE "$MNT" | grep -q "nfs"` to avoid a false positive on an unmounted filesystem and a permission error when trying to `mount` manually without root.
  - `rsync -a --delete` (local → NFS) = **real mirror**: new zips arrive, older ones are dropped (inherited retention = 7).
  - **Failsafe (07/08/2026):** reachability check (TCP 2049) → **fail-fast** if the NAS is off; **3 attempts** with 2 min backoff; `timeout` (rsync 15 min / service 30 min) so it never hangs; **ntfy** (`/backup`) on the final failure; errors logged to `/var/log/zomboid-backup.log`.
  - Protects against total loss of the kavure disk.
- **Before updates:** `zomboid-update` takes an automatic compressed backup of the save via `tar` + `zstd -3 -T0` (~15s) → `offbox/archive/pre-update-<data>.tar.zst` (NFS).
- **Panel backup (autobackup):** **daily at midnight** (`backupSchedule: 0 0 * * *`), **retention 7** (`backupMaxCount: 7`), local `/srv/data/zomboid/data/backups/*.zip`.
  - ⚠️ It is **local** (same disk as the server) → it protects against *human error/rollback*, not against *disk failure*. The real disk protection is the off-box.
  - Note: `backups/` also contains `startup/` (full snapshot on every boot, ~921 MB × 5 rotating) and `version/` (configs) — mirrored along with it to the off-box.
- **Pre-migration snapshot:** `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/` (1.2G) — archived, keep.
- Saves live in `/srv/data/zomboid/data/Saves/Multiplayer/pzserver`

## Decisions

### No web panel for container control (07/08/2026)

Considered building a web panel (`zomboid-ctl`) with buttons to start/stop/restart/update the container — in Rust + systemd, Portainer, or a dedicated container. **REJECTED** (a cannon to kill a fly).

- Real control already exists: scripts `zomboid-{start,stop,restart,update,save,status}` (SSH) + scheduled restart (4x/day: 05:00/11:00/17:00/23:00) + **Zomboid Control Panel** (RCON, players, mods, backup, saves/broadcast scheduler).
- The panel's only real gap: **it does not start/stop the container** (false "stopped" — see "Architecture Limitations") — decision: accept it, controlling via scripts/SSH.
- Cost of an extra UI: maintaining code/image/unit + token + security surface — just to repeat what the timer already does.
- If web control is ever needed, evaluate the simple options first (generic Portainer or the panel's scheduler) before building a custom UI.

## Observations

- **`tsarslib` warning (non-blocking):** the log shows `PZXmlParserException: FileNotFoundException` from a missing animation XML in the `tsarslib` mod (`mods/tsarslib/common/media/animsets/...`). It does not prevent the server from coming up (`SERVER STARTED` OK) — it is a mod that references animations that were not downloaded/outdated. Watch it in case it causes problems.

- **Soft-lock on 15/08/2026 (resolved with a restart):** the server froze at 21:35:55 UTC (log stopped; RCON accepted TCP but abandoned the auth handshake → the panel showed "host unreachable"/"connection closed"). Java process alive but not processing (soft-lock), no OOM/hs_err. **Likely cause: a vanilla game bug** — when building/repairing a wall frame (`MOWoodenWallFrame.lua`, base file `media/lua/server/Map/MapObjects/`, not overridden by a mod), the server fires 43× `replacing isoObject` + 206× `ERROR: IsoThumpable not found on square` (known in dedicated MP). It was not caused by the 39 new KI5 mods (which were active). Recovery: `zomboid-restart` (RCON fails by timeout — ok, world saved). Fresh boot with no errors, RCON/panel OK. If it recurs, try booting without the 39 new mods to isolate; mitigation for the bug: avoid rebuilding wall frames in MP.

- **Endless "Joining Game" / Build Mismatch (resolved 18/08/2026):**
  - **Symptom:** the player hangs indefinitely on the *"Joining game"* screen. In the client log (`console.txt`), `java.nio.BufferUnderflowException` appears in `ChunkNotReadyPacket.parse`.
  - **Root cause:** mismatch between the version/build of the Steam client Java binaries (`psicopompo` on 42.20.3) and the server files on the mounted volume (`kavure` on 42.20.2). The `root:root` permissions on the bind mount `/srv/data/zomboid/pz-dedicated/` prevented a direct update, and the empty `ADMINPASSWORD` variable in `.env` caused `NoSuchElementException` in `entry.sh`.
  - **Resolution:**
    1. Make sure `ADMINPASSWORD=adminpz123` and `STEAMAPPBRANCH=public` (or `stable`) are set in `/srv/data/zomboid/.env`.
    2. Run `zomboid-update` or update the binaries (`projectzomboid.jar`) with proper permissions.
    3. Validate the MD5 checksum between client and server (`md5sum projectzomboid.jar`).

## See also
- [[kavure]] — Target server
- [[zomboid-control-panel]] — Web admin panel
- [[kavure-migration-plan]] — Migration plan
