---
tags: [homelab, service, aiostreams, media]
---

# aiostreams

Streaming proxy for media players.

**Server:** kavure
**Port:** `3000`
**Funnel:** `kavure.chimaera-heptatonic.ts.net:10000`
**Internal URL:** `http://localhost:3000`
**Public URL:** `https://kavure.chimaera-heptatonic.ts.net:10000`

## Stack

| Container | Image | Role |
|---|---|---|
| aiostreams | viren070/aiostreams:latest | Streaming proxy |

## Access

- **Tailscale:** `http://kavure.chimaera-heptatonic.ts.net:3000`
- **Public:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Funnel)

## How it works

Proxy that receives requests from players (e.g. Stremio) and returns resolved streams via third-party services.
