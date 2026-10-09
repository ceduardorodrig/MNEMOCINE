---
tags: [homelab, server, ybytu, dns, monitoring, changedetection, ntfy]
---

# ybytu

> OS hostname: `ybytu-vnic` (displayed in Tailscale as `ybytu`)

**Role:** Cloud utility server (Oracle Cloud Infrastructure Always Free) — DNS, dashboard portal, notification gateway, and monitoring  
**Default Shell:** bash (`/bin/bash`)  

## Hardware Specifications

| Component | Specification |
|---|---|
| **OS** | Ubuntu 24.04 LTS |
| **Kernel** | 7.0.0-1012-oracle |
| **CPU** | AMD EPYC 7551 (2 vCPUs — Oracle free tier shape `VM.Standard.E2.1.Micro`) |
| **RAM** | 954 MB (ZRAM: 477 MB) |
| **Disk Storage** | 50 GB virtual block volume |
| **Tailscale IP** | 100.115.253.109 |
| **Tailscale DNS** | ybytu.chimaera-heptatonic.ts.net |
| **Network Interface** | Virtual network (`ens3`: 10.0.0.136/24, MTU 9000) |

## Core Operational Responsibilities

- **Tailnet Exit Node:** Configured exit node providing egress routing for mobile and remote devices.
- **Network-Wide Ad-Blocking DNS:** AdGuard Home container answering DNS requests across the mesh.
- **Central Portal Dashboard:** Homepage dashboard rendering homelab services and live container states.
- **Uptime Monitoring:** Uptime Kuma executing external HTTP and port probes.
- **Change Detection:** Changedetection.io monitoring upstream software repositories and document releases.
- **Push Notification Gateway:** Self-hosted ntfy instance receiving systemd and backup failure webhooks.

## Docker Workloads (Standalone Containers)

All workloads execute as Docker containers managed via Docker Compose:

| Container | Image | Ports | Responsibility |
|---|---|---|---|
| adguardhome | `adguard/adguardhome:latest` | `0.0.0.0:53`, `0.0.0.0:3000` | DNS server & admin panel |
| homepage | `ghcr.io/gethomepage/homepage:latest` | `0.0.0.0:3001` | Homelab portal interface |
| glances | `nicolargo/glances:latest` | `0.0.0.0:61208` | Node telemetry metrics |
| dockerproxy | `tecnativa/docker-socket-proxy:latest` | `127.0.0.1:2375` | Secure socket gateway for Homepage |
| uptime-kuma | `louislam/uptime-kuma:latest` | `0.0.0.0:3002` | Service availability monitor |
| changedetection | `dgtlmoon/changedetection.io:latest` | `0.0.0.0:8082` | Web page alteration alerts |
| ntfy | `binwiederhier/ntfy:latest` | `0.0.0.0:8083` | Push notification service |
| watchtower | `containrrr/watchtower:latest` | — | Automated container image updater |
| autoheal | `willfarrell/autoheal:latest` | — | Restarts unhealthy containers automatically |

## DNS Architecture & Upstream Resolution

- **Primary Upstream:** `tcp://100.124.146.77:5053` (Native recursive `unbound` resolver on kavure, queried over Tailscale).
  - *Note on TCP Transport:* AdGuard Home uses TCP to avoid known UDP packet drop bugs ([AdguardTeam/AdGuardHome#7628](https://github.com/AdguardTeam/AdGuardHome/issues/7628)).
- **Encrypted Fallback:** `tls://9.9.9.9` and `tls://1.1.1.1` (DNS-over-TLS). If kavure becomes temporarily unreachable, AdGuard seamlessly falls back to encrypted public resolvers with zero service interruption.
- **Log Retention Policy:** `querylog.interval` is bounded to 7 days with memory buffer set to 200 queries, preventing memory exhaustion on this 1 GB instance.

## Backup & Storage Mounts

- **NFS Mounts:** Configuration backups export to NAS mirror on psicopompo using soft mounts (`soft,timeo=30,retrans=2` with `nofail`).
- **Local Config Mirroring:** `config-backup` runs daily at 05:00, pushing compose stacks and AdGuard configurations to NAS and Git.

## See Also

- [`services/adguard-home.md`](../services/adguard-home.md) — AdGuard Home configuration and filter rules
- [`services/homepage.md`](../services/homepage.md) — Homelab application portal configuration
- [`guides/oracle-oci-cli.md`](../guides/oracle-oci-cli.md) — OCI CLI remote instance management
