---
tags: [homelab, service, rclone, storage, cloud]
---

# Rclone

Cloud storage synchronization and remote filesystem mount client (Google Drive) — CLI + FUSE mounts.

**Host Node:** psicopompo  

## System Units

| Unit (Systemd --user) | Function | Status |
|---|---|---|
| `rclone-webgui.service` | Rclone Web GUI + Remote Control daemon | ❌ **Decommissioned (2026-08-26)** — Unused endpoint purged |
| `rclone-mount.service` | FUSE mount of `gdrive:` to `/home/edu/Google_Drive` | ✅ Active |

## Configuration & Mount Specifications

- Configuration: `/home/edu/.config/rclone/rclone.conf`
- Remote Target: `gdrive:` (Drive scope)
- Local Mountpoint: `/home/edu/Google_Drive`

Operational commands:
```bash
# Mount Google Drive FUSE filesystem:
systemctl --user start rclone-mount.service

# Re-authenticate Google OAuth token (requires local browser):
rclone config reconnect gdrive:
```

## Off-Site Cloud Mirror — BACKUP MNEMOCINE

- **Daily Off-Site Backup:** Synchronizes `/mnt/BACKUP` (221 GB) → `gdrive:BACKUP MNEMOCINE` via `/usr/local/bin/rclone-gdrive-backup`.
- **Systemd Scheduler:** Governed by `hl-rclone-gdrive-backup.timer` running daily at **06:30 BRT** (`Persistent=true`).
- **Deletion Safeguard:** Deleted assets stage into `gdrive:_deleted/<date>/` using `--backup-dir` with `--max-delete 200` to prevent destructive sync loops.
- **Snapshot Exclusion:** Subvolumes `.snapshots/**`, `.stversions/**`, and `.Trash-1000/**` are strictly excluded from transmission to prevent syncing local Btrfs snapshot iterations.
- **OAuth Refresh Token Stability:** The Google Cloud OAuth consent screen is configured as **"In Production"**, preventing Google's 7-day token revocation policy enforced on testing apps.

## See Also
- [`../../servers/psicopompo.md`](../../servers/psicopompo.md) — Workstation node profile
- [`../backups/strategy.md`](../backups/strategy.md) — Homelab backup architecture
- [`../backups/backup-rituals.md`](../backups/backup-rituals.md) — Audit and health check procedures
