---
tags: [homelab, service, flaresolverr, download]
---

# Flaresolverr

Proxy service for bypassing Cloudflare and DDoS-Guard bot verification challenges on automated indexer scrapers.

**Host Node:** kuaray  
**Port:** `8191`  
**Internal Endpoint:** `http://kuaray.chimaera-heptatonic.ts.net:8191`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `flaresolverr` | `flaresolverr/flaresolverr:latest` | Headless browser Cloudflare solver proxy |

## Integration

Utilized by **Prowlarr** to fetch search results from torrent indexers protected by Cloudflare bot management.

## Operational Workflow

1. Prowlarr sends incoming HTTP requests to Flaresolverr.
2. Flaresolverr spawns a headless browser session to solve the JavaScript verification challenge.
3. Returns resolved session cookies and HTML payloads back to Prowlarr.
