---
tags: [homelab, service, navidrome, media]
---

# Navidrome

Personal audio streaming server compatible with the Subsonic API standard.

**Host Node:** kavure (migrated 2026-08-09)  
**Port:** `4533`  
**Web Console:** `http://kavure.chimaera-heptatonic.ts.net:4533`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `navidrome` | `deluan/navidrome:latest` | Subsonic-compatible audio streaming engine |

## Access

```text
http://kavure.chimaera-heptatonic.ts.net:4533
```

## Compatible Client Applications

- **Ultrasonic** (Android)
- **SonicWeb** (Web browser interface)
- **Substreamer** (iOS)
- **Tauon Music Box** (Linux desktop client)

## Infrastructure Integration

Audio collections are managed upstream by **Lidarr**, which downloads and organizes incoming tracks into structured album folders. Navidrome indexes the shared library directory and serves audio streams directly to connected client endpoints.

## Storage Backend

The music library is mounted into the container from remote NAS shares hosted on psicopompo over NFS (`/srv/data/navidrome/music`).
