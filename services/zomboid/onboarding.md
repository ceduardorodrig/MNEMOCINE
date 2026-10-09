---
tags: [homelab, service, zomboid, tutorial]
---

# Project Zomboid — Player Onboarding Guide

Connection and onboarding guide for the **VaiMorreSim** dedicated Project Zomboid server hosted on kavure.

> Tailnet whitelist access enabled — players outside the mesh join directly via the in-game public browser.

## Connection Parameters

| Parameter | Configuration |
|---|---|
| Server Name | `VaiMorreSim` |
| Tailnet IP | `100.124.146.77` |
| Port | `16261` (UDP) |
| Password | Stored in SOPS vault (`ZOMBOID_ADMINPASSWORD`) |
| Max Players | 15 |
| Game Branch | Build 42 (**public / stable**) |
| Active Mods | ~65 Steam Workshop items |

## Joining the Server

**Option A — In-Game Browser (No Tailscale Required):**
1. Launch Project Zomboid → Select **Join**.
2. Search for `VaiMorreSim` in the public community server list.
3. Connect and enter the server password (`ZOMBOID_ADMINPASSWORD` in SOPS).

**Option B — Direct Tailscale Connection:**
1. Ensure your client node is authenticated on the Tailscale mesh.
2. Select **Join** → **Enter IP** → `100.124.146.77` (Port 16261).
3. Connect and supply credentials.

> When connecting for the first time, accept the prompt to download Workshop mods — the server automatically synchronizes required assets during initial handshake.

> **Maintenance Notices:** Prior to scheduled maintenance restarts, a **yellow broadcast banner** appears across the top of the display (`[SERVER] ...`) with ~20 seconds advance notice. The server takes ~1 minute to flush saves and apply Workshop mod updates. Automated restarts occur at 05:00, 11:00, 17:00, and 23:00 BRT (automatically deferred if players are active).

## Mobile Remote Management (Mod Updates & Restarts)

To trigger a remote save and restart from a mobile device:
1. Ensure mobile phone is connected to **Tailscale** → navigate to `http://kavure.chimaera-heptatonic.ts.net:3001`.
2. Authenticate to **Zomboid Control Panel**.
3. Under the **Console** tab, issue `save` to flush active world state to disk.
4. Issue `quit` ~5 seconds later.
5. The container terminates cleanly and Docker restarts it automatically (`restart: unless-stopped`), checking for Steam Workshop updates upon boot.

*(Alternative via mobile SSH terminal: `tailscale ssh kavure@kavure` → `zomboid-restart`).*

## Workshop Mods & Collections

- Active mod definitions are cataloged in **Zomboid Control Panel** (Mods tab) — see [`zomboid-control-panel.md`](zomboid-control-panel.md).
- Automated updates trigger during restart cycles 4 times daily (05:00, 11:00, 17:00, 23:00 BRT).

## Administrator Access

- **Web Dashboard:** `http://kavure.chimaera-heptatonic.ts.net:3001` (RCON terminal, live map, player tracking, backups, event scheduler).
- **SSH Automation:** [`ssh-runbook.md`](ssh-runbook.md) (lifecycle CLI scripts).
- **Admin Roles:** Permissions persist inside `players.db`.

## See Also
- [`project-zomboid.md`](project-zomboid.md) — Dedicated server container architecture
- [`ssh-runbook.md`](ssh-runbook.md) — Operational SSH runbook
- [`zomboid-control-panel.md`](zomboid-control-panel.md) — Web administration console
