---
tags: [homelab, service, valheim, gaming]
---

# Valheim — Dedicated Server

Dedicated Valheim 1.0 (Deep North) server with BepInEx and QoL mods.

**Server:** kavure
**Ports:** UDP 2456-2458
**Password:** `HalVeim1235`
**World:** `Fimbulvetr`
**IP (Tailscale):** `100.124.146.77`

> **Active since 09/09/2026:** Valheim 1.0.12 (network version 40) via `mbround18/valheim:3` with BepInEx + 3 server-side mods. Server public=false (access via the tailnet). Automatic backup every 30min via container + offbox NFS. Portals in casual mode (ores pass through).

## Stack

| Container | Image | Role |
|---|---|---|
| valheim-server | mbround18/valheim:3 | Dedicated server + BepInEx + mods |

## Ports

| Port | Protocol | Use |
|---|---|---|
| 2456 | UDP | Game (primary) |
| 2457 | UDP | Game (backup) |
| 2458 | UDP | Game (backup) |

## Data

| Item | Value |
|---|---|
| World | `Fimbulvetr` |
| Server | `Mnemocine Vikings` |
| Password | `HalVeim1235` |
| Public | `false` (access only via tailnet) |
| BepInEx | Yes (`TYPE: BepInEx`) |
| Modifiers | `portals=casual` |
| Auto-update | 03:00 daily (steamcmd) |
| Auto-backup | Every 30 min → offbox NFS |
| TZ | America/Sao_Paulo |

## World Modifiers

| Modifier | Value | Effect |
|---|---|---|
| portals | `casual` | Ores/minerals pass through portals |

## Disabled SmoothServer Modules

| Module | Config | Reason |
|---|---|---|
| `[Compression] Enabled` | `false` | Incompatible with Valheim 1.0.12 (frame tag `0x48`, empty world). Fixed on 12/09/2026. |
| `[Map] Enabled` | `false` | Map sharing disabled on request (20/09/2026). Each player only sees what they explored + local pins. |

> Both persist across restarts because `Profile = Custom` is active (no automatic overwrite of defaults).

## Mods (3 active — server-side)

| Mod | Version | Role |
|---|---|---|
| Server_devcommands | 1.113 | Devcommands + admin tools |
| SmoothServer | 0.6.0 | Network performance |
| FuelEternal | 1.2.1 | Fire never goes out |

**All mods are server-side** — vanilla clients connect without problems.

### Client-side mods (install on the client, not the server)

| Mod | Version | Role |
|---|---|---|
| Gizmo (ComfyMods) | 1.16.0 | Building rotation (Ctrl+scroll) |
| CameraTweaks (Searica) | 1.3.1 | Customizable zoom and FOV |

### Mods removed from the server

| Mod | Reason |
|---|---|
| Gizmo (ComfyMods) | Client-side only — removed from the server on 16/09/2026; each player installs it on the client |
| CameraTweaks (Searica) | Client-side only — removed from the server on 16/09/2026; each player installs it on the client |
| BuildCamera (Azumatt) | Kicked vanilla clients (`EnforceClientMod: true`); no demand |
| AAA_Crafting | `Inventory.AddItem` changed signature (incompatible with 1.0) |
| aruberuto/AreaRepair | Harmony patch crash in `Awake` (incompatible with 1.0) |
| Azumatt/AzuAreaRepair | Harmony patch crash in `Awake` (incompatible with 1.0) |

## Data on disk

```
/srv/data/valheim/
├── docker-compose.yml    ← compose (MODS, MODIFIERS: portals=casual)
├── .env                  ← VALHEIM_SERVER_PASS
├── config/               ← BepInEx + configurações
│   └── bepinex/          ← configs dos mods (persistidas entre restarts)
├── data/                 ← binário do servidor (volume → /home/steam/valheim)
├── saves/                ← MUNDO + auto-backups do jogo (volume → /home/steam/.config/unity3d/IronGate/Valheim)
│   └── worlds_local/     ← Fimbulvetr (mundo ativo) + Fimbulvetr_backup_auto-* (auto-backups nativos do jogo)
├── backups/              ← AUTO_BACKUP do container (Odin) → /home/steam/backups (persistido desde 13/09)
└── offbox/               ← mount NFS → psicopompo (backup off-box)
```

