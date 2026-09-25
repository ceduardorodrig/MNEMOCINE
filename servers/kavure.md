---
tags: [homelab, server, kavure, docker, storage, gaming, todo, miracena]
---

# kavure

**Role:** Dedicated services server — Sumænimá (sae-core), Minecraft, Project Zomboid, Valheim, monitoring.
**Default shell:** bash (`/bin/bash`)

> **Status:** ✅ **Up and running** — Ubuntu installed, Tailscale + SSH working. **Project Zomboid migrated and active (Docker, 06/08/2026)**; **`ops` infra stack active** (autoheal, watchtower, glances) and **host on `America/Sao_Paulo`** (07/08/2026); **Sumænimá sae-core MIGRATED AND ACTIVE (07/08/2026)** — kavure is the Swarm manager (role=core) with db, valkey, api (9090), umami-db, backup (NFS → psicopompo) and asciline.
> **Updated 28/08/2026:** full `apt dist-upgrade` (51 packages) + reboot. Kernel **6.8.0-137 → 6.8.0-138**. Swarm (3 nodes), games and services OK after reboot.
> **Home Assistant reconfigured on kavure (16/08):** container with `cap_add: [NET_ADMIN, NET_RAW]`; **HACS 2.0.5 installed and configured** (GitHub OAuth OK); Tuya (cloud) and automatic backup pending configuration. **Kavure does NOT have Bluetooth hardware** (integration removed). See [`services/home-assistant.md`](../services/home-assistant.md).
> **Fix NFS shutdown race (10/09/2026):** 4 `hard` entries → `soft` in fstab (configs, repos, music, books). All mounts now use `soft,nofail,mount-timeout=10s`. Removed `idle-timeout` from the Docker mounts (avoids "device is busy" on shutdown). Created drop-in `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). fstab backup: `/etc/fstab.bak.20260910`. Kernel **6.8.0-138 → 6.8.0-139**. See [`network/nfs.md`](../network/nfs.md).
> **Fix Boot-Race Tailscale + NFS (25/09/2026):** (1) Updated `/etc/systemd/system/docker.service.d/nfs-ordering.conf` with `After=tailscaled.service remote-fs.target` and `Wants=tailscaled.service remote-fs.target`. Prevents Docker from starting before the NFS mounts are ready (which caused `ExitCode=128` in `calibre` and `navidrome`). (2) Enabled `net.ipv4.ip_nonlocal_bind = 1` via `/etc/sysctl.d/99-tailscale-bind.conf` (kavure and psicopompo), allowing processes such as HAProxy and the Docker daemon to bind on the ports with the specific Tailnet IP before the IP assignment finishes on the interface.
> See [`kavure-migration-plan`](../network/kavure-migration-plan.md) for the full plan.

## Hardware (confirmed on 05/08/2026)

| Item | Actual Specification |
|---|---|
| **Machine** | Dell OptiPlex 3060 SFF |
| **CPU** | Intel Core i3-8100 4C/4T @ 3.6 GHz |
| **RAM** | 12 GB (11 GiB) — 2 DDR4 DIMM slots, upgrade to 32 GB possible |
| **System Disk** | **Kingston SA400S3 223 GB SATA 2.5"** (LVM: 100 GB on `/`, 120 GB free in the VG) |
| **Future Disk (to buy)** | **M.2 SATA 2280 1 TB** (OS/Docker) + **HDD 3.5" 4–8 TB** (storage) |
| **GPU** | Quadro P1000 — **OUT OF PLAN: capacitor came loose during the repaste**, awaiting repair |
| **Network** | Gigabit Ethernet + Wi-Fi |
| **OS** | **Ubuntu 24.04.4 LTS** (kernel 6.8.0-139) |
| **Filesystem** | **LVM + ext4** (subiquity) |
| **Tailscale** | `100.124.146.77` — `kavure` |
| **Access** | `tailscale ssh kavure@kavure` (user `kavure`, sudo NOPASSWD — `/etc/sudoers.d/kavure-nopasswd`, 10/09/2026) |
| **LAN** | `192.168.3.41/24` via **Wi-Fi extender** (a fixed LAN IP is **unnecessary** — access is via the tailnet) |

> **The SSD is SATA 2.5"** — the **M.2 2280 slot is free** (accepts SATA M.2 or NVMe). The Kingston 2.5" becomes the **spare** when the 1 TB M.2 arrives.

## Hardware Limitations

- **RAM 12 GB:** sae-core (~1.5 GB) + Minecraft (G1, `Xmx8G`/soft `5G`) + Zomboid B42 (ZGC, `-Xmx8g`/soft `4g`) **coexist via soft-max heap** (each JVM only grows to the soft limit when it needs to; G1/ZGC return idle memory). Validated on 08/08/2026 (6.8G used / 4.7G free; swap ~1-3G to monitor). Two games at 100% at the same time is still tight — a 32 GB upgrade is the future step.
- **SSD 223 GB:** ~80 GB used in the migration; the 1 TB M.2 will solve it.
- **M.2 slot:** accepts **SATA M.2** (550 MB/s) or NVMe (PCIe 2.0 x4 limit ~1.5 GB/s) — decision: **1 TB SATA M.2**.
- **HDD >4 TB:** validated with no size limit (UEFI + GPT) — Dell community expert.
- **PSU 200 W:** M.2 (no cable) + HDD 3.5" (~25 W peak) + i3-8100 → **~120 W peak, plenty of headroom** ✅ (no GPU for now).

## Health Diagnostics (06/08/2026)

| Item | Result | Status |
|---|---|---|
| **CPU (Kryonaut repaste)** | idle **34°C** → full load **46°C** (limit 80°C) | ✅ Excellent |
| **RAM** | 4 GB + 8 GB @ 2400 MT/s; 4G stress without errors; 10 GiB free | ✅ Healthy |
| **Kingston SA400 SSD** | SMART **PASSED**; 11.125 h powered on; 0 reallocated; 0 uncorrect; 30°C | ✅ Healthy |
| **SSD speed** | 350 MB/s read (normal SATA for this model) | ✅ Normal |
| **dmesg** | ACPI `AE_NOT_FOUND` in `\_SB.PCI0.GLAN.GPEH` — Dell bug, harmless (shows on every boot) | ✅ Clean |

## Roles (planned)

- **Docker Swarm manager** (role=core) — sae-core (db, valkey, api, umami-db, backup, asciline)
- **Sumænimá standby edge (29/08/2026)** — took over the role that was kuaray's: `sae-edge_{proxy,tunnel,umami}-standby` (replicas=0, manual scale on failover) with constraint **`node.labels.edge_backup == true`** (kavure **keeps** `role=core`). Static frontend in `/var/www/sumaenima` (synced via `deploy-swarm.sh`). The standby Nginx uses **docker config** (`sae-edge_nginx-conf-standby`, generated from `templates/nginx.conf.edge.j2`) — the `/srv/data/sumaenimahub/nginx-backup/nginx.conf` bind (which was corrupted, 63 B, root-owned dir) was **removed on 29/08**; validated with a `proxy-standby=1` scale test (`nginx -t` OK) and reverted to 0/0.
- **backup-sentinel health `:9092`** — responds to **GET and HEAD with 200** since **29/08/2026** (`do_HEAD` added; previously HEAD → 501 and the Homepage/Uptime Kuma widget showed an error). Code in `/srv/data/sumaenimahub/SUMAENIMA-HUB/scripts/backup/backup_health_server.py` (`ro` mount in the container).
- **Sumænimá backup scheduling (29/08/2026)** — homelab standard: **systemd timer `hl-sumaenima-backup.timer` (03:00, `Persistent=true`)** → `/usr/local/bin/sumaenima-backup` (failsafe + ntfy `/backup`) → `docker exec sae-core_backup python3 /app/scripts/backup/sentinel.py` (Borg + pg_dump → psicopompo NFS). The crond inside the container **was removed** (29/08): the image started running as `appuser` and the crond could not read `/etc/crontabs/root` (Permission denied) — the daily run would have stopped silently. The `.backup_last_run` marker is touched by the host (root); health file `/srv/health/sumaenima-backup-last-ok`. The repo `.env` is read by the sentinel as group `appuser` (640, gid 1001).
- Game server — **Project Zomboid** (Docker — `danixu86/project-zomboid-dedicated-server`, **active** since 06/08/2026) + **Minecraft Dominium** (Crafty, **active** since 08/08/2026 — see [`crafty`](../services/crafty.md)) + **Valheim** (Docker — `mbround18/valheim:3`, **active** since 09/09/2026 — see [`valheim-server`](../services/valheim/valheim-server.md))
- Zomboid management panel (Zomboid Control Panel)
- Monitoring — **Glances active** (`:61208`, 07/08/2026); **watchtower** (auto-update, schedule 03:00 BRT) and **autoheal** active; portainer planned
- Streaming — **aiostreams** (`:3000`, funnel `kavure.chimaera-heptatonic.ts.net:8443`) and **comet** (`:8000`), migrated from kuaray on **09/08/2026** (see [`aiostreams`](../services/aiostreams.md) and [`comet`](../services/comet.md))
- **Miracena Stack** (10/09/2026) — CMS + Automation + Sites: Directus (`:8055`), WordPress (`:8085`), n8n (`:5678`), Nginx Proxy Manager (`:81` admin, `:8180` HTTP, `:8445` HTTPS), PostgreSQL (shared: Directus + n8n), Redis, MariaDB. Deployed in `/srv/data/miracena/` with resource limits (~5.6 GB RAM total). **Tailscale Funnel** active at `miracena.chimaera-heptatonic.ts.net` (public HTTPS → NPM → WordPress). See [`miracena-stack`](../services/miracena-stack.md)

## Storage Layout

```
Atual (após merge LVM em 06/08/2026):
  sda  Kingston SA400S3 223 GB SATA 2.5"  → LVM ubuntu-vg (LV único expandido)
  sda1 1GB vfat  /boot/efi
  sda2 2GB ext4  /boot
  sda3 ~220 GB   LVM  → ubuntu-lv (217 GB) → /   ← LV único, todo o espaço
