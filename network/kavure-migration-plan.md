---
tags: [homelab, network, storage, gaming, todo]
---

# Kavure — Server Migration Runbook & Execution Record

Comprehensive plan executed for **kavure** (Dell OptiPlex 3060 SFF) to assume the role of dedicated 24/7 homelab services server, offloading workloads from **psicopompo** (which transitioned into a dedicated dev workstation and GPU inference worker node).

## Objectives

- **kavure** operates as the primary dedicated server: Sumænimá (`sae-core`), Minecraft, Project Zomboid, observability stack.
- **psicopompo** decommissioned as general service host → converted to **development environment + GPU inference workers** (vision/audio/ollama).
- **Migration with absolute data integrity** across persistent game states (Minecraft + Project Zomboid).
- Game servers initialized in **standby/stopped state**, launching on-demand to respect host memory ceilings.

## Approved Architectural Decisions

| Decision Area | Selected Value |
|---|---|
| Node Hostname | `kavure` |
| **Operating System** | **Ubuntu Server 24.04 LTS** |
| **Filesystem Layout** | **LVM + ext4** (Subiquity default installer profile) |
| **OS Snapshots** | None (OS is disposable; state is safeguarded via off-box backups to NAS) |
| RAM Constraints | Managed tightly with 12 GB RAM — Zomboid `-Xmx6g` + ZGC; game servers never run simultaneously |
| Orchestration | Docker Swarm — kavure = manager (`role=core`), psicopompo = worker (`role=gpu`) |
| Zomboid Server | Containerized (`danixu86/project-zomboid-dedicated-server`) + Zomboid Control Panel (RCON enabled); ✅ **COMPLETED 2026-08-06** |
| Minecraft Server | Crafty Controller 4 with identical bind mounts |
| Immediate Storage | Internal 2.5" SATA SSD (~223 GB) + off-box NFS backups to psicopompo `/mnt/BACKUP` |
| **Future Storage Expansion** | **M.2 SATA 2280 1 TB** (OS/Containers) + **3.5" HDD 4–8 TB** (`/mnt/storage`) |
| **Discrete GPU** | **Quadro P1000 DEFERRED** — damaged capacitor during repasting; awaiting component micro-soldering |
| psicopompo Decommissioning | Removed mapped containers cleanly; developer utilities preserved |

## Phase Execution History

### ✅ Phase A0 — Hardware Provisioning & OS Setup (Completed 2026-08-05)

1. ✅ Validated hardware specifications and thermal parameters under initial environment.
2. ✅ Installed **Ubuntu Server 24.04.4 LTS** with LVM volume group configuration.
3. ✅ Configured OpenSSH server and enrolled Tailscale node.
4. ✅ Established Tailscale IP `100.124.146.77` with Tailscale SSH integration.

### Discrete GPU Status — Quadro P1000
- During hardware repasting, a surface-mount capacitor detached from the Quadro P1000 PCB. Card is awaiting precision micro-soldering.
- Zero impact on core services: Core i3-8100 Intel UHD Graphics 630 handles headless server requirements.

### ✅ Phase B — Sumænimá Core Migration (Completed 2026-08-07)

1. ✅ Executed `pg_dump` of primary databases and Umami metrics; synced volumes, configurations, and migration history.
2. ✅ Deployed `SUMAENIMA-HUB` on kavure (`/srv/data/sumaenimahub/`); mapped container paths and published overlay network bindings.
3. ✅ Initialized Swarm cluster with kavure as manager; enrolled psicopompo (`role=gpu`), ybyra, and kuaray.
4. ✅ Kept GPU inference workers (vision/audio/ollama) on psicopompo via `gpu.yml`, communicating across `sae-net` overlay.
5. ✅ Reconfigured edge proxy on ybyra to route `/api` requests to kavure port 9090.
6. ✅ Verified end-to-end operational health: `/api/health` returning HTTP 200 across edge ingress and internal endpoints.

### Phase C — Game World Migration (Integrity-Preserving)

#### C1 — Minecraft Dominium (38 GB) — ✅ Completed 2026-08-08
1. ✅ Verified AdvancedBackups archive on storage and transferred dataset to NAS target `/mnt/BACKUP/minecraft-server-kavure/`.
2. ✅ Suspended source `crafty-controller` on psicopompo to ensure state consistency.
3. ✅ Synced world files via `rsync -aHAX --checksum` with zero discrepancies.
4. ✅ Bound backup directories to off-box NFS storage.
5. ✅ Verified player connection, voice chat latency, and JVM memory footprint (G1GC garbage collector flags applied).

#### C2 — Project Zomboid (27 GB) — ✅ Completed 2026-08-06
1. ✅ Created pre-migration archive of `/home/pzserver/Zomboid/` to NAS off-box storage.
2. ✅ Migrated world save files and Steam Workshop mod cache via checksum-verified rsync.
3. ✅ Deployed containerized server stack via Docker Compose (`/srv/data/zomboid/docker-compose.yml`).
4. ✅ Configured RCON parameters (`RCONPort=27015`) and linked Zomboid Control Panel (`:3001`).
5. ✅ Optimized Build 42 JVM parameters: `-Xms1024m -Xmx6144m` paired with ZGC (`ZUncommit`, `ZUncommitDelay=60`).
6. ✅ Established daily off-box backup rotation scripts (`zomboid-backup` to NFS).

### ✅ Phase D — Off-Box Backup Strategy
- Deployed automated incremental rsync pipelines pushing container state snapshots over encrypted Tailnet to psicopompo `/mnt/BACKUP`.
- Retention schedules configured for game worlds and database dumps.

### ✅ Phase E — Infrastructure Documentation & Ops Automation
- Provisioned `/srv/data/ops/` hosting autoheal, watchtower (03:00 BRT update cycle), and glances telemetry (`:61208`).
- Set system timezone to `America/Sao_Paulo`.
- Aligned documentation across node profiles and network architecture catalogs.

### ✅ Phase F — Psicopompo Workstation Normalization (Completed 2026-08-08)
- Removed migrated container stacks from psicopompo, freeing local NVMe and SATA storage.
- Preserved developer tools, local Docker image registry, and GPU transcription microservices.
