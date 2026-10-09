---
tags: [homelab, service, valheim, tutorial]
---

# Valheim — Player Onboarding Guide

Connection and configuration guide for joining the **Mnemocine Vikings** dedicated Valheim server hosted on kavure.

> Tailnet access only — players outside the mesh require Tailscale configuration to reach the host IP.

## Connection Parameters

| Parameter | Configuration |
|---|---|
| Server Name | `Mnemocine Vikings` |
| Tailnet IP | `100.124.146.77` |
| Port | `2456` (UDP) |
| Server Credentials | Centrally stored in SOPS secret store (`VALHEIM_SERVER_PASS`) |
| World Identifier | `Fimbulvetr` |
| Game Version | **1.0.17** (Deep North) — automatic daily maintenance at 03:00 BRT |

## How to Join

1. Ensure your client node is authenticated on the Tailscale tailnet (`chimaera-heptatonic.ts.net`).
2. Launch Valheim → Select **Join Game**.
3. Add dedicated server manually:
   - Target Host: `100.124.146.77`
   - Port: `2456`
4. Connect and enter the server password (`VALHEIM_SERVER_PASS` from secrets vault).

> The server operates in private mode (`public=false`), remaining invisible on public Steam community lists. Connect directly via the private Tailnet IP.

## Mod Configuration

The server runs BepInEx with server-side QoL mods. Connecting with a vanilla game client works cleanly without mandatory local mods.

### Optional Client-Side QoL Mods

| Mod | Feature | Intended Users |
|---|---|---|
| Gizmo (ComfyMods) | Advanced construction rotation (Ctrl+Scroll) | All players |
| CameraTweaks (Searica) | Configurable camera FOV and zoom distances | All players |
| Server Devcommands (JereKuusela) | Enables remote admin devcommands (`god`, `fly`, `spawn`) | **Admins only** |

Installation: Managed locally through Thunderstore Mod Manager or r2modman.

### Enabling the Game Console (F5)

The developer console is disabled by default in client builds. Enable it once locally:
- **Settings → Gameplay → Enable Console**, or
- Add the launch argument `-console` in Steam game properties.
- Press **F5** in-game to toggle the console interface.

## Remote Server Management via Mobile

To initiate a server reboot remotely:
1. Connect mobile device to **Tailscale**.
2. Open SSH terminal: `tailscale ssh kavure@kavure`
3. Execute: `valheim-restart`
*(The container triggers `AUTO_BACKUP_ON_SHUTDOWN=1`, safely writing game state before restart).*

## Automated Maintenance Windows

| Schedule | Automated Process |
|---|---|
| 03:00 BRT | Watchtower checks and pulls image updates via steamcmd |
| 05:00 BRT | Daily restart cycle (`hl-valheim-restart.timer`) |
| 05:30 BRT | Off-box backup sync to NAS (`hl-valheim-backup.timer`) |
| Every 30 min | Container-internal world state backup |

## Server Administrators

| Player Name | In-Game Persona | SteamID64 |
|---|---|---|
| Carlos (Owner) | AhNo CaM | `76561198075365006` |
| Titi / Twister / Lira | Lira | `76561198009545651` |
| Henrique | BiM | `76561197988953037` |

> Permissions bind to the **Steam Account ID**, carrying over across all characters created under that account.

## See Also
- [`valheim-server.md`](valheim-server.md) — Dedicated server container architecture
- [`ssh-runbook.md`](ssh-runbook.md) — Operational SSH runbook
- [`../../servers/kavure.md`](../../servers/kavure.md) — Hosting server node profile
