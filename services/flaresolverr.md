---
tags: [homelab, service, flaresolverr, download]
---

# Flaresolverr

Proxy that solves Cloudflare challenges for scrapers and indexers.

**Server:** kuaray
**Port:** `8191`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:8191`

## Stack

| Container | Image | Role |
|---|---|---|
| flaresolverr | flaresolverr/flaresolverr:latest | Cloudflare proxy |

## Integration

Used by **Prowlarr** to reach torrent indexers that sit behind Cloudflare protection.

## How it works

1. Prowlarr sends a request via Flaresolverr
2. Flaresolverr solves the JavaScript/Cloudflare challenge
3. Returns the resolved content to Prowlarr
