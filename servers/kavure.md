---
tags: [homelab, server, kavure, docker, storage, gaming, todo]
---

# kavure

**Role:** Dedicated application server — Sumænimá Swarm Manager (`sae-core`), Minecraft Dominium, Project Zomboid, Valheim, and core monitoring.  
**Default Shell:** bash (`/bin/bash`)  

## Hardware Specifications

| Component | Specification |
|---|---|
| **Chassis** | Dell OptiPlex 3060 SFF |
| **CPU** | Intel Core i3-8100 4C/4T @ 3.60 GHz |
| **RAM** | 12 GB DDR4 (11 GiB addressable, 2 DIMM slots) |
| **System Storage** | 223 GB SATA 2.5" SSD (Kingston SA400S3) — LVM configuration (217 GB on `/`) |
| **Planned Expansion** | M.2 SATA 1 TB (OS/Docker) + 3.5" HDD 4–8 TB (Bulk Storage) |
| **Network** | Gigabit Ethernet (`enp1s0`, wired to gigabit switch) |
| **LAN IP** | `192.168.3.41/24` via switch |
| **MTU (PPPoE)** | **1492** (netplan `enp1s0`) aligned with WAN uplink |
| **OS** | Ubuntu 24.04 LTS (kernel `6.8.0-142`) |
| **Filesystem** | LVM + ext4 |
| **Tailscale IP** | `100.124.146.77` — `kavure` |
| **Access** | `tailscale ssh kavure@kavure` |

## Operational Capabilities & Architecture

- **Docker Swarm Manager (`role=core`):** Orchestrates the `sae-core` stack (PostgreSQL, Valkey, API `:9090`, Umami DB, backup daemon, and Asciline).
- **Sumænimá Edge Standby:** Configured as backup failover node (`edge_backup=true`) hosting dormant standby replicas of `proxy`, `tunnel`, and `umami`.
- **Game Server Host:** Dedicated containerized game environments:
  - **Project Zomboid:** `danixu86/project-zomboid-dedicated-server` (active since 2026-08-06);
  - **Minecraft Dominium:** Crafty Controller running Fabric Loader on Minecraft 1.21.1;
  - **Valheim:** Dedicated container server (`mbround18/valheim:3`).
- **Subnet Router (Activated 2026-10-05):** Advertises route `192.168.3.0/24` across the Tailnet, granting remote access to local IoT devices and home routers.
- **DNS Core Resolver (2026-10-08):** Runs Pi-hole alongside a native **recursive `unbound`** instance (`127.0.0.1:5053`, DNSSEC validation). Monitored by a dedicated Rust watchdog (`hl-dns-watchdog.timer`).

## Storage Layout & Directory Structure

```
/srv/data/zomboid/              ← Project Zomboid container volume
/srv/data/pihole/               ← Pi-hole ad-blocking configuration and gravity.db
/srv/data/dnscrypt-proxy/       ← Cold storage archive (superseded by native unbound)
/srv/data/ops/                  ← Infrastructure operations stack (autoheal, watchtower, glances)
/srv/data/sumaenimahub/         ← Sumænimá Swarm runtime data and volumes
/srv/data/sumaenimahub/backup   ← NFS mount -> psicopompo:/mnt/BACKUP/sumaenima-server-kavure
/srv/data/minecraft/            ← Crafty Controller and Minecraft Dominium server assets
/srv/data/valheim/              ← Valheim dedicated server data
/srv/data/valheim/offbox        ← NFS mount -> psicopompo:/mnt/BACKUP/valheim-server-kavure
/var/lib/docker/                ← Docker storage root (overlay2)
```

## Systemd Automated Backups

| Timer | Schedule | Protected Service | Target Destination |
|---|---|---|---|
| `hl-config-backup.timer` | 05:00 | Host configurations | rsync $\rightarrow$ NAS mirror |
| `hl-zomboid-backup.timer` | 05:15 | Project Zomboid world saves | rsync $\rightarrow$ NAS mirror |
| `hl-valheim-backup.timer` | 05:30 | Valheim world saves | rsync $\rightarrow$ NAS mirror |
| `hl-sumaenima-backup.timer` | 03:00 | Sumænimá database & uploads | Borg + pg_dump $\rightarrow$ NAS mirror |

## Network & Wake-on-LAN

Wired into the `IT-BLUE LE-4203` gigabit switch (`1000 Mb/s full-duplex`). Wake-on-LAN is persisted via Netplan and systemd (`wol@enp1s0`). The host responds to magic packets from psicopompo or kururu within 29–39 seconds from S5 power-off.

## Container Healthchecks

All standalone containers on this node implement explicit healthcheck definitions, integrated with `autoheal` for autonomous remediation.

## See Also

- [`network/kavure-migration-plan.md`](../network/kavure-migration-plan.md) — Service migration blueprint
- [`services/crafty.md`](../services/crafty.md) — Minecraft server controller
- [`services/unbound.md`](../services/unbound.md) — Recursive local DNS resolver
