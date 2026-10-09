---
tags: [homelab, service, valheim, gaming]
---

# Valheim — Dedicated Server Specification

Dedicated server deployment for Valheim 1.0 (Deep North) powered by BepInEx and server-side quality-of-life enhancements.

**Host Node:** kavure  
**Network Ports:** UDP 2456-2458  
**Credentials:** Centralized in SOPS secrets vault (`VALHEIM_SERVER_PASS`)  
**World Name:** `Fimbulvetr`  
**Tailscale IP:** `100.124.146.77`  

> **Operational Status:** Running Valheim 1.0.17 / **network version 40** via `mbround18/valheim:3` with BepInEx and server-side mods. The server runs in private mode (`public=false`), accessible exclusively through the encrypted Tailnet. Automated backups run every 30 minutes with off-box sync to the primary NAS over NFS. World portal modifier set to casual mode (teleportation of ores permitted).

## Container Specification

| Container Name | Base Image | Operational Role |
|---|---|---|
| `valheim-server` | `mbround18/valheim:3` | Dedicated server daemon + BepInEx runtime |

## Port Matrix

| Port | Protocol | Purpose |
|---|---|---|
| 2456 | UDP | Primary gameplay connection |
| 2457 | UDP | Steam browser query port |
| 2458 | UDP | Auxiliary query port |

## Environment Parameters

| Parameter | Configuration Value |
|---|---|
| World Name | `Fimbulvetr` |
| Server Name | `Mnemocine Vikings` |
| Server Credentials | Injected via SOPS (`VALHEIM_SERVER_PASS`) |
| Public Discovery | `false` (Direct Tailnet access only) |
| Runtime Framework | `TYPE: BepInEx` |
| World Modifiers | `portals=casual` |
| Automated Updates | Daily check at 03:00 BRT via steamcmd |
| Backup Rotation | Every 30 minutes container-side; daily 05:30 BRT off-box |
| System Timezone | `America/Sao_Paulo` |

## Administrative Access & Permissions (`permissions.yaml`)

**Authoritative Permissions Store:** `config/bepinex/permissions.yaml` on host → `/home/steam/valheim/BepInEx/config/permissions.yaml` within the container filesystem.

```yaml
- id: 76561198075365006
  name: AhNo CaM
  admin: yes
- id: 76561198075365006
  name: AhNo CaM
  character: 1571166467
  admin: yes
```

The game engine populates player records upon their initial login and **reloads permissions on every player join event**. The standard profile requires two entries per account: the base account declaration (`id` + `name` + `admin`) and the character-specific instance (`+ character`, mapped to the player's internal ZDOID).

### Registered Administrators

| Player Name | In-Game Identifier | SteamID64 | Admin Status | Effective Since |
|---|---|---|---|---|
| Carlos (Owner) | AhNo CaM | `76561198075365006` | ✅ Active | 2026-09-09 |
| Titi / Twister / Lira | Lira | `76561198009545651` | ✅ Active | 2026-09-26 |
| Henrique | BiM | `76561197988953037` | ✅ Active | 2026-09-26 |

> Administrative rights attach to the **Steam Account ID** (`id`), automatically propagating privileges to all characters created by that Steam user.

### Legacy Configuration Mirror

`saves/adminlist.txt` is maintained in exact sync with the primary YAML file to preserve backward compatibility with legacy tooling.

## Server-Side Mod Architecture

All active plugins operate **entirely on the server side** — vanilla clients connect seamlessly without installing local mod packages.

| Mod Identifier | Version | Core Capability |
|---|---|---|
| Server_devcommands | 1.115 | Administrative console commands and remote dev tools |
| FuelEternal | 1.2.1 | Continuous combustion for domestic campfires and braziers |
| NoodlesMcDoodles | **1.0.12** | Authoritative server simulation of active zones, monsters, and physics (mitigates rubberbanding and desync) |

> **NoodlesMcDoodles (Deployed 2026-10-04):**  
> Transfers real-time zone simulations (spawns, creature AI, crafting stations) to the dedicated server hardware, preventing the first player entering an area from acting as a fragile peer-to-peer simulation host for neighboring clients. Configured in `FarOrShared` mode with full server authority. Stability parameters tuned via hot-reload: `T9_PingInflationMs = 100`, `T1_GlobalRateBps = 524288` (512 KB/s bandwidth ceiling per client), and `T9_LossThreshold = 0.95`.

### Optional Client-Side Mods

| Mod | Version | Purpose |
|---|---|---|
| Gizmo (ComfyMods) | 1.16.0 | Advanced building component rotation |
| CameraTweaks (Searica) | 1.3.1 | Customizable zoom distances and camera FOV |

## Filesystem Layout

```text
/srv/data/valheim/
├── docker-compose.yml    ← Service definition (MODS, MODIFIERS: portals=casual)
├── .env                  ← VALHEIM_SERVER_PASS
├── config/               ← BepInEx configurations
│   └── bepinex/          ← Mod configuration files
│       └── permissions.yaml  ← Authoritative administrator registry
├── data/                 ← Steam server binary cache (/home/steam/valheim)
├── saves/                ← Active game world and persistent saves
│   ├── adminlist.txt     ← Legacy admin mirror
│   ├── player.list       ← Player session connection registry
│   └── worlds_local/     ← Fimbulvetr.db + native automated snapshots
├── backups/              ← Automated container snapshot volume
└── offbox/               ← NFS mountpoint to psicopompo NAS storage
```

## Backup & Disaster Recovery Architecture

- **Off-Box Snapshots (Primary):** The native game engine writes automated world saves into `saves/worlds_local/Fimbulvetr_backup_auto-*`. The `valheim-backup` script triggers daily incremental `rsync` syncs pushing datasets across the encrypted Tailnet to psicopompo (`/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`).
- **Container Backup Daemon:** Odin creates local archive snapshots every 30 minutes in `/home/steam/backups` with a 7-day retention schedule.
- **Systemd Automation:** `hl-valheim-backup.timer` triggers at 05:30 BRT daily.

## Troubleshooting & Historical Findings

### Compression Compatibility with Valheim 1.0 (Empty World Issue)
- **Symptom:** World loaded with bare terrain devoid of structures and vegetation; logs threw `unknown frame tag 0x48`.
- **Root Cause:** Network compression modules in historical networking mods conflicted with Valheim 1.0 network version 40.
- **Resolution:** Keep compression disabled while network protocol version remains on 40.

### Steam Cloud Mute Bug (Client-Side Sign Visibility)
- **Symptom:** Text on wooden signs and player chat messages appeared obscured with `TEXT HIDDEN DUE UGC SETTINGS` for a specific client.
- **Root Cause:** A historical player mute created an empty `blocked_players` file on the client machine. Steam Cloud synchronization rejected uploading zero-byte files (HTTP 403 Forbidden), indefinitely resurrecting the stale block list.
- **Resolution:** Writing a single newline (`printf '\n' > blocked_players`, 1 byte) permitted Steam Cloud to synchronize successfully without triggering the upload error.

## See Also
- [`onboarding.md`](onboarding.md) — Player connection setup guide
- [`ssh-runbook.md`](ssh-runbook.md) — SSH maintenance commands
- [`../../servers/kavure.md`](../../servers/kavure.md) — Kavure node documentation
