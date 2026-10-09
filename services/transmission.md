---
tags: [homelab, service, transmission, download]
---

# Transmission

Lightweight headless BitTorrent client daemon.

**Host Node:** kuaray  
**Web Port:** `9091`  
**DHT Port:** `51413` (TCP/UDP)  
**Web Console:** `http://kuaray.chimaera-heptatonic.ts.net:9091`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `transmission` | `linuxserver/transmission:latest` | BitTorrent download daemon |

## Access

```text
http://kuaray.chimaera-heptatonic.ts.net:9091
```

## System Integration

- Ingests incoming torrent transfers dispatched by Lidarr via Prowlarr indexers.
- Supports direct torrent addition via web interface.
- Bandwidth-throttled to preserve local network responsiveness.

## Secrets & Authentication

- The RPC password hash is secured in SOPS (`TRANSMISSION_RPC_PASSWORD` — stores the salted hash from `settings.json`).
- `settings.json` is excluded from public config backups.
