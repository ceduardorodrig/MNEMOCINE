---
tags: [homelab, guia, zomboid, migracao, handoff, psicopompo]
---

# Handoff — Zomboid on psicopompo (migrated to kavure) — **COMPLETED**

> **Date:** 06/08/2026 · **Reason:** PZ server migrated to kavure (Docker). Local infra on psicopompo **shut down and data destroyed** (with validated backup).

## Context

- The original Project Zomboid server ran on **psicopompo** via LinuxGSM (user `pzserver`).
- It was migrated to **kavure** (Docker — `danixu86/project-zomboid-dedicated-server`), doc: [`project-zomboid.md`](project-zomboid.md).
- The **data (game) was left untouched** (not deleted) — user's decision. Only the **processes, services, timers, crons, user and permissions** were shut down.

## What was shut down (06/08/2026)

### 1. Main service
| Item | State |
|---|---|
| `zomboid.service` | `stop` + `disable` → **inactive / disabled** |
| Description | `Project Zomboid Server - VaiMorreSim [PSICOPOMPO] (LinuxGSM)` — user `pzserver`, `WorkingDirectory=/home/pzserver/server`, `ExecStart=/home/pzserver/server/pzserver start` |

### 2. systemd timers
| Timer | Before | Now |
|---|---|---|
| `pzserver-monitor.timer` (every 5min) | enabled | **disabled** + stopped |
| `pzserver-backup.timer` (04:00 daily) | enabled | **disabled** + stopped |
| `pzserver-restart.timer` (05:00 daily) | enabled | **disabled** + stopped |
| `pzserver-update.timer` (every 30min) | disabled | disabled (already was) |
| `pzserver-update-lgsm.timer` (Sun 00:00) | disabled | disabled (already was) |

The `.service` files (oneshot: `pzserver-backup`, `pzserver-monitor`, `pzserver-restart`, `pzserver-update`, `pzserver-update-lgsm`) are `static` — triggered by the timers; with the timers off, they never run.

### 3. Helper scripts
- `/usr/local/libexec/pzserver-backup` — daily backup (stop + restart via LinuxGSM)
- `/usr/local/libexec/pzserver-monitor-health` — monitors the tmux session, restarts it if it dies
- `/usr/local/libexec/pzserver-restart` — daily restart

> **Removed during the destruction** (06/08/2026).

### 4. User and permissions
| Item | State |
|---|---|
| user `pzserver` (uid 888) | shell changed to **`/usr/sbin/nologin`** + password locked (`passwd -l`), then **`userdel -r` (removed)** |
| `/etc/sudoers.d/pzserver` | **removed** (was `edu ALL=(pzserver) NOPASSWD: /home/pzserver/server/pzserver *`) |
| `sudoers` validated | `visudo -c` → **parsed OK** |

### 5. Residual processes
- A `ProjectZomboid64` running as `edu` (user test at 02:54) was killed. Confirmed: **no remaining pzserver/ProjectZomboid64 process**; port `16261` closed.

## What was removed during the destruction (06/08/2026 — backups validated beforehand)

- ✅ `/home/pzserver/` (5.7G — game data, config) + user `pzserver`
- ✅ `/mnt/NVME_PCI/zomboidserver [knox-county]/` (22G — LinuxGSM + serverfiles + `lgsm/backup` 13G)
- ✅ `.service`/`.timer` units (11) + `libexec` scripts (3) + lock `/run/pzserver-maintenance.lock` + tmux `/tmp/tmux-888/`
- ✅ `/home/edu/Zomboid` (local game test artifact)

## Off-box backup (important — do NOT break)

- **kavure** keeps sending backups here: `zomboid-update` (on kavure) runs `rsync -aHAX /srv/data/zomboid/data/ → edu@100.82.51.112:/mnt/BACKUP/zomboid-server-kavure/archive/pre-update-<data>/`.
- **`zomboid-backup`** (new, cron 01:15 on kavure) mirrors the panel's zips → `daily/` (rsync `--delete`, inherited retention = 7). It uses **`edu@`** → does not depend on a removed user/service. ✅
- Preserved backups: `/mnt/BACKUP/zomboid-server-kavure/daily/` (5.6G, automatic mirror 01:15) + `archive/migration-20260805/` (1.2G) — **keep**.

## Final verification

```bash
systemctl list-timers --all | grep pzserver   # (vazio)
pgrep -af ProjectZomboid64               # (vazio)
ss -lunpt | grep 16261                   # (vazio)
getent passwd pzserver                   # (user removido)
```

## Pending items — COMPLETED (06/08/2026)

**Permanent destruction executed** (backups validated beforehand — see the Backup section):

1. ✅ **Game data removed** — `/home/pzserver` (5.7G) + `/mnt/NVME_PCI/zomboidserver [knox-county]` (22G, incl. 13G of old snapshots in `lgsm/backup`)
2. ✅ **systemd units removed** — `zomboid.service` + 5 `pzserver-*.{service,timer}` + `systemctl daemon-reload`
3. ✅ **User `pzserver` removed** (`userdel -r`, uid 888) + `/home/pzserver`
4. ✅ **`libexec` scripts removed** (`pzserver-backup`, `pzserver-monitor-health`, `pzserver-restart`)
5. ✅ **Residue removed** — `/run/pzserver-maintenance.lock`, tmux socket `/tmp/tmux-888/`, `/home/edu/Zomboid` (test artifact)
6. ✅ **`verify_infra.py` removed** from the repo (and refs in SECURITY/auto-sync/health-endpoints)

**Backups preserved before the destruction:**
- `/mnt/BACKUP/zomboid-server-kavure/daily/` (5.6G) — panel mirror (world backup + startup + version), **validated (`zip OK`)**, automatic via `zomboid-backup` (cron 01:15 on kavure)
- `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/` (1.2G) — pre-migration snapshot
- kavure keeps serving (`pz-server: Up`, panel healthy)

**Space freed:** `/mnt/NVME_PCI` 810G → 825G free (~15G of data; the rest was on `/` and `/home`).

## See also
- [[project-zomboid]] — current server on kavure (Docker)
- [[zomboid-control-panel]] — admin panel
- [[kavure-migration-plan]] — migration plan
- [[psicopompo]] — source server
