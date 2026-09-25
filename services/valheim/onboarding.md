---
tags: [homelab, service, valheim, tutorial]
---

# Valheim — Onboarding (Players)

Guide for joining the **Mnemocine Vikings** Valheim server (kavure).

> Access only over the tailnet — anyone not on Tailscale needs manual access via IP.

## Connection details

| Item | Value |
|---|---|
| Server name | `Mnemocine Vikings` |
| IP (Tailscale) | `100.124.146.77` |
| Port | `2456` (UDP) |
| **Password** | `HalVeim1235` |
| World | `Fimbulvetr` |
| Version | 1.0.12 (Deep North) |

## How to join

1. Accept the `kavure` host on your tailnet (if you haven't already).
2. Open Valheim → **Join Game**.
3. Add the server manually:
   - IP: `100.124.146.77`
   - Port: `2456`
4. Connect → type the password `HalVeim1235`.

> The server is **private** (`public=false`) — it does not appear in the server list. Only reachable via direct IP on the tailnet.

## Mods

The client downloads the mods automatically when connecting (BepInEx + 4 QoL mods). If the game asks you to install them, accept — the server sends the list.

### Installed mods (4)

| Mod | Role |
|---|---|
| Gizmo | Building rotation (Ctrl+scroll) |
| FuelEternal | Fire never goes out |
| CameraTweaks | Customizable zoom and FOV |
| SmoothServer | Network performance (Compression disabled, map not shared) |

### Admin commands (F5)

Valheim 1.0 has native commands via the console:

1. Press **F5** to open the console.
2. Type `devcommands` → Enter (enables developer mode).
3. Useful commands:
   - `god` — invincibility mode
   - `fly` — free flight
   - `pos` — shows coordinates
   - `freefly` — free camera
   - `event` — random events
   - `stopevent` — stops the current event

> ⚠️ Commands are **local** — they only affect whoever typed them. There is no remote admin via RCON like in Zomboid.

## Remote restart from your phone

If you need to restart while away:

1. Phone connected to **Tailscale** (MagicDNS).
2. SSH: `tailscale ssh kavure@kavure`
3. Run: `valheim-restart`

> The server saves automatically before the restart via `AUTO_BACKUP_ON_SHUTDOWN=1`.

## Automatic maintenance

| Time | What happens |
|---|---|
| 03:00 | Watchtower updates the image (steamcmd) |
| 05:00 | Daily restart (timer `hl-valheim-restart`) |
| 05:30 | Off-box backup (timer `hl-valheim-backup`) |
| Every 30 min | Automatic container backup |

## Admin (owner)

- **SSH:** [`ssh-runbook`](ssh-runbook.md) — start/stop/restart/backup
- **Console:** `devcommands` in the game (F5)

## See also

- [[valheim-server]] — Valheim server (Docker)
- [[ssh-runbook]] — Operation via SSH
- [[kavure]] — Target server
