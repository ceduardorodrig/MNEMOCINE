---
tags: [homelab, service, duplicati, backup]
---

# Duplicati

> **🟥 DECOMMISSIONED (2026-08-06)** — Succeeded by the [canonical configuration backup standard](../backups/config-backup.md) (NAS mirror + Restic + Git + Snapper) and off-site cloud sync (Rclone → Google Drive). Preserved for historical inventory tracking.

Historical automated backup service with web UI.

**Host Node:** ~~kuaray~~ (Historical)  
**Port:** ~~`8200`~~  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `duplicati` | `linuxserver/duplicati:latest` | Legacy backup manager |

## Current State

**Purged** — container and local volume configurations removed.

## Successor Strategy

- Native Restic snapshots targeting NAS and cloud remotes.
- Regular database dumps of PostgreSQL and application state.
- Automated systemd timers pushing encrypted datasets off-site.
