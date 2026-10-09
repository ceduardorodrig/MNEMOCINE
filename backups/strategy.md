---
tags: [homelab, backup, storage]
---

# Backup Strategy

## Current Status (09/08/2026)

| Node | Active Backup | Mechanism | Destination Target |
|---|---|---|---|
| psicopompo | ✅ **Configs + Snapshots + History** | `config-backup` + snapper (nvme/backup/hdd) + restic + etckeeper | `/mnt/BACKUP/` (Local NAS array) |
| ybytu | ✅ Configs (05:00→08:00 UTC) | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/ybytu` |
| ybyra | ✅ Configs | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/ybyra` |
| kuaray | ✅ Configs (reconstructed 08/08) | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/kuaray` |
| kavure | ✅ Game Servers (off-box) + Configs + **Monitoring (13/09)** | NFS off-box (Zomboid/Minecraft/Valheim/Sumænimá Borg) + `config-backup` + etckeeper | `/mnt/BACKUP/*-server-kavure` + `/configs-homelab/kavure` + `/mnt/BACKUP/monitoring-server-kavure` |

> **Canonical Configuration Backup** (established 09/08/2026): All cluster nodes mirror configuration states to the central NAS (`/mnt/BACKUP/configs-homelab/`) via `config-backup` (05:00–06:00 window), versioned via **git → private GitHub `mnemocine` repository**, **restic** (retention: 14d/8w/6m), and **snapper**. See [`config-backup.md`](config-backup.md).  
> The `agentic-ai` workspace is mirrored nightly to `/mnt/BACKUP/agentic-ai-server-psicopompo`.

## Off-Box NFS Standard (NAS on Psicopompo) — Standardized 07/08/2026

**Architecture:** psicopompo operates as the **Tailnet NAS (NFSv4)**. Services hosting critical mutable state **do not backup over SSH** — writing directly to **mounted NFS export shares** (local mirror → NAS). Eliminating SSH eliminates the 12-hour Tailscale SSH re-authentication timeout (the failure mode that previously broke Zomboid backups).

### Standard Components

| Layer | Standard Specification |
|---|---|
| **NAS Target Directory** | `/mnt/BACKUP/{service}-server-{host}/` (e.g. `zomboid-server-kavure/`, `sumaenima-server-kavure/`) |
| **NFSv4 Export** | psicopompo `/etc/exports`: `rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000`, scoped strictly to client Tailscale IP |
| **Client Mount Point** | `/srv/data/{service}/offbox` — fstab: `nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,nofail` |
| **Sync Execution** | `rsync -a --delete <source>/ <offbox>/daily/` (true mirror; `archive/` for pre-update snapshots) |
| **Failsafe Controls** | Probes TCP port 2049 → **fail-fast**; **3× retries** with 2-minute backoff; command timeouts (15m rsync / 30m cron); error logging; **ntfy** `/backup` alert on final failure |
| **Scheduling** | Systemd timer: `timeout 1800 /usr/local/bin/{service}-backup` |

### Implementation References
- **Zomboid:** `/usr/local/bin/zomboid-backup` (canonical failsafe implementation) — see [`services/zomboid/project-zomboid.md`](../services/zomboid/project-zomboid.md).
- **Sumænimá:** Mount `/srv/data/sumaenimahub/backup` → `/mnt/BACKUP/sumaenima-server-kavure`.

### Onboarding a New Service to the Off-Box Standard
1. Create target directory on NAS + add export line to `/etc/exports` (psicopompo) + execute `exportfs -arv` + permit ports `2049/111` in UFW for client Tailscale IP.
2. On client node: Create `offbox` directory + append entry to `/etc/fstab` (standard options) + mount filesystem.
3. Adapt failsafe script template (based on `zomboid-backup`) for the service (source and destination paths).
4. Configure systemd timer with execution timeout + ntfy alert integration.
5. Document additions in `backups/strategy.md`, [`network/nfs.md`](../network/nfs.md), and service documentation.

## Scope of Backups

### Psicopompo
- Docker volumes (Crafty — **pending complete migration** to kavure; StênioBOT/Umami already migrated)
- Docker configurations (compose files, environment templates)
- Obsidian Vault (synchronized via Syncthing + nightly snapshot)
- **Desktop Configurations (21/09/2026):** `~/.config/hypr`, `~/.config/noctalia`, `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia`. Mirrored via `config-backup` → `/mnt/BACKUP/configs-homelab/psicopompo/` (git + restic + snapper).

### Ybytu
- AdGuard Home configuration (`/var/lib/docker/volumes/adguard_conf/_data/AdGuardHome.yaml`) — **mirrored via `config-backup` since 06/10/2026**
- Homepage dashboard configuration (Docker volumes)

### Ybyra
- Edge configurations (Nginx reverse proxy and compose files)

### Kuaray
- Multimedia libraries (Navidrome, Lidarr) — audio media consolidated on psicopompo since 06/08 (`/mnt/BACKUP/media/`)
- Miracena stack database dumps (Directus + n8n + MariaDB)

### Kavure
- **Project Zomboid (Active):** Daily off-box mirror (05:15, `zomboid-backup` via `hl-zomboid-backup.timer`) targeting psicopompo `/mnt/BACKUP/zomboid-server-kavure/daily/`
- **Valheim (Active since 09/09/2026):** Daily off-box mirror (05:30, `valheim-backup` via `hl-valheim-backup.timer`) targeting `/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`
- **Sumænimá (`sae-core`):** Daily automated backup via sentinel daemon (Borg + pg_dump) to NFS `/mnt/BACKUP/sumaenima-server-kavure/`
- **Monitoring (Active since 13/09/2026):** Daily off-box snapshot (05:15, `monitoring-backup`) capturing Prometheus TSDB snapshots + Loki/Grafana to `/mnt/BACKUP/monitoring-server-kavure/daily/`
- **General Coverage:** `config-backup` mirrors **entire `/srv/data` directory** to NAS (git + restic). Excluded items (`zomboid/data`, `minecraft`, `sumaenimahub`) maintain independent off-box backup pipelines.

## Recommendations & Architecture Review

### Completed Milestones (09/08/2026)
1. ✅ **Canonical configuration backups** established across 5 nodes — `config-backup.md`
2. ✅ **Btrfs snapshots** active on all psicopompo drives (snapper) — `snapshots-psicopompo.md`
3. ✅ **restic incremental history** for configurations and vault (14d/8w/6m retention, weekly integrity check)
4. ✅ **etckeeper** tracking `/etc` versioning across all hosts to bare git repositories on NAS
5. ✅ Private GitHub repository `mnemocine` mirroring configurations
6. ✅ Centralized secrets store via SOPS/age; plaintext credentials purged from documentation

### Pending Action Items
1. **Off-site backup (3-2-1 Rule):** Google Drive 5TB synchronization via rclone (configurations + vault + repositories)
2. **Monthly recovery drills** and quarterly `restic check --read-data` executions — see `backup-rituals.md`
3. **Off-host cold backup of age encryption keys** (`age-keys-backup.txt`) stored in KeePassXC / offline USB
4. **Push telemetry monitoring in Uptime Kuma** tracking backup health stamps
5. **End-to-end recovery playbooks** testing full restorations for Zomboid, Minecraft, sae-core, and host configurations

## Utility Commands

```bash
# Docker volume backup
docker run --rm -v steniobot_valkey:/volume -v /backup:/backup alpine \
  tar czf /backup/valkey-$(date +%F).tar.gz -C /volume .

# Docker volume restore
docker run --rm -v steniobot_valkey:/volume -v /backup:/backup alpine \
  tar xzf /backup/valkey-2026-06-01.tar.gz -C /volume
```
