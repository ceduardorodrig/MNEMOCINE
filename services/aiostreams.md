---
tags: [homelab, service, aiostreams, media]
---

# AioStreams

Streaming aggregation proxy for media players.

**Host Node:** kavure  
**Internal Port:** `3000`  
**Tailscale Funnel:** `kavure.chimaera-heptatonic.ts.net:10000`  
**Internal Endpoint:** `http://localhost:3000`  
**Public Endpoint:** `https://kavure.chimaera-heptatonic.ts.net:10000`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `aiostreams` | `viren070/aiostreams:latest` | Streaming aggregation proxy |

## Access & Network Bindings

- **Tailnet:** `http://kavure.chimaera-heptatonic.ts.net:3000` (`100.124.146.77:3000`)
- **Public WAN:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Tailscale Funnel)

> 📌 **Network Interface Bindings:** The container publishes listening sockets on both `100.124.146.77:3000` (Zone 1 - Tailnet) and `127.0.0.1:3000` (Zone 0 - Loopback). Loopback binding is required so the host-level Tailscale Funnel daemon can forward incoming public traffic on port `10000` without exposing unauthenticated listeners on physical LAN interfaces (`0.0.0.0`). Managed via `/home/kavure/homelab/aiostreams/compose.yml`.

## Functionality

Receives stream resolution queries from external media clients (such as Stremio) and delivers aggregated playback streams resolved across third-party debrid providers.
