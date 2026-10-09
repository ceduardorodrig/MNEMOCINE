---
tags: [homelab, server, ybyra, docker, monitoring, tailscale]
---

# ybyra

**Role:** Cloud edge gateway (Oracle Cloud Infrastructure Always Free) — Sumænimá primary public ingress, reverse proxy, and analytics  
**Default Shell:** bash (`/bin/bash`)  
**Swarm Role:** `primary` — Docker Swarm worker node executing the `sae-edge` stack  

## Hardware Specifications

| Component | Specification |
|---|---|
| **OS** | Ubuntu 24.04 LTS (KVM virtualized instance) |
| **Kernel** | 6.17.0-1020-oracle |
| **CPU** | AMD EPYC 7551 (2 vCPUs — Oracle free tier shape `VM.Standard.E2.1.Micro`) |
| **RAM** | 954 MB |
| **Boot Volume** | **50 GB** — Re-provisioned 2026-10-08 (downsized from 150 GB to release block storage for ARM capture) |
| **Swap** | 4 GB |
| **Tailscale IP** | 100.66.224.34 |
| **Tailscale DNS** | ybyra.chimaera-heptatonic.ts.net |
| **Network Interface** | Virtual network (`ens3`: 10.0.0.40/24) |

## Core Operational Responsibilities

- **Primary Edge Ingress:** Terminating external public traffic via Tailscale Funnel.
- **Frontend SPA Hosting:** Serving the static production build of the Sumænimá web application (`/var/www/sumaenima`).
- **Reverse Proxy Routing:** Nginx reverse proxy multiplexing frontend routes, backend APIs, and web analytics.

## Public Ingress & Tailscale Funnels

| Public URL | Internal Target | Status |
|---|---|---|
| `https://sumaenima.chimaera-heptatonic.ts.net` | `http://proxy:80` | Active — Ingress for primary web application |

## Docker Swarm Services (`sae-edge` Stack — Managed by kavure)

| Service | Image | Ports | Responsibility |
|---|---|---|---|
| proxy | `nginx-sumaenima:latest` | `0.0.0.0:80` | Reverse proxy (SPA frontend, API gateway, Umami analytics) |
| tunnel | `tailscale/tailscale:latest` | — | Tailscale Funnel ingress gateway |
| umami | `sumaenima-umami:latest` | 3000 | Privacy-preserving web analytics platform |

### Traffic Routing Architecture

All inbound requests arrive through the Tailscale Funnel container and route to Nginx:
- `/` $\rightarrow$ Static React/Vite SPA hosted locally on disk (`/var/www/sumaenima`);
- `/api/` $\rightarrow$ Fast-forwarded over Swarm overlay network (`sae-net`) to `sae-core_api` on kavure;
- `/umami/` $\rightarrow$ Local container route to Umami analytics daemon.

## Standalone Infrastructure Containers

| Container | Image | Ports | Responsibility |
|---|---|---|---|
| glances | `nicolargo/glances:latest` | `0.0.0.0:61208` | Host telemetry monitoring |
| autoheal | `willfarrell/autoheal:latest` | — | Restarts unhealthy containers automatically |
| watchtower | `containrrr/watchtower:latest` | — | Automated container image updater |

## Re-provisioning Post-Mortem (150 GB $\rightarrow$ 50 GB Reduction, 2026-10-08)

To release block storage quota for the Always Free ARM instance (`ybytyra`), ybyra was gracefully rebuilt:
1. Active edge traffic failed over to standby replicas on kavure (`sae-edge_proxy-standby`);
2. Legacy 150 GB instance terminated via OCI CLI;
3. Replacement instance launched with fixed 50 GB boot disk and static private IP `10.0.0.40`;
4. Tailscale identity restored from backup, retaining IP `100.66.224.34`;
5. Node rejoined Swarm as worker (`role=primary`), and edge traffic failed back with zero data loss.

## See Also

- [`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md) — Step-by-step reduction runbook
- [`services/sumaenima-edge.md`](../services/sumaenima-edge.md) — Edge architecture and reverse proxy setup
- [`network/topology.md`](../network/topology.md) — Global mesh network topology
