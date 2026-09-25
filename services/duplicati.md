---
tags: [homelab, service, duplicati, backup]
---

# Duplicati

> **🟥 REMOVED (06/08/2026)** — it did not cover valuable data; replaced by the
> [canonical config backup](../backups/config-backup.md) (NAS mirror + restic + git + snapper) and the off-site (rclone → Drive).

Automated backup with a web interface.

**Server:** ~~kuaray~~ (historical)
**Port:** ~~`8200`~~

## Stack

| Container | Image | Role |
|---|---|---|
| duplicati | linuxserver/duplicati:latest | Backup |

## Access

`http://kuaray.chimaera-heptatonic.ts.net:8200`

## Current State

**Removed** — no longer running. Kept as a historical record.

## Recommendations

- Set up cloud off-site backup (B2, S3, etc.)
- Backup of the StênioBOT and Umami PostgreSQL databases
- Backup of the Tailscale configs (not essential, but useful)
- Test the restore periodically
