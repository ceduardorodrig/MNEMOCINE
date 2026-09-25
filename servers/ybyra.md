---
tags: [homelab, server, ybyra, docker, monitoring, tailscale]
---

# ybyra

**Role:** Cloud server (Oracle Cloud) — Sumaenima primary edge (proxy, tunnel, umami)
**Default shell:** bash (`/bin/bash`)
**Swarm role:** `primary` — Docker Swarm worker node (stack `sae-edge`)

> **Updated 28/08/2026:** full `apt dist-upgrade` (41 packages, incl. Docker engine → 29.7.2) + reboot. Kernel **6.17.0-1016 → 6.17.0-1020-oracle**. Swarm services and primary edge OK after reboot.

## Hardware

| Item | Specification |
|---|---|
| **OS** | Ubuntu 24.04.4 LTS (KVM — QEMU Standard PC) |
| **Kernel** | 6.17.0-1020-oracle |
| **CPU** | AMD EPYC 7551 32-Core (2 vCPUs — 1 core/2 threads, Oracle free tier) |
| **RAM** | 954 MB (no swap configured) |
| **System Disk** | 150 GB — Boot Volume (Oracle Block Storage) — `sda1` ext4 — 2% used (3 GB) |
| **Swap** | None |
| **Tailscale IP** | 100.66.224.34 |
| **Tailscale DNS** | ybyra.chimaera-heptatonic.ts.net |
| **Network** | Oracle internal network (`ens3`: 10.0.0.40/24) |

## Roles

- New cloud server (Oracle free tier)
- Future Single Page Application host (Docker)

## Tailscale Funnels

| URL | Destination | Status |
|---|---|---|
| `https://sumaenima.chimaera-heptatonic.ts.net` | `http://proxy:80` | Active — proxies to the Swarm nginx |

## Docker Containers — Utilities (Standalone)

| Container | Image | Ports | Function |
|---|---|---|---|
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoring |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |

## Swarm Services (Managed by the Docker Swarm on psicopompo)

| Service | Image | Ports | Function |
|---|---|---|---|
| proxy | nginx-sumaenima:latest | `0.0.0.0:80` | Reverse proxy (SPA, API, Umami) |
| tunnel | tailscale/tailscale:latest | — | Tailscale Funnel (sumaenima.chimaera-heptatonic.ts.net) |
| umami | sumaenima-umami:latest | 3000 | Analytics (reachable via nginx `/umami/`) |
| ~~datavis~~ | ~~datavis-server:latest~~ | ~~9091~~ | **removed 22/09/2026** — legacy, nothing consumed it; CVE-2025-67221 (orjson) closed by removal |

## Native Programs

| Program | Function |
|---|---|
| tailscaled | Tailscale agent |
| Docker Engine | Container runtime (v29.7.2) |
| nginx | Primary Edge (traffic routing, virtual DNS, SPA Frontend) |

## Important Ports

| Port | Service | Bind |
|---|---|---|
| 22 | SSH | Tailscale |
| 80 | Nginx (Primary Edge — SPA, API, Umami) | `0.0.0.0` |
| 61208 | Glances | `0.0.0.0` |

## Notes

- Oracle free tier server (June 2026): 2 vCPUs, 1 GB RAM, 150 GB disk.
- Server **exclusively as the primary edge** of the Sumænimá Hub.
- All public traffic enters via Tailscale Funnel (`sumaenima.chimaera-heptatonic.ts.net` → proxy:80).
- Nginx routes:
  - `/` → SPA (React + Vite)
  - `/api/` → FastAPI (steniobot-api on psicopompo, overlay network)
  - `/umami/` → Umami (on ybyra itself, overlay network)
- ~~`/api/datavis/`~~ → removed 22/09/2026 (legacy) — 404 now, it used to be 502
- It does **not** run filebrowser, syncthing or other utilities — those live on ybytu.
- Utility containers (glances, autoheal, watchtower) run standalone outside the Swarm.
- No Kuaray service runs here — kuaray is the separate media server.
- See `network/topology.md` for the full network topology.
- **Fix NFS (10/09/2026):** `hard` → `soft` entries in fstab (`configs-homelab`, `repos/git`). Backup: `/etc/fstab.bak.20260910`. Docker drop-in: `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). See [`network/nfs.md`](../network/nfs.md).
