---
tags: [homelab, server, kuaray, docker, storage, media, home-assistant, automation]
pending: [HB-013]
---

# kuaray

> ## 🚀 REACTIVATED (2026-10-04)
> Node reintegrated into the active topology via a wired Ethernet link (`enp7s0`, 100 Mb/s full-duplex, 0.28 ms LAN latency).
> Assumes the role of dedicated host for the **Miracena Stack** (offloading active memory from Kavure) and the **Multimedia Stack** (*arr services, torrent, Soulseek), reading primary libraries over NFS from psicopompo.

**Role:** Miracena Client Project Stack (Directus, WordPress, Nuxt 3, n8n, DBs) + Multimedia Suite (*arr stack, P2P, streaming)  
**Default Shell:** bash (`/bin/bash`)  
**Swarm Role:** **none** — kuaray is **not** a Docker Swarm node (`docker info` → `Swarm: pending`); it runs **standalone Docker/Compose only**. The Sumænimá edge standby lives on **kavure**, not here.  

> **Correction (2026-10-13):** the previous claim — *"`standby` — Docker Swarm worker node holding dormant failover containers"* — was **materially wrong**. Verified live: `docker info` reports `Swarm: pending`, and the Swarm manager (`kavure`) lists only **psicopompo / kavure / ybyra** as nodes. The dormant `sae-edge_*` standby replicas are scheduled on **kavure** (`node.labels.edge_backup == true`), never on kuaray.

## Hardware Specifications

| Component | Specification |
|---|---|
| **OS** | Linux Mint 22.3 (Zena) |
| **Kernel** | 7.0.0-38-generic |
| **CPU** | Intel Core i5-4200U @ 1.60 GHz (Turbo up to 2.60 GHz) — 2C/4T |
| **GPU** | Intel HD Graphics (Haswell) + NVIDIA GeForce GT 740M |
| **RAM** | 5.7 GB (3.4 GB in active use) |
| **Swap** | 5.4 GB disk swap + 3.4 GB ZRAM |
| **System Disk** | 224 GB SATA SSD (Kingston A400) — `/dev/sda2` |
| **Storage Disk** | 932 GB SATA HDD (Seagate 1 TB) — `/dev/sdb1` (MBR partition starting at LBA 2048 to isolate legacy bad sectors) |
| **Tailscale IP** | 100.94.209.99 |
| **Tailscale DNS** | kuaray.chimaera-heptatonic.ts.net |
| **Network Interfaces** | Realtek RTL810xE Fast Ethernet (`enp7s0`: 192.168.3.200/24) + Qualcomm Atheros QCA9565 Wi-Fi (`wlp6s0`, metric 600) |
| **MTU (PPPoE)** | **1492** (NetworkManager) configured to match WAN uplink |
| **Access** | `tailscale ssh kuaray@kuaray` · **OpenSSH key-only** (sem senha desde 13/10 — [detalhe](../network/tailscale.md)) |

## Operational Workloads

### Miracena Stack (`/srv/data/miracena/`)

| Container | Image | Ports | Responsibility |
|---|---|---|---|
| miracena-postgres | `postgres:16-alpine` | `5432` (internal) | PostgreSQL database for Directus and n8n |
| miracena-mariadb | `mariadb:11` | `3306` (internal) | MariaDB database for WordPress |
| miracena-redis | `redis:7-alpine` | `6379` (internal) | Redis caching layer for Directus |
| miracena-directus | `directus/directus:latest` | `100.94.209.99:8055` | Headless CMS backend |
| miracena-wordpress | `wordpress:latest` | `100.94.209.99:8085` | WordPress content management engine |
| miracena-nuxt | `node:22-alpine` | `100.94.209.99:3003` | Nuxt 3 web frontend |
| miracena-n8n | `docker.n8n.io/n8nio/n8n:stable` | `100.94.209.99:5678` | Workflow automation server |
| miracena-nginx-proxy-manager | `jc21/nginx-proxy-manager:latest` | `81`, `8180`, `8445` | Reverse proxy and SSL management |
| miracena-tunnel | `tailscale/tailscale:latest` | HTTPS 443 | Ingress Tailscale Funnel endpoint |

### Multimedia Suite & Homelab Services (`/home/kuaray/homelab/`)