## Backup

> **Fixed (13/09/2026):** the off-box backup was **broken** — the `valheim-backup` script pointed at `/srv/data/valheim/config/backups/` (the default of a different image), a folder that **does not exist** in this setup. The real world lives in `saves/worlds_local/`. Script fixed (source → `saves/worlds_local/`) + added the `./backups:/home/steam/backups` mount in the compose so Odin's AUTO_BACKUP does not lose backups on recreate.

- **Off-box (primary):** the **game's native auto-backup** writes to `saves/worlds_local/Fimbulvetr_backup_auto-*` → mirrored by `valheim-backup` (rsync) to the psicopompo NFS (`/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`). Covers the active world + backups.
- **Container AUTO_BACKUP (Odin):** every 30 min → `/home/steam/backups` (`./backups`, persisted since 13/09). Retention `AUTO_BACKUP_DAYS_TO_LIVE=7`.
- **Schedule:** systemd timer `hl-valheim-backup.timer` (05:30, `Persistent=true`) → health file `/srv/health/valheim-backup-last-ok` (covered by the `BackupNotRun` alert).

## Schedules (systemd timers)

```ini
# hl-valheim-restart.timer — 05:00 diário (Persistent=true)
# hl-valheim-backup.timer  — 05:30 diário (Persistent=true)
```

- **watchtower** (container from the `ops` stack, **03:00 BRT**): updates `valheim-server` — recreates the container with stop-timeout 30s; `AUTO_BACKUP_ON_UPDATE=1` saves first.

## Access

```bash
tailscale ssh kavure@kavure
valheim-status    # status completo
```

## Troubleshooting

### SmoothServer Compression incompatible with Valheim 1.0.12 (empty world)

**Symptoms:** the world loads empty (terrain OK, no trees/buildings), `unknown frame tag 0x48` error in the logs, `zdosSent/s=0` (the server does not send ZDOs to the client).

**Root cause (final diagnosis 12/09/2026):** the `[Compression]` module of SmoothServer 0.6.0 is **incompatible with Valheim 1.0.12** (the network protocol changed, frame tag `0x48`). It is **not** a corrupted DLL — even after a clean reinstall the problem came back.

**The detail that blocked the fix before:** with `Profile = Default`, SmoothServer 0.6.0 **forces the default values back** in the config on every boot — any edit to `Compression.Enabled` was silently overwritten.

**Fix (confirmed):**
1. Edit `[Profiles] Profile = Default` → `Profile = Custom` (so the plugin does not overwrite anything)
2. Edit `[Compression] Enabled = true` → `Enabled = false`
3. Restart container

**How to edit the config (important):** edit via **`docker exec`** inside the container, with correct nested quotes. Editing via `echo senha | sudo -S sed` on the host does not persist.

```bash
ssh kavure@kavure
echo 'SENHA' | sudo -S docker exec valheim-server bash -c \
  'sed -i "281s/Profile = Default/Profile = Custom/; 90s/Enabled = true/Enabled = false/" \
  /home/steam/valheim/BepInEx/config/Nosferatu.SmoothServer.cfg'
```

> **Never** delete files from `saves/` or `worlds_local/` — they contain the world.

### Config edits via the host do not persist

The SmoothServer config file is mounted from `./config/bepinex` on the host to `/home/steam/valheim/BepInEx/config` in the container. Edits made on the host with `echo senha | sudo -S sed ...` **do not apply** (stdin/quoting issue over SSH). Always use `docker exec` in the container.

## See also

- [[onboarding]] — Guide for players
- [[ssh-runbook]] — Operation via SSH
- [[kavure]] — Target server
- [[project-zomboid]] — Zomboid server (reference pattern)
