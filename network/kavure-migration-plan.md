---
tags: [homelab, network, storage, gaming, todo]
---

# kavure — Migration Plan

Complete plan for **kavure** (Dell OptiPlex 3060 SFF) to take over as the homelab services server, taking load off **psicopompo** (which becomes a dev environment + GPU workers).

## Goal

- **kavure** becomes the dedicated server: Sumænimá (sae-core), Minecraft, Project Zomboid, monitoring.
- **psicopompo** stops being a server → becomes a **development environment + GPU workers** (vision/audio/ollama).
- **Migration with total data integrity** (Minecraft + Zomboid) — no data may be lost.
- Both game servers **start down** and come up on demand.

## Approved Decisions

| Decision | Value |
|---|---|
| Hostname | kavure |
| **Distro** | **Ubuntu Server 24.04 LTS** |
| **Filesystem** | **LVM + ext4** (subiquity installer default, no hacks) |
| **OS Snapshots** | None (non-standard; real protection via off-box backup) |
| RAM | Squeeze by with 12 GB — Zomboid `-Xmx6g` + ZGC; games never simultaneous; 32 GB upgrade as a future step |
| Orchestration | Docker Swarm — kavure = manager (role=core), psicopompo = worker (role=gpu) |
| Zomboid | **Docker** (`danixu86/project-zomboid-dedicated-server`) + Zomboid Control Panel (RCON enabled); ✅ **DONE 06/08/2026** |
| Minecraft | Crafty (identical bind mounts) |
| Storage until new HDD | kavure local SSD (~80 GB) + off-box backup on psicopompo `/mnt/BACKUP` |
| **Future storage** | **M.2 SATA 2280 1 TB** (OS/Docker) + **HDD 3.5" 4–8 TB** (`/mnt/storage`) — to buy |
| **GPU** | **Quadro P1000 OUT OF PLAN** — capacitor came loose during the repaste, awaiting repair |
| psicopompo | Remove **only mapped containers**; portainer/dockerproxy/the rest untouched |

## ✅ Phase A0 — DONE (05/08/2026)

> **Status:** Ubuntu 24.04.4 installed, Tailscale + SSH working, real specs recorded in `kavure.md`.

1. ✅ **Windows 11 booted** and specs validated.
2. ⏳ **CPU repaste (i3-8100)** — pending (do it the first time the machine is opened).
3. ✅ **Ubuntu Server 24.04.4 LTS** installed with LVM + ext4 layout (100 GB on `/`, 120 GB free in the VG).
4. ✅ **SSH** enabled.
5. ✅ **`tailscale up`** → hostname `kavure`, IP `100.124.146.77`.
6. ✅ **Access:** `tailscale ssh kavure@kavure` (user `kavure`, sudo).
7. ✅ **Real specs recorded** in `kavure.md`.

### GPU P1000 — ❌ OUT OF PLAN

- During the repaste, **a capacitor came loose from the P1000**. Card **awaiting repair** (microsoldering/reflow technician) — no ETA.
- **Impact on the plan: NONE** — kavure runs everything (Sumænimá, Minecraft, Zomboid) without a GPU; the Intel UHD 630 iGPU is enough for headless. The GPU was for future offload.
- When/IF the card is repaired, resume: install in the PCIe x16 slot + `gpu-burn` to check temperature.

### Storage — Purchase Plan (validated)

| Item | Specification | Status |
|---|---|---|
| **M.2 SATA 2280 1 TB** | free slot (accepts SATA); OS + Docker + games | Buy |
| **HDD 3.5" 4–8 TB** | SATA port (only power connector); no size limit (UEFI+GPT) | Buy |
| Kingston SA400 223 GB | current 2.5" SATA | Spare |

## Phase A — Provisioning

- Install: `docker.io`, `docker-compose-v2`, `tailscale` (✅ already), `openssh-server` (✅ already), `rsync`.
- **NVIDIA driver + container-toolkit:** ⏸️ deferred — P1000 out of plan (awaiting repair).

## ✅ Phase B — Sumænimá Migration (sae-core) — DONE (07/08/2026)

