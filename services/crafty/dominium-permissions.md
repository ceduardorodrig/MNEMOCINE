---
tags: [homelab, service, crafty, gaming, server, kavure]
---

# Dominium — Minecraft Server Runbook & Permissions

Modded Fabric Minecraft server orchestrated via Crafty Controller 4 on kavure (migrated from psicopompo on 2026-08-08).

**Physical Node:** kavure  
**Container:** `crafty-controller`  
**Filesystem Path:** `/srv/data/minecraft/minecraftserver [dominium]/`  

## Connection & Management Endpoints

| Connection Type | Target / Method |
|---|---|
| Server IP | `kavure.chimaera-heptatonic.ts.net` |
| Port | `25565` (Java Edition) |
| Web Management Console | Crafty Admin → `https://kavure.chimaera-heptatonic.ts.net:8444` |
| Local RCON | `localhost:25575` (Loopback binding on host) |

## LuckPerms Group Hierarchy

| Group | Chat Prefix | Inherits From | Core Permissions |
|---|---|---|---|
| `admin` | `<dark_gray>[<red>Admin<dark_gray>]` | — | All commands: give, time, weather, tp, gamemode, selector, advancedbackups, ledger |
| `dominium` | — | `default` | Survival mode + trusted access |
| `builder` | — | `default` | Survival mode + `/gamemode` |
| `lonewanderer` | — | `default` | Survival mode + `/tpa`, `/tpaccept`, `/back`, `/home`, `/sethome`, `/spawn` |
| `default` | — | — | Standard player baseline: `/msg`, `/tpa`, `/tpaccept`, `/back`, `/home`, `/sethome`, `/spawn` |

## Registered Player Profiles

| Player Username | UUID | Assigned Group |
|---|---|---|
| oxelytrum | `86869f39-8b2e-4519-bfa1-6c86e0b49d4c` | `dominium` |
| twister2700 | `9d6c62d9-16ca-4159-8614-9a067848bf53` | `dominium` |
| onidsouza | `f971f8da-379e-4190-9032-c3ba8fc3eda5` | `builder` |

## Essential LuckPerms CLI Commands

```bash
# Display user details and parent groups:
/lp user <player> info

# Inspect group permissions:
/lp group <group> permission info

# Assign user to parent group:
/lp user <player> parent set <group>

# Grant specific node permission:
/lp user <player> permission set <permission.node> true

# Create permission group:
/lp creategroup <name>

# Export permissions registry:
/lp export
```

## Permissions Storage & Backups

LuckPerms stores its database in an H2 database file inside the container volume:  
`/crafty/servers/dominium/mods/luckperms/luckperms-h2-v2.mv.db`

Backup database snapshot:
```bash
docker cp crafty-controller:/crafty/servers/dominium/mods/luckperms/luckperms-h2-v2.mv.db /backup/
```

Restore database snapshot:
```bash
docker cp /backup/luckperms-h2-v2.mv.db crafty-controller:/crafty/servers/dominium/mods/luckperms/
docker restart crafty-controller
```

## Modpack Architecture (Dominium)

The **canonical source of truth is the Prism Launcher client instance** hosted on psicopompo (`/home/edu/.local/share/PrismLauncher/instances/Dominium/`).

| Specification | Configuration |
|---|---|
| Client Environment | Prism Launcher — `Dominium` instance (psicopompo) |
| Mod Loader | **Fabric 0.19.5** (Unified across client and server) |
| Minecraft Version | 1.21.1 |
| Mod Distribution | **111 JARs in client / 103 JARs on server** → 77 shared identical versions, 33 client-only, 24 server-only |
| Server Directory | `/srv/data/minecraft/minecraftserver [dominium]/MINECRAFT SERVER/` (kavure) |
| Automation Tooling | Centralized inside `/srv/data/minecraft/minecraftserver [dominium]/` (`client-push.sh`, `sync_mods.py`, `export_mrpack.py`) |

> ⚠️ **packwiz & GitHub Pages Distribution Deprecated (2026-10-06):**  
> The historical repository `ceduardorodrig/DOMINIUM-MODPACK` and its GitHub Pages endpoint return HTTP 404. Packwiz sync flows are replaced by direct synchronization scripts and `.mrpack` distribution.

### Synchronizing Server with Client (Canonical Workflow Since 2026-10-06)

Operational Rules:
1. **Source of Truth = Prism Client Instance.** Do not modify mods directly on the server without client parity.
2. Pair mod files **by Fabric mod ID in `fabric.mod.json`**, never by arbitrary JAR filenames.
3. Mods declared with `environment: "client"` are strictly excluded from the server; server-only mods (LuckPerms, AdvancedBackups, Chunky, Ledger) are preserved.
4. **Mandatory Snapshot Prior to Updates:** Create pre-update backup at `/srv/data/minecraft/pre-update/<date>/` (local fast rollback) and `offbox/archive/pre-update-<date>/` (NAS target).
5. Start and stop servers cleanly via Crafty API (`POST /api/v2/servers/{id}/action/start_server`, authenticated with `agentic.ai` key in SOPS).

```bash
D="/srv/data/minecraft/minecraftserver [dominium]"

# 1) kavure: Suspend server via Crafty and generate pre-update snapshot
# 2) psicopompo: Fetch and execute client-push.sh (transfers Prism mods -> staging directory on kavure)
tailscale ssh kavure@kavure "cat '$D/client-push.sh'" > /tmp/dominium-push.sh && bash /tmp/dominium-push.sh

# 3) kavure: Reconcile mod IDs (dry-run first, then commit with --apply)
tailscale ssh kavure@kavure "python3 '$D/sync_mods.py'"
tailscale ssh kavure@kavure "python3 '$D/sync_mods.py' --apply"
```

Restart through Crafty and inspect startup completion (`Done (...)`) in `MINECRAFT SERVER/logs/latest.log`.

### Distributing Client Packs to Players (`.mrpack`)

Because Prism does not support headless CLI export, client distribution packages are compiled into standard Modrinth format (`.mrpack`):

```bash
D="/srv/data/minecraft/minecraftserver [dominium]"
tailscale ssh kavure@kavure "cat '$D/export_mrpack.py'" > /tmp/dominium-mrpack.py \
  && python3 /tmp/dominium-mrpack.py 1.1.0
# Outputs ~/Dominium-1.1.0.mrpack (~73 MB)
```

The script resolves each JAR against the Modrinth API by SHA-512 (linking online files while embedding unindexed dependencies like `archers`), generates `modrinth.index.json`, and bundles necessary configuration overrides (`config/`, `shaderpacks/`, `resourcepacks/`). Players import the generated `.mrpack` into Prism Launcher, Modrinth App, or ATLauncher via **Add Instance → Import from file**.

## See Also
- [`../crafty.md`](../crafty.md) — Crafty Controller architecture
- [`../../servers/kavure.md`](../../servers/kavure.md) — Kavure dedicated server profile
- [`mods-list.md`](mods-list.md) — Full client/server mod catalog