| Container | Image | Ports | Responsibility |
|---|---|---|---|
| lidarr | `lscr.io/linuxserver/lidarr:latest` | `0.0.0.0:8686` | Music collection manager |
| prowlarr | `lscr.io/linuxserver/prowlarr:latest` | `0.0.0.0:9696` | Torrent and Usenet indexer proxy |
| transmission | `lscr.io/linuxserver/transmission:latest` | `0.0.0.0:9091`, `51413` | BitTorrent client daemon |
| slskd | `slskd/slskd:latest` | `0.0.0.0:5030` | Soulseek P2P client daemon |
| soularr | `mrusse08/soularr:latest` | `0.0.0.0:8265` | Bridge connecting Soulseek to Lidarr |
| flaresolverr | `ghcr.io/flaresolverr/flaresolverr:latest` | `0.0.0.0:8191` | Cloudflare challenge proxy |
| vert | `ghcr.io/vert-sh/vert` | `0.0.0.0:3030` | Decentralized microblogging web UI |
| syncthing | `linuxserver/syncthing:1.29.7` | `127.0.0.1:8384` + tailnet (`host` net) | Continuous file synchronization |
| glances | `nicolargo/glances:latest` | `100.94.209.99:61208` (`host` net) | Telemetry monitoring agent |
| dockerproxy | `tecnativa/docker-socket-proxy:latest` | `127.0.0.1:2375` + `100.94.209.99:2375` | Secure Docker socket gateway |
| watchtower | `containrrr/watchtower:latest` | `8080` (internal) | Automated container updates |
| autoheal | `willfarrell/autoheal:latest` | — | Automatic container restart monitor |

> **Correction (2026-10-13):** the `syncthing` row previously claimed `0.0.0.0:8384`. Verified live:
> the container runs `network_mode: host` and binds **`127.0.0.1:8384`** plus the **Tailscale IP**
> (`100.94.209.99%tailscale0:8384`) — never `0.0.0.0` (see [`services/syncthing.md`](../services/syncthing.md)
> and [`network/ports.md`](../network/ports.md) §2.5). The `glances` and `dockerproxy` rows also
> carried no bind: both are host-net and bind loopback + the Tailscale IP.

## Storage Architecture & HDD Remediation

- **Primary Media NFS Mount:** Audio libraries mount over NFSv4 from psicopompo (`/mnt/nas/media/music`). Local playback and Lidarr tagging do not depend on the failing local HDD.
- **Secondary Storage (`/dev/sdb1`):** Formatted with an MBR partition starting at sector 2048, bypassing physical sector errors at LBAs 8, 32, and 34–39. Mounts with options `nofail,errors=continue`.
- **Automated Backups:** Daily rsync passes export Miracena databases and compose definitions to NAS storage at 05:35.

## Network Hardware Remediation (Realtek RTL810xE, 2026-10-04)

- Configured `pcie_aspm=off` in GRUB parameters to eliminate ASPM power state conflicts on older Haswell Dell motherboards.
- Performed cold hardware power drain to reset auxiliary PHY controller power.
- Link verified at stable **100 Mb/s Full Duplex** on `192.168.3.200/24`. LAN latency dropped from ~22 ms (Wi-Fi) to 0.28 ms.
- **EEE disabled (2026-10-10):** Energy-Efficient Ethernet was `enabled - inactive`; now forced `off` by `hl-nic-power-tuning.service` (systemd oneshot, `ethtool --set-eee enp7s0 eee off`, runs at boot) — removing the last NIC power-saving state as a possible source of intermittent link stalls. Context: [`network/topology.md`](../network/topology.md#lan-stability--nic--switch-investigation-2026-10-10).

### Tailscale DNS health — HB-013 (2026-10-12, persistence confirmed 2026-10-13)

Tailscale reported `resolvconf … Failed to resolve interface "tailscale": No such device`. Root cause: **`systemd-resolved` was installed but disabled**, so at boot `tailscaled` fell back to the broken `resolvconf` path (log: `dns: [rc=resolvconf resolvconf=openresolv ret=openresolv]`). **Fix (durable):** `systemctl enable --now systemd-resolved` + `/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf` (stub listener active) + restart `tailscaled`. The host now runs in **`systemd-resolved`** mode (`resolv.conf mode: stub`, `nameserver 127.0.0.53`), so the DNS manager is re-detected correctly on every boot. `ybytu` was brought onto the **same** stub topology on 2026-10-13 (its AdGuard no longer holds `0.0.0.0:53`) — see [`ybytu.md`](ybytu.md). Detected by `homelab_tailscale_health` (see [`../network/observability.md`](../network/observability.md)).

## See Also

- [`services/miracena-stack.md`](../services/miracena-stack.md) — Client stack architecture
- [`network/nfs.md`](../network/nfs.md) — NFS remote storage mounts
- [`services/syncthing.md`](../services/syncthing.md) — Syncthing peer configuration