1. ✅ `pg_dump` of the main DB + Umami; volumes, `.env`, migrations copied (rsync over Tailscale + tar via docker).
2. ✅ `SUMAENIMA-HUB` on kavure (`/srv/data/sumaenimahub/`); `core.yml` bind mounts adjusted for kavure paths + port 9090 published.
3. ✅ Swarm: `docker swarm init` on kavure → join of psicopompo (role=gpu), ybyra (primary), kuaray (standby); labels applied; `docker stack deploy -c core.yml sae-core`.
4. ✅ GPU workers (vision/audio/ollama) stay on psicopompo via `gpu.yml` (overlay `sumaenima_sumaenima-net` → api/valkey/ollama on kavure).
5. ✅ Nginx on ybyra (and the kuaray standby) → proxy `api:9090` (kavure); `hosts.ini`/`deploy.yml` updated.
6. ✅ `sumaenima-ctl` manages the Swarm via SSH to kavure (local GPU on psicopompo).
7. ✅ Validated: health `kavure:9090/api/health` 200, ybyra `/api/health` 200, public Funnel 200, NFS backup active.

## Phase C — Games (migration with integrity)

### C1 — Minecraft Dominium (38 GB) — ✅ DONE (08/08/2026)

> **Actual execution (08/08/2026):** Crafty + server migrated with rsync `--checksum` (0 differences). **Backup (AdvancedBackups) redirected to the NAS via NFS** (user's decision — off-box standard): `/srv/data/minecraft/offbox` → `/mnt/BACKUP/minecraft-server-kavure/` (25GB history from the HDD copied to the NAS; the plugin purge cleans up the old one). **JVM G1 flags** applied in Crafty (`execution_command`): floor 2G / ceiling 8G / soft 5G + Aikar + `G1PeriodicGCInterval` (coexistence with Zomboid). Necessary fix: `chown -R 1000:1000` on the server folder (crafty runs java as uid 1000; the root-owned `latest.log` blocked logging).

1. ✅ Verify the AdvancedBackups (25 GB on the HDD) is intact → **copied to the NAS** `/mnt/BACKUP/minecraft-server-kavure/`.
2. ✅ Stop `crafty-controller` on psicopompo (consistent world) — the server was already stopped since 22/07.
3. ✅ `rsync -aHAX --checksum --info=progress2` of `/mnt/NVME_PCI/minecraftserver [dominium]` → `/srv/data/minecraft/minecraftserver [dominium]`.
4. ✅ **Verification:** `rsync -n --checksum` (0 differences) + `du` 38G=38G.
5. ✅ Container recreated with the same binds (compose), backup mount → `offbox` NFS; server starts down (turned on in Crafty's web UI `kavure:8443`).
6. ✅ Validated: boot `Done (~15s)`, RCON, Voice Chat, **player joined** (08/08/2026). RAM coexisting with Zomboid (6.8G used / 4.7G free; swap ~1-3G to monitor).

### C2 — Project Zomboid (27 GB) — ✅ DONE (06/08/2026)

> **Note:** the original plan called for LinuxGSM, but the execution used **Docker** (`danixu86/project-zomboid-dedicated-server`) with Compose in `/srv/data/zomboid/` — see [`services/zomboid/project-zomboid.md`](../services/zomboid/project-zomboid.md). Actual steps:

1. ✅ Stop `zomboid.service` + backup of the save (`/home/pzserver/Zomboid`) → `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/`.
2. ✅ `rsync -aHAX` of `Zomboid/` → `data/` and of `workshop/` → `workshop-mods/` + verification `rsync -n --checksum` (0 differences).
3. ✅ Deploy via **Docker Compose** (`/srv/data/zomboid/docker-compose.yml` + `.env`), volumes: `data/` → `/home/steam/Zomboid`, `pz-dedicated/` → `/home/steam/pz-dedicated`, `workshop-mods/` → `.../steamapps/workshop`.
4. ✅ **Enable RCON** in `pzserver.ini` (`RCONPort=27015` + password) — fixed in the panel (`rconHost=pz-server`).
5. ✅ **Zomboid Control Panel** installed (Docker, `fpsacha/zomboid-panel`) + auto-scan + autobackup; access via Tailscale `:3001`.
6. ✅ Service **starts down** and comes up on demand via `zomboid-*` scripts (cron restart 4x/day: 05/11/17/23).
7. ✅ Tested world boot (`SERVER STARTED`, `isNewGame=false`) + validation of the ~65 mods.
8. ✅ **JVM B42:** `-Xms1024m -Xmx6144m` + ZGC flags (`ZUncommit`, `ZUncommitDelay=60`, `SoftMaxHeapSize=4g`) in `ProjectZomboid64.json`.
9. ✅ Mandatory **pre-update backup** (`zomboid-update` → `archive/pre-update-<data>/`) + daily off-box backup at 01:15 (`zomboid-backup` → `daily/`).

## Phase D — Off-box Backup

- **Incremental rsync** (via Tailscale) → **psicopompo `/mnt/BACKUP`** (930 GB free), with retention of multiple points in time via `--link-dest`.
- Covers: game worlds (7+ day retention), code, configs.
- psicopompo = redundancy, **not a dependency**.

## Phase E — Infra Repo Docs

- **Create:** `servers/kavure.md` ✅, `recovery/disaster-recovery.md` ✅ (merged 09/08), `services/zomboid/project-zomboid.md` ✅, `services/zomboid/zomboid-control-panel.md` ✅.
- **`ops` infra (07/08):** **autoheal**, **watchtower** (schedule 03:00 BRT, cleanup, updates everything including `pz-server`) and **glances** (`:61208`) installed in `/srv/data/ops/`. **Host on `America/Sao_Paulo`** — Zomboid scheduling via systemd timers (restart 4x/day 05/11/17/23 with `RESPECT_PLAYERS=1` + backup 05:15) on Brasília time.
- **Update:** `README.md` ✅, `_tags.md` (+`#kavure`, `#zomboid`, `#zomboid-panel`), `network/topology.md`, `network/service-topology.md`, `network/tailscale.md` (fix the nonexistent funnel/exit node), `network/dns.md`, `services/steniobot.md`, `services/crafty.md`, `servers/psicopompo.md` (dev+GPU role), `recovery/disaster-recovery.md` (merged), `backups/strategy.md`.

## Phase F — Finalize psicopompo — ✅ DONE (08/08/2026)

- ✅ Remove **only mapped containers** (sae-core stack, crafty). **Portainer, dockerproxy and the rest stay untouched** until a new inventory.
- ✅ Removed from psicopompo (after validating the migration on kavure): `crafty-controller` (container), network `minecraftserver_default`, `/mnt/HDD_SATA/minecraftserver [dominium-backup]` (25 GB — history on the NAS) and `/mnt/NVME_PCI/minecraftserver [dominium]` (38 GB — migrated source). Backup intact at `/mnt/BACKUP/minecraft-server-kavure/`.
- Keep: GPU workers (vision/audio/ollama) + Steam + dev environment.

## Risks / Bottlenecks

- **RAM 12 GB:** sae-core (~4.5 GB) + Minecraft (4–6 GB) + Zomboid B42 (`-Xmx6g`) **do not run together** → on-demand games + memory limits + 32 GB upgrade as a future step.
- **Zomboid B42 asks for `-Xmx12g` in the docs** — with 12 GB of RAM we have to squeeze to `-Xmx6g` + ZGC (fewer players / possible stutter).
- **B42 patches can break saves** → mandatory pre-update backup (rsync, 7+ day retention).
- **SSD 223 GB:** ~80 GB used; **M.2 SATA 1 TB + HDD 4–8 TB** solves it (to buy).
- **M.2 PCIe 2.0 x4** (~1.5 GB/s) — half the NVMe speed, irrelevant (chosen option: M.2 SATA).
- **PSU 200 W:** no GPU → M.2 (no cable) + HDD 3.5" 4-8 TB (~25 W peak) + i3-8100 → **~120 W peak, plenty of headroom** ✅. If the P1000 is repaired in the future: +47 W → ~170 W, still ok with 1 HDD.
- **P1000 (awaiting repair):** loose capacitor — off the active path; zero impact on Phases B–D.
- **Swarm node labels** not configured today → apply before the deploy.
- **Docs diverge from reality** (funnel, roles, Down nodes) → fixed in Phase E.
- Zomboid **RCON** must be enabled (panel requirement).
- **Crafty** runs non-root in the container — ok on Ubuntu (AppArmor default, no friction).

## References

- `servers/kavure.md` — server documentation
- `network/topology.md` — IPs and network
- `network/tailscale.md` — tailnet
- `backups/strategy.md` — backup strategy
