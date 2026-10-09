---
tags: [homelab, service, prowlarr, download]
---

# Prowlarr

Unified BitTorrent and Usenet indexer manager for the media automation pipeline.

**Host Node:** kuaray  
**Port:** `9696`  
**Web Console:** `http://kuaray.chimaera-heptatonic.ts.net:9696`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `prowlarr` | `linuxserver/prowlarr:latest` | Centralized indexer proxy and integration manager |

## Integration

Supplies and syncs search indexers to:
- **Lidarr** (music acquisition)
- Additional media daemons as needed

## Operational Workflow

1. Centralizes configuration across multiple torrent and Usenet indexers.
2. Automatically propagates indexer credentials and health status to connected automation applications.
3. Routes challenges through Flaresolverr when accessing sites protected by Cloudflare bot-management.

## Secrets Management

- **API Key:** Managed inside SOPS secret store (`PROWLARR_API_KEY`). The local `config.xml` is excluded from raw Git mirrors.
