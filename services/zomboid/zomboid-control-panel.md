---
tags: [homelab, service, zomboid-panel, gaming]
---

# Zomboid Control Panel

Web administration interface for the **Project Zomboid** dedicated server.

**Project Repository:** [fpsacha/zomboid-control-panel](https://github.com/fpsacha/zomboid-control-panel) (MIT License, actively maintained for Build 42)  
**Image Version:** `ghcr.io/fpsacha/zomboid-panel:latest` (Auto-updated daily via Watchtower at 03:00 BRT)  
**Host Node:** kavure  
**Access Channel:** Tailscale mesh exclusive  

## Core Capabilities

- **Server Telemetry** — Displays real-time uptime, connected players, and memory consumption.
- **Console & Source RCON** — Interactive terminal emulator with command history.
- **Workshop Mod Manager** — Automated discovery of pending Steam Workshop updates, mapping `Mods=` and `WorkshopItems=` entries.
- **Backup Management** — Generates local world archives with web-based point-in-time restore actions.
- **In-Game World Features** — Live interactive map tracking, weather manipulation, and automated announcement schedules.

## Prerequisites & Environment Integration

- Dedicated Project Zomboid instance with **RCON enabled**: `RCONPort=27015` and matching `RCONPassword` configured in `pzserver.ini`.
- Network connectivity between the panel container and the game daemon container over the Docker bridge network.
- Advanced administrative commands require the **PanelBridge** Lua mod (`DoLuaChecksum=false` in `pzserver.ini`).

## Deployment on kavure

Deployed via Docker Compose within the kavure gaming stack:

```yaml
services:
  zomboid-panel:
    image: ghcr.io/fpsacha/zomboid-panel:latest
    container_name: zomboid-panel
    restart: unless-stopped
    ports:
      - "100.124.146.77:3001:3001"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /srv/data/zomboid/data:/pz-server/Zomboid
      - /srv/data/zomboid/workshop-mods:/pz-server/steamapps/workshop
      - /srv/data/zomboid/pz-dedicated:/pz-dedicated
```

- Accessible via `http://100.124.146.77:3001` or `http://kavure.chimaera-heptatonic.ts.net:3001`.
- Bound exclusively to Tailscale to prevent unauthenticated public exposure.

## Workshop Path Architecture

- The control panel inspects installed mods via `/pz-server/steamapps/workshop`, mapped directly to `/srv/data/zomboid/workshop-mods/` on the host.
- The manager checks local directory timestamps against the Steam Workshop API. When pending updates are detected, triggering a server restart via `zomboid-restart` pulls down new assets.

## PanelBridge Lua Extension

- Server-side Lua extension providing administrative capabilities beyond standard RCON boundaries (teleportation, healing, dynamic item spawning).
- Installed in `/srv/data/zomboid/pz-dedicated/media/lua/server/PanelBridge.lua`.
- File ownership is maintained under `kavure:kavure` (UID 1000) to allow the panel process to automatically upgrade the bridge component as new releases are published.

## See Also
- [`project-zomboid.md`](project-zomboid.md) — Dedicated server specification
- [`ssh-runbook.md`](ssh-runbook.md) — SSH maintenance scripts
- [`../../servers/kavure.md`](../../servers/kavure.md) — Kavure node specification
