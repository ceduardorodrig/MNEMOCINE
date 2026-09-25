---
tags: [homelab, service, zomboid-panel, gaming]
---

# Zomboid Control Panel

Web admin panel for the **Project Zomboid** server — Zomboid's "Crafty".

**Project:** [fpsacha/zomboid-control-panel](https://github.com/fpsacha/zomboid-control-panel) (MIT, active, tested up to B42.18)
**Version:** v1.1.36 (updated 07/08/2026 — image `ghcr.io/fpsacha/zomboid-panel:latest`; watchtower also updates it at 03:00)
**Server:** kavure (active since 06/08/2026)
**Access:** via Tailscale

## Features

- **Server control** — start/stop/restart/save, status, uptime
- **Console + RCON** — terminal with history (no more SSH/sudo to administer)
- **Mod manager** — detects Workshop updates, resolves `Mods=`/`WorkshopItems=` automatically
- **Backups** with restore from the UI
- **Scheduler** — restarts/saves/broadcast (replaces systemd timers)
- Extras: live world map, Discord bot, INI editor, events/weather

## Requirements

- PZ server with **RCON enabled**: `RCONPort=27015` + `RCONPassword=...` in `pzserver.ini`
- Network access from the panel to the server (same machine, LAN or Tailscale)
- For PanelBridge (advanced features): `DoLuaChecksum=false` in the server `.ini`

## Installation (kavure)

Options: **Docker** (`ghcr.io/fpsacha/zomboid-panel:latest`) or Linux binary (`./start.sh`).

```bash
mkdir -p ~/zomboid-panel && cd ~/zomboid-panel
curl -O https://raw.githubusercontent.com/fpsacha/zomboid-control-panel/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/fpsacha/zomboid-control-panel/main/.env.example
mv .env.example .env
docker compose up -d
```

- Browse to `http://localhost:3001` (or via Tailscale)
- Configure: PZ server path, data, RCON (host/port/password)
- In Docker, use the `PUID`/`PGID` of the PZ folder owners

## Security

- JWT on all routes + rate limiting
- Do not expose port 3001 directly to the internet — use Tailscale or a reverse proxy with HTTPS

## Mods and Workshop path

- The panel reads the mods at `/pz-server/steamapps/workshop` — the panel's compose bind-mounts `/srv/data/zomboid/workshop-mods` at that path (same overlay as the game container).
- The old copy at `pz-dedicated/steamapps/workshop/` was **removed** (07/08/2026) — it caused a permanent "Mod update available" (stale local copy vs Steam).
- The Mod manager compares the local `timeUpdated` (from the folder) with the Steam API. If "update available" appears, restart the game (`zomboid-restart`) to download the update; the panel's auto-scan (5 min) then shows everything up to date.

## PanelBridge

- Server-side Lua mod that gives the panel actions outside RCON (teleport, heal, weather, inventory...). Lives in `pz-dedicated/media/lua/server/PanelBridge.lua`.
- **Fix 07/08/2026:** the `media/lua/server/` folder was `root:root` → the panel (uid 1000) could not **auto-update** the bridge (EACCES). `sudo chown -R kavure:kavure /srv/data/zomboid/pz-dedicated/media/lua/server` fixed it — auto-update `1.7.21 → 1.7.23 → 1.7.24` confirmed in the panel log (after updating the panel to v1.1.36).

## See also
- [[project-zomboid]] — Project Zomboid server
- [[kavure]] — Target server
- [[kavure-migration-plan]] — Migration plan
