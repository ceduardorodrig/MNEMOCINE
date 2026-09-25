---
tags: [homelab, automation, backup, ritual]
---

# Homelab Automations — Log

Source of truth: [`schedules.json`](schedules.json) (JSON). These tables are the human-readable view.
Rule: **every new/changed/removed job = update `schedules.json` and these tables in the same step** (canonical AGENTS.md).

> **Scheduler (10/08/2026):** all **customized** homelab jobs migrated from cron to **systemd timers** `hl-*.timer` (`Persistent=true` — if the machine is off at the scheduled time, the job runs on the next boot). The **native cron** (Ubuntu/Mint) and **cronie** (psicopompo, kept for future use) remain active only for OS jobs (`e2scrub_all`, `sysstat`, `anacron`, `0hourly`). Source: `schedules.json` (`type=systemd-timer`) and units in `/etc/systemd/system/hl-*.{service,timer}`.

## Backup window (standard)

- **Local (psicopompo/kavure/kuaray):** 05:00–06:00 BRT (`America/Sao_Paulo`).
- **VPS (ybytu/ybyra):** 08:00 UTC (= 05:00 BRT).

| Time | Job |
|---|---|
| 05:00 | config-backup (all hosts) + zomboid-restart (kavure) |
| 05:15 | zomboid-backup (kavure) + **monitoring-backup (kavure, 13/09)** |
| 05:20 | agentic-ai-backup (psicopompo) |
| 05:25 | n8n-backup (kavure) |
| 05:30 | valheim-backup (kavure) |
| 05:35 | miracena-backup (kavure, timer enabled 13/09) |
| 05:40 | restic-configs-backup (psicopompo) |
| 05:55 | etckeeper-push + configs-git-push |
| Sun 06:00 | restic-configs-check |

## Per-host table

### psicopompo
| Job | Schedule | Purpose |
|---|---|---|
| config-backup | 05:00 BRT | Mirror configs to the NAS |
| agentic-ai-backup | 05:20 BRT | Copy of the vault |
| restic-configs-backup | 05:40 BRT | Versioned history (14d/8s/6m) |
| restic-configs-check | Sun 06:00 | Repo integrity |
| rclone-gdrive-backup | 06:30 BRT | Off-site → Google Drive |
| configs-git-push | 05:55 BRT | Push to GitHub `mnemocine` |
| etckeeper-push | 05:55 BRT | Push /etc → NAS |
| **hl-health-metrics** | **every 5 min** | Textfile: health files + systemd units (28/08) |
| **hl-container-metrics** | **every 2 min** | Textfile: container state (28/08) |
| **hl-smart-metrics** | **every 15 min** | Textfile: SMART data for the disks (28/08) |
| snapper-timeline | hourly | Disk snapshots |
| snapper-cleanup | daily | Snapshot cleanup |
| snap-pac hooks | on every pacman run | Pre/post update snapshot |
| watchtower | 24h polling | Auto-update |

### kavure
| Job | Schedule | Purpose |
|---|---|---|
| config-backup | 05:00 BRT | Mirror configs |
| etckeeper-push | 05:55 BRT | Push /etc |
| zomboid-restart | 05/11/17/23 | Graceful PZ restart |
| zomboid-backup | 05:15 BRT | Saves → NFS |
| **monitoring-backup** | **05:15 BRT** | Snapshot Prometheus + Loki/Grafana → NFS (13/09) |
| **n8n-backup** | **05:25 BRT** | n8n Postgres dump → NFS (28/08) |
| **valheim-backup** | **05:30 BRT** | World `worlds_local` → NFS (fixed 13/09) |
| **miracena-backup** | **05:35 BRT** | PG/MariaDB dump + uploads → NFS (timer enabled 13/09) |
| sae-core_backup (borg) | 03:00 | SQL dumps → NFS |
| **hl-health-metrics** | **every 5 min** | Textfile: health files + systemd units (28/08) |
| **hl-container-metrics** | **every 2 min** | Textfile: container state (28/08) |
| **hl-smart-metrics** | **every 15 min** | Textfile: SMART data for the physical disks (28/08) |
| watchtower | 03:00 BRT | Auto-update (only active one for updates) |
| AdvancedBackups | internal | Minecraft world → NFS |
| zomboid panel autobackup | internal | Saves (retention 7) |

### kuaray
| Job | Schedule | Purpose |
|---|---|---|
| config-backup | 05:00 BRT | Mirror configs (rebuilt 08/08) |
| etckeeper-push | 05:55 BRT | Push /etc |
| timeshift-hourly | 05:00 | timeshift check (NO active snapshots — re-evaluate) |
| **hl-health-metrics** | **every 5 min** | Textfile: health files + systemd units (28/08) |
| **hl-container-metrics** | **every 2 min** | Textfile: container state (28/08) |
| **hl-smart-metrics** | **every 15 min** | Textfile: SMART data for the HDD (28/08 — picked up pending=37) |
| watchtower | **PAUSED** | Auto-update (pending decision) |

### ybytu (UTC)
| Job | Schedule | Purpose |
|---|---|---|
| config-backup | 08:00 UTC | Mirror configs |
| etckeeper-push | 08:55 UTC | Push /etc |
| **hl-health-metrics** | **every 5 min** | Textfile: health files + systemd units (28/08) |
| **hl-container-metrics** | **every 2 min** | Textfile: container state (28/08) |
| watchtower | 24h polling | Auto-update |

### ybyra (UTC)
| Job | Schedule | Purpose |
|---|---|---|
| config-backup | 08:00 UTC | Mirror configs |
| etckeeper-push | 08:55 UTC | Push /etc |
| **hl-health-metrics** | **every 5 min** | Textfile: health files + systemd units (28/08) |
| **hl-container-metrics** | **every 2 min** | Textfile: container state (28/08) |
| watchtower | 24h polling | Auto-update |

## Schema (`schedules.json`)

```json
{
  "id": "exemplo-job",
  "host": "kavure",
  "name": "nome-curto",
  "type": "cron | systemd-timer | hook | docker | swarm-service | docker-internal",
  "schedule_cron": "0 5 * * *",
  "tz": "America/Sao_Paulo | UTC | null",
  "command": "comando completo",
  "purpose": "o que faz",
  "enabled": true,
  "notify": "ntfy /backup | logger | null",
  "health_file": "/srv/health/... | null",
  "doc": "caminho da doc no vault"
}
```

## Runbook — adding/changing/removing a job

1. **Create/edit the job** (cron, systemd timer, etc.) on the host.
2. **Update `schedules.json`** + the tables in this README.
3. Update the doc for the corresponding service (if it affects backups, reference `backups/config-backup.md`).
4. Validate: run the job manually and check health/ntfy.
5. If the backup window changes: update the "Window" table above and the `/etc/cron.d/*`.

## OS defaults (do not manage)

fstrim, logrotate, apt-daily*, sysstat, e2scrub, dpkg-db-backup, man-db, fwupd-refresh, motd-news, mintupdate-automation (kuaray), anacron (kuaray), shadow, plocate, cachyos-rate-mirrors. Listed in the JSON as a reference; agents must not modify them.
