---
tags: [homelab, guide, zomboid, migration, handoff, psicopompo]
---

# Handoff — Project Zomboid Decommissioning on Psicopompo (Completed)

> **Execution Date:** 2026-08-06 · **Objective:** Migration of dedicated Project Zomboid services from psicopompo to kavure. Legacy local infrastructure on psicopompo **decommissioned and purged**, backed by verified off-box snapshots.

## Context

- The original Project Zomboid instance was hosted on **psicopompo** using LinuxGSM under user account `pzserver`.
- The workload transitioned to a containerized Docker deployment on **kavure** (`danixu86/project-zomboid-dedicated-server`), documented in [`project-zomboid.md`](project-zomboid.md).
- Following checksum-verified data migration, local services, crons, systemd units, and dedicated users on psicopompo were permanently purged.

## Decommissioning Summary (2026-08-06)

### 1. Main Service Unit
| Unit | Previous State | Final State |
|---|---|---|
| `zomboid.service` | Active / Running | **Stopped & Masked / Disabled** |

### 2. Systemd Automation Timers
| Timer Name | Previous State | Final State |
|---|---|---|
| `pzserver-monitor.timer` | Enabled | Disabled and stopped |
| `pzserver-backup.timer` | Enabled | Disabled and stopped |
| `pzserver-restart.timer` | Enabled | Disabled and stopped |
| `pzserver-update.timer` | Disabled | Disabled |
| `pzserver-update-lgsm.timer` | Disabled | Disabled |

All dependent `.service` unit files were deleted and daemon reloaded.

### 3. Dedicated Scripts & Binary Daemons
Purged from `/usr/local/libexec/`:
- `pzserver-backup`
- `pzserver-monitor-health`
- `pzserver-restart`

### 4. User Accounts & Sudo Permissions
| Item | Action Taken |
|---|---|
| User `pzserver` (UID 888) | Shell changed to `/usr/sbin/nologin`, account locked, and deleted via `userdel -r` |
| `/etc/sudoers.d/pzserver` | File deleted and validated via `visudo -c` |

### 5. Filesystem Cleanup
- Purged `/home/pzserver/` (5.7 GB).
- Purged `/mnt/NVME_PCI/zomboidserver [knox-county]/` (22 GB including legacy LinuxGSM archives).
- Reclaimed 15 GB on NVMe storage.

## Active Off-Box Backup Verification

- kavure continues pushing daily backup snapshots to psicopompo NAS storage over NFS: `/mnt/BACKUP/zomboid-server-kavure/daily/` and `archive/migration-20260805/`.
- The backup pipeline runs under user `edu` via NFSv4 permissions, completely decoupled from the purged `pzserver` system account.

## See Also
- [`project-zomboid.md`](project-zomboid.md) — Active dedicated server on kavure
- [`zomboid-control-panel.md`](zomboid-control-panel.md) — Web administration console
- [`../../servers/psicopompo.md`](../../servers/psicopompo.md) — Workstation node profile