```

**Folder structure (FHS):**

```
/srv/data/zomboid/    ← Docker Zomboid (danixu86/project-zomboid-dedicated-server)
/srv/data/ops/        ← stack de infra (autoheal, watchtower, glances)
/srv/data/sumaenimahub/ ← código + volumes + backup do Sumænimá sae-core (07/08/2026)
/srv/data/sumaenimahub/SUMAENIMA-HUB  ← repo de deploy
/srv/data/sumaenimahub/volumes/       ← dados PostgreSQL/Valkey/Umami
/srv/data/sumaenimahub/backup         ← mount NFS → psicopompo /mnt/BACKUP/sumaenima-server-kavure
/srv/data/minecraft/   ← Crafty/Minecraft Dominium (08/08/2026 — migrado do psicopompo)
/srv/data/minecraft/minecraftserver [dominium]  ← servidor 1.21.1/Fabric (38 GB)
/srv/data/minecraft/offbox  ← mount NFS → psicopompo /mnt/BACKUP/minecraft-server-kavure (backup AdvancedBackups)
/srv/data/valheim/     ← Valheim Dedicated Server (09/09/2026 — mbround18/valheim:3)
/srv/data/valheim/offbox  ← mount NFS → psicopompo /mnt/BACKUP/valheim-server-kavure (backup)
/srv/data/miracena/    ← Miracena Stack (10/09/2026 — Directus, WordPress, NPM, PostgreSQL, Redis, MariaDB)
/srv/data/           ← dados de jogo (mundos, saves)
/var/lib/docker/     ← volumes Docker
```

> **Decision:** single 217 GB LV (merged with `lvextend -r -l +100%FREE`), organized by FHS folders. Simpler and all the space usable; the risk of a full `/` is mitigated with monitoring.

Plan (purchases):
  M.2 2280 slot  → M.2 SATA 1 TB  (OS + Docker + games)
  SATA port     → HDD 3.5" 4-8 TB (/srv/data, mass storage)
  Kingston 2.5"  → spare

- **No OS snapshots** — non-standard on Ubuntu; real protection comes from the off-box backup.

## Backup

### Automatic Backups (systemd timers)

| Timer | Time | Service | Method |
|-------|---------|---------|--------|
| `hl-config-backup.timer` | 05:00 | Host configs | rsync → NAS |
| `hl-zomboid-backup.timer` | 05:15 | Project Zomboid | rsync → NAS |
| `hl-n8n-backup.timer` | 05:25 | n8n (PostgreSQL) | pg_dump → NAS |
| `hl-miracena-backup.timer` | 05:35 | Miracena Stack | pg_dump + mysqldump + rsync → NAS |
| `hl-sumaenima-backup.timer` | 03:00 | Sumænimá | Borg + pg_dump → NAS |
| `hl-valheim-backup.timer` | 05:30 | Valheim | rsync → NAS |

### NFS Mount for Backups

```bash
# Todos os mounts usam soft (nunca hard) para evitar deadlock no shutdown
# Padrão: /etc/fstab com x-systemd.automount,x-systemd.mount-timeout=10s,nofail
```

- **psicopompo** = tailnet NAS (NFSv4, 930 GB free)
- **Incremental rsync** → `--link-dest` for retention of multiple points in time

## Docker (Ubuntu 24.04)

- Install: `docker.io` + `docker-compose-v2` (Ubuntu repo) — trivial.
- Storage driver: **overlay2** (default).
- Default AppArmor (no friction with containers, unlike openSUSE's SELinux).

### Auto-start on Boot (07/08/2026)

- **`sumaenima-swarm.service`** (systemd, enabled) → `/usr/local/bin/sumaenima-boot.sh`: deploys the `sae-core` + `sae-edge` Swarm on boot (exports `.env`, waits for docker).
- **GPU workers** (on psicopompo): `sumaenima-gpu.service` (systemd user, linger enabled) comes up via `sumaenima-ctl start`.
- The other kavure services (pz-server, ops, dockerproxy, zomboid-panel) use `restart: unless-stopped` — they come up with Docker.

## See also
- [[kavure-migration-plan]] — Full migration plan
- [[project-zomboid]] — Project Zomboid server
- [[zomboid-control-panel]] — Zomboid web panel
- [[crafty]] — Minecraft server (Crafty)
- [[steniobot]] — Sumænimá (sae-core)
