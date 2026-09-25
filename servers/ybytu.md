---
tags: [homelab, server, ybytu, dns, monitoring, changedetection, ntfy]
---

# ybytu

> Real OS hostname: `ybytu-vnic` (Tailscale shows it as `ybytu`)

**Role:** Cloud server (Oracle Cloud) — DNS, dashboard, sync
**Default shell:** bash (`/bin/bash`)

## Hardware

| Item | Specification |
|---|---|
| **OS** | Ubuntu 24.04.4 LTS |
| **Kernel** | 6.17.0-1020-oracle |
| **CPU** | AMD EPYC 7551 (2 vCPUs — Oracle free tier, 1 core/2 threads) |
| **RAM** | 954 MB (ZRAM: 477 MB, 354 MB in use) |
| **System Disk** | 50 GB — virtual HDD (Oracle Block Volume) — 17% used (8 GB) |
| **Swap** | 477 MB (ZRAM) |
| **Tailscale IP** | 100.115.253.109 |
| **Tailscale DNS** | ybytu.chimaera-heptatonic.ts.net |
| **Network** | Oracle internal network (`ens3`: 10.0.0.136/24, MTU 9000) |

## Roles

- Tailnet Exit Node
- DNS with ad blocking (AdGuard Home)
- Central homelab dashboard (Homepage)
- Uptime monitoring (Uptime Kuma)
- Change monitoring on pages (Changedetection.io)
- Push notifications (Ntfy)

## Tailscale Funnels

None.

## Docker Containers

| Container | Image | Ports | Function |
|---|---|---|---|---|
| adguardhome | adguard/adguardhome:latest | `0.0.0.0:53`, `0.0.0.0:3000` | DNS ad-blocking |
| homePage | ghcr.io/gethomepage/homepage:latest | `0.0.0.0:3001` | Homelab dashboard |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoring |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `127.0.0.1:2375` | Docker socket proxy |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| uptime-kuma | louislam/uptime-kuma:latest | `0.0.0.0:3002` | Uptime monitoring |
| changedetection | dgtlmoon/changedetection.io:latest | `0.0.0.0:8082` | Change monitoring |
| ntfy | binwiederhier/ntfy:latest | `0.0.0.0:8083` | Push notifications |

## Native Programs

| Program | Function | Port |
|---|---|---|
| ~~filebrowser (systemd)~~ | ~~Web file server v2.63.5~~ — **removed/inactive (28/08/2026)**, unit does not exist and the port is closed | ~~`8334`~~ |
| vnstat | Traffic monitor | — |
| tailscaled | Tailscale agent (v1.98.4) | — |

## Important Ports

| Port | Service | Bind |
|---|---|---|
| 53 | AdGuard Home (DNS) | `0.0.0.0` |
| 3000 | AdGuard Home (admin) | `0.0.0.0` |
| 3001 | Homepage | `0.0.0.0` |
| ~~8334~~ | ~~Filebrowser~~ | — |
| 2375 | Docker proxy | `127.0.0.1` |
| 61208 | Glances | `0.0.0.0` |
| 3002 | Uptime Kuma | `0.0.0.0` |
| 8082 | Changedetection | `0.0.0.0` |
| 8083 | Ntfy | `0.0.0.0` |

## Notes

- **AdGuardHome** runs **as a container only** (the native `/opt/adguardhome/` no longer exists).
- **Filebrowser**: **removed/inactive (28/08/2026)** — the systemd unit does not exist, the binary is not installed, port 8334 is closed. The previous doc was out of date.
- Containers **do not use Docker Compose** — they were started individually.
- The `/home/ubuntu/homelab/homepage/config/` folder contains the homepage configuration YAML files.

## Update 28/08/2026

- **Full upgrade** `apt dist-upgrade` (51 packages) + reboot. Kernel **6.17.0-1018 → 6.17.0-1020-oracle**.
- **Docker engine updated** (29.5.x → 29.7.2) along with apt. Containers with `restart: unless-stopped` came up on their own.
- **Post-reboot incident:** the host did not return to the tailnet + SSH did not answer the banner (public IP `64.181.168.251`) → **force reboot** via the OCI panel (OS Management) fixed it. From then on the tailnet came back, all 9 containers up (dockerproxy restarted manually after exit 255), exit node active, NFS automount (`/srv/backup-configs`, `/srv/backup-gitrepos` → psicopompo NAS) OK.
- **Fix NFS (10/09/2026):** `hard` → `soft` entries in fstab (`configs-homelab`, `repos/git`). Backup: `/etc/fstab.bak.20260910`. Docker drop-in: `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). See [`network/nfs.md`](../network/nfs.md).
