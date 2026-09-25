---
tags: [homelab, service, zomboid, tutorial]
---

# Zomboid — Onboarding (Players)

Guide for joining the **VaiMorreSim** Project Zomboid server (kavure).

> Access only over the tailnet (**whitelist only**) — anyone not on Tailscale uses the in-game browser (the server is public in the list).

## Connection details

| Item | Value |
|---|---|
| Server name | `VaiMorreSim` |
| IP (Tailscale) | `100.124.146.77` |
| Port | `16261` (UDP) |
| **Password** | `TuVaiMorre` |
| Max players | 15 |
| Build | B42 (**stable**) |
| Mods | ~65 Workshop |

## How to join

**Option A — in-game browser (no Tailscale needed):**
1. Game → **Join** → look for `VaiMorreSim` in the server list (it is public).
2. Connect → type the password `TuVaiMorre`.

**Option B — direct (Tailscale):**
1. Accept the `kavure` host on your tailnet (if you haven't already).
2. Game → **Join** → **Enter IP** → `100.124.146.77` (port 16261) → connect.
3. Password `TuVaiMorre`.

> If the game asks you to download Workshop mods when connecting, accept — the server sends the list automatically on the first join.

> **Maintenance notices:** before restarts/shutdowns, a **yellow banner at the top of the screen** (`[SERVER] ...`) warns ~20s in advance — the server is down for ~1 min to save and update the mods. Automatic restarts: 05:00, 11:00, 17:00 and 23:00 (they are skipped if there are players online).

## Remote restart from your phone (mod update)

If you need to restart while away (e.g. a mod was updated on Workshop and you want to pull it now), use the **panel** from your phone's browser:

1. Phone connected to **Tailscale** (MagicDNS) — `http://kavure.chimaera-heptatonic.ts.net:3001`.
2. Log into the **Zomboid Control Panel** (panel admin account).
3. **Console** tab → type `save` → Enter (saves the world).
4. ~5s later → type `quit` → Enter.
5. The game saves and exits → **Docker restarts the container by itself** (`restart: unless-stopped`) → on boot the server re-downloads/updates the Workshop mods (~1-2 min down).

> Validated on 07/08/2026. Alternative over SSH (Termius/Termux + Tailscale): `tailscale ssh kavure@kavure` → `zomboid-restart` (1 command, does save + restart).

## Mods

- Full list (WorkshopItems/Mods) managed by the **Zomboid Control Panel** (Mods tab) — see [`zomboid-control-panel`](zomboid-control-panel.md).
- Technical reference in [`project-zomboid`](project-zomboid.md) (`Mods=`/`WorkshopItems=` in `pzserver.ini`).
- Mod updates: automatic on the **4x/day** restart (05:00, 11:00, 17:00, 23:00 — the server downloads Workshop updates on boot).

## Admin (owner)

- **Web panel:** `http://kavure.chimaera-heptatonic.ts.net:3001` — RCON, players, map, mods, backup, events.
- **SSH/scripts:** [`ssh-runbook`](ssh-runbook.md) — start/stop/restart/update/backup.
- **Admin players:** accounts and permissions come from the migrated `players.db` (unchanged).

## See also
- [[project-zomboid]] — Project Zomboid server (Docker)
- [[ssh-runbook]] — Operation via SSH
- [[zomboid-control-panel]] — Web panel
