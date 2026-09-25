---
tags: [homelab, service, crafty, gaming]
---

# Crafty Controller

Minecraft server management panel.

**Server:** kavure
**Admin Port:** `8444` (host `8444` → container `8443`)
**Game Port:** `25565`
**URL:** `https://kavure.chimaera-heptatonic.ts.net:8444`

> **✅ Migrated to kavure (08/08/2026 — Phase C1):** Crafty + the Dominium server (Minecraft 1.21.1/Fabric) moved from psicopompo with **rsync `--checksum` (0 differences)**. The **backup (AdvancedBackups) now goes straight to the NAS** over NFS (`/srv/data/minecraft/offbox` → `/mnt/BACKUP/minecraft-server-kavure/`), following the zomboid pattern. JVM configured with **G1 flags** (floor 2G / ceiling 8G / soft 5G) to coexist with Zomboid. psicopompo was left intact (crafty stopped, nothing deleted).
>
> **Backup (13/09/2026):** AdvancedBackups writes to `/minecraft-backups` (= offbox → NAS) every 2h **only while the server is running**. Server stopped since 08/08 → last full backup 28/06 (partials up to 08/08). **Expected gap** — when the server comes back, the automatic backup resumes. If you are re-enabling without starting the server, rsync the world manually first.

## Stack

| Container | Image | Role |
|---|---|---|
| crafty-controller | crafty-4 | Management + Minecraft server |

## Ports

| Port | Role |
|---|---|
| `8443` | Web interface (HTTPS) |
| `25565` | Minecraft server (Java) |
| `25575` | RCON (localhost) |
| `8123` | Dynamic map |
| `5520-5550` | Proxy/portals |
| `19132` | Bedrock |

## Access

`https://kavure.chimaera-heptatonic.ts.net:8444`

## Data

Persistent Docker volumes with Crafty's settings, worlds and automatic backups.

## Servers

- [[dominium-permissions]] — Dominium modded server (groups, players, permissions)
