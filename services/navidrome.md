---
tags: [homelab, service, navidrome, media]
---

# Navidrome

Music streaming — Subsonic-API compatible server.

**Server:** kavure (migrated 09/08/2026)
**Port:** `4533`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:4533`

## Stack

| Container | Image | Role |
|---|---|---|
| navidrome | deluan/navidrome:latest | Music streaming |

## Access

`http://kavure.chimaera-heptatonic.ts.net:4533`

## Compatible Clients

- **Ultrasonic** (Android)
- **SonicWeb** (browser)
- **Substreamer** (iOS)
- **Tauon Music Box** (Linux) — integration with `localhost:7813`

## Integration

Music managed by **Lidarr**, which downloads and organizes the tracks automatically. Navidrome reads the music library and serves it to the clients.

## Data

Music library mounted as a Docker volume on kuaray's disks.
