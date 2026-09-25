---
tags: [homelab, backup, storage]
---

# Backup Strategy

## Current State (09/08/2026)

| Server | Active backup | Tool | Destination |
|---|---|---|---|
| psicopompo | ✅ **configs + snapshots + history** | `config-backup` + snapper (nvme/backup/hdd) + restic + etckeeper | `/mnt/BACKUP/` (own NAS) |
| ybytu | ✅ configs (05:00→08:00 UTC) | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/ybytu` |
| ybyra | ✅ configs | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/ybyra` |
| kuaray | ✅ configs (rebuilt 08/08) | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/kuaray` |
| kavure | ✅ games (off-box) + configs + **n8n (28/08)** + **monitoring (13/09)** | NFS off-box (zomboid/minecraft/valheim/sumaenima borg) + `config-backup` + etckeeper | `/mnt/BACKUP/*-server-kavure` + `/configs-homelab/kavure` + `/mnt/BACKUP/n8n-server-kavure` + `/mnt/BACKUP/monitoring-server-kavure` |

> **Canonical backup of configs** (created 09/08/2026): all hosts mirror their configs to the NAS
> (`/mnt/BACKUP/configs-homelab/`) via `config-backup` (05:00–06:00 window), versioned with
> **git → private GitHub `mnemocine`**, **restic** (14d/8s/6m) and **snapper**. See [`config-backup.md`](config-backup.md).
> The `agentic-ai` vault has a nightly copy in `/mnt/BACKUP/agentic-ai-server-psicopompo`.

## Off-box standard via NFS (psicopompo NAS) — standardized 07/08/2026

**Architecture:** psicopompo is the **tailnet NAS (NFSv4)**. Services with critical data **do not back up via SSH** — they write **directly to an NFS mount** (local mirror → NAS). No SSH → no Tailscale SSH 12h `check` (the footgun that took down the Zomboid backup on 07/08).

### Components of the standard

| Layer | Standard |
|---|---|
| **Folder on the NAS** | `/mnt/BACKUP/{servico}-server-{host}/` (e.g.: `zomboid-server-kavure/`, `sumaenima-server-kavure/`) |
| **Export (NFSv4)** | psicopompo's `/etc/exports`: `rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000`, restricted to the client's tailnet IP |
| **Mount on the client** | `/srv/data/{servico}/offbox` — fstab `nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,nofail` |
| **Copy** | `rsync -a --delete <fonte>/ <offbox>/daily/` (true mirror; `archive/` for pre-update snapshots) |
| **Failsafe** | TCP 2049 reachability → **fail-fast**; **retry 3×**/backoff 2min; `timeout` (rsync 15min / cron 30min); **error log**; **ntfy** (`/backup`) on final failure |
| **Scheduling** | cron `15 1 * * * timeout 1800 /usr/local/bin/zomboid-backup` |

### Implementation references
- **Zomboid:** `/usr/local/bin/zomboid-backup` (reference failsafe script) — see [`services/zomboid/project-zomboid.md`](../services/zomboid/project-zomboid.md).
- **Sumænimá:** mount `/srv/data/sumaenimahub/backup` → `/mnt/BACKUP/sumaenima-server-kavure`.

### How to add a new service to the standard
1. Create the folder on the NAS + a line in `/etc/exports` (psicopompo) + `exportfs -arv` + open `2049/111` (ufw) for the client IP.
2. On the client: `offbox` folder + an entry in `/etc/fstab` (same options) + `mount`.
3. Adapt the failsafe script (base: `zomboid-backup`) to the service (source + destination).
4. Cron with `timeout` + ntfy on the `backup` topic on failure.
5. Document in `backups/strategy.md` + [`network/nfs.md`](../network/nfs.md) + the service doc.

## What needs backing up

### Psicopompo
- Docker volumes (Crafty — **until migration** to kavure; StênioBOT/Umami already migrated to kavure)
- Docker configs (compose files, env vars)
- Obsidian vault (already synced via Syncthing)
- **Desktop configs (21/09/2026):** `~/.config/hypr` (15 .lua + scripts), `~/.config/noctalia` (config.toml + merged-config.toml via `noctalia config export`), `~/.config/environment.d` (gaming/kwin/env), `~/.config/steam-launch-options` (profiles/games.toml + VDF backups), `~/.local/state/noctalia` (settings.toml = GUI overrides). Mirrored by `config-backup` → `/mnt/BACKUP/configs-homelab/psicopompo/` (git + restic + snapper). Re-fetchable Noctalia state (plugins/community/clipboard) excluded from the mirror.

### Ybytu
- AdGuard Home config (`/opt/adguardhome/conf/`)
- Filebrowser DB (`/home/ubuntu/filebrowser.db`)
- Homepage config (Docker volumes)

### Ybyra
- No critical service yet (new server, future SPA host)

### Kuaray
- Multimedia libraries (Navidrome, Lidarr, etc.) — media consolidated on psicopompo since 06/08 (`/mnt/BACKUP/media/`)
- Home Assistant DB
- MQTT config
- **Duplicati removed (06/08/2026)** — the job only covered `/DATA/AppData`; config backup will be structured in the future.

### Kavure
- **Project Zomboid (active):**
  - Daily off-box (05:15, `zomboid-backup` via `hl-zomboid-backup.timer`): mirrors the panel zips over **NFS** (`/srv/data/zomboid/offbox/daily/`) → psicopompo `/mnt/BACKUP/zomboid-server-kavure/daily/` (rsync `--delete` local→NFS; failsafe/retry/ntfy)
  - Pre-update (`zomboid-update`): save snapshot → `offbox/archive/pre-update-<data>/` (NFS)
  - Pre-migration snapshot: `archive/migration-20260805/` (1.2G) — keep
  - Local source: `/srv/data/zomboid/data/backups/` (panel autobackup, retention 7)
- **Valheim (active since 09/09/2026; backup fixed 13/09):**
  - Off-box (05:30, `valheim-backup` via `hl-valheim-backup.timer`): mirrors `saves/worlds_local/` (active world `Fimbulvetr` + the game's native auto-backups) → psicopompo NFS `/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`
  - **13/09 fix:** the script pointed at `config/backups/` (does not exist) → off-box never ran. Fixed to `saves/worlds_local/` + added the `./backups:/home/steam/backups` mount in compose (the Odin's AUTO_BACKUP now persists). Health file `/srv/health/valheim-backup-last-ok`.
  - Container: `AUTO_BACKUP` every 30 min → `./backups/` (retention 7 days) + the game's native auto-backup in `saves/worlds_local/Fimbulvetr_backup_auto-*`
- Sumænimá (sae-core) — ✅ **active since 07/08/2026**: sentinel (Borg) on kavure → NFS `/mnt/BACKUP/sumaenima-server-kavure/` (SQL dumps stenio_db + umami + `.env`). **Scheduling (29/08/2026):** switched from crond-in-container (broken since v2.22.0 — the image runs as `appuser` and crond could not read `/etc/crontabs/root`) to the homelab standard: `hl-sumaenima-backup.timer` (03:00, `Persistent=true`) → `/usr/local/bin/sumaenima-backup` → sentinel via `docker exec`. Health file `/srv/health/sumaenima-backup-last-ok` (the `BackupNotRun` alert is covered automatically — glob `/srv/health/*-last-ok`). Sentinel image without crond (29/08).
- **Monitoring (active since 13/09/2026):**
  - Off-box (05:15, `monitoring-backup` via `hl-monitoring-backup.timer`): snapshot of the Prometheus TSDB (`POST /api/v1/admin/tsdb/snapshot` — requires `--web.enable-admin-api`) + rsync `--delete` of Loki/Grafana → psicopompo NFS `/mnt/BACKUP/monitoring-server-kavure/daily/` (Prometheus in `daily/prometheus/`, Loki `daily/loki/`, Grafana `daily/grafana/`)
  - **Active storage stays LOCAL on kavure** (Docker volume) — the official Prometheus docs **do NOT support TSDB on NFS** (irreversible corruption; see issue #5342). NFS is only for the daily backup.
  - Health file `/srv/health/monitoring-backup-last-ok` (the `BackupNotRun` alert covers it automatically).
- **Overall kavure coverage (revised 13/09):** `config-backup` mirrors **all of `/srv/data`** to the NAS (git + restic) — covering Home Assistant, Pihole, Comet, Searxng, AIOStreams (except `anime-database`, which is rebuildable), Calibre, Navidrome, monitoring, n8n, Valheim configs. Deliberate exclusions: `zomboid/data`, `minecraft`, `sumaenimahub` data (they have their own/off-box backup). **Miracena:** `hl-miracena-backup.timer` enabled 13/09 (05:35) — it had been disabled (the health file was manual).

## Recommendation

### Done (09/08/2026)
1. ✅ **Canonical backup of configs** on the NAS (config-backup, 5 hosts) — `config-backup.md`
2. ✅ **btrfs snapshots** of all psicopompo disks (snapper: root/nvme/backup/hdd) — `snapshots-psicopompo.md`
3. ✅ **restic** history of configs+vault (retention 14d/8s/6m, weekly check) — no encryption (owner's decision)
4. ✅ **etckeeper** `/etc` versioned on all hosts (git → bare repos on the NAS)
5. ✅ **Git/GitHub** private `mnemocine` (mirror of the configs)
6. ✅ **Secrets** centralized in the sops/age store (see `guides/secrets-centralizados.md`); plaintext removed from the vault

### Pending
1. **Off-site (3-2-1)**: Google Drive 5TB via rclone (configs + agentic-ai + repos) or Backblaze B2. No encryption at the destination (owner's decision) — revisit the trade-off.
2. **Monthly restore drill** and quarterly `restic check --read-data` — see `backup-rituals.md`
3. **Off-host copy of the age key** (`age-keys-backup.txt`) and `secrets.env` → KeePassXC/flash drive (NEVER plaintext on the NAS)
4. **Uptime monitor in uptime-kuma** for the backup health files
5. **Recovery playbook**: test an end-to-end restore (Zomboid, Minecraft, sae-core, configs)

## Useful Commands

```bash
# Backup de volume Docker
docker run --rm -v steniobot_valkey:/volume -v /backup:/backup alpine \
  tar czf /backup/valkey-$(date +%F).tar.gz -C /volume .

# Restore de volume Docker
docker run --rm -v steniobot_valkey:/volume -v /backup:/backup alpine \
  tar xzf /backup/valkey-2026-06-01.tar.gz -C /volume
```
