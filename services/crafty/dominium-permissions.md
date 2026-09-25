---
tags: [homelab, service, crafty, gaming, server, kavure]
---

# Dominium — Minecraft Server

Modded Fabric server managed by Crafty Controller on kavure (migrated from psicopompo on 08/08/2026).

**Physical server:** kavure
**Container:** crafty-controller
**Directory:** `/srv/data/minecraft/minecraftserver [dominium]/`

## Access

| Type | How |
|---|---|
| Server IP | `kavure.chimaera-heptatonic.ts.net` |
| Port | `25565` (Java Edition) |
| Console | Crafty Admin → `https://kavure.chimaera-heptatonic.ts.net:8444` |
| RCON | localhost:25575 (host only) |

## LuckPerms Groups

| Group | Prefix | Inherits from | Main permissions |
|---|---|---|---|
| `admin` | `<dark_gray>[<red>Admin<dark_gray>]` | — | All commands: give, time, weather, tp, gamemode, selector, advancedbackups, ledger |
| `dominium` | — | default | Survival + full trust |
| `builder` | — | default | Survival + `/gamemode` |
| `lonewanderer` | — | default | Survival + `/tpa`, `/tpaccept`, `/back`, `/home`, `/sethome`, `/spawn` |
| `default` | — | — | `/msg`, `/tpa`, `/tpaccept`, `/back`, `/home`, `/sethome`, `/spawn` |

## Registered Players

| Player | UUID | Group |
|---|---|---|
| oxelytrum | `86869f39-8b2e-4519-bfa1-6c86e0b49d4c` | `dominium` |
| twister2700 | `9d6c62d9-16ca-4159-8614-9a067848bf53` | `dominium` |
| onidsouza | `f971f8da-379e-4190-9032-c3ba8fc3eda5` | `builder` |

## Useful Commands (LuckPerms)

```bash
# Ver grupo de um player
/lp user <player> info

# Ver permissões de um grupo
/lp group <grupo> permission info

# Adicionar player a um grupo
/lp user <player> parent set <grupo>

# Dar permissão específica
/lp user <player> permission set <permissao> true

# Criar grupo
/lp creategroup <nome>

# Exportar todas as permissões
/lp export
```

## Backup

The permissions live in the LuckPerms H2 database inside the container:
`/crafty/servers/dominium/mods/luckperms/luckperms-h2-v2.mv.db`

To back up:
```bash
docker cp crafty-controller:/crafty/servers/dominium/mods/luckperms/luckperms-h2-v2.mv.db /backup/
```

To restore:
```bash
docker cp /backup/luckperms-h2-v2.mv.db crafty-controller:/crafty/servers/dominium/mods/luckperms/
docker restart crafty-controller
```

## Modpack (DOMINIUM-MODPACK)

The modpack is distributed via **Packwiz + GitHub Pages** with auto-update.

| Item | Value |
|---|---|
| Repository | [ceduardorodrig/DOMINIUM-MODPACK](https://github.com/ceduardorodrig/DOMINIUM-MODPACK) |
| Pack URL | `https://ceduardorodrig.github.io/DOMINIUM-MODPACK/pack.toml` |
| Mod loader | Fabric 0.19.3 |
| MC Version | 1.21.1 |
| Mods | 112 (Modrinth) |

### Update mods

```bash
cd /home/edu/DOMINIUM-MODPACK
packwiz update --all
packwiz refresh
git add -A
git commit -m "Atualizar mods $(date +%d/%m/%Y)"
git push
```

### Add a new mod

```bash
packwiz mr add <slug>
packwiz refresh
git add -A && git commit -m "Adicionar <mod>" && git push
```

### Sync the server

The Crafty server needs the same mods (`server`/`both` side). Use the script:

```bash
python3 "/mnt/NVME_PCI/minecraftserver [dominium]/sync_mods.py"
```

### Clean installation

To test a from-scratch install on PrismLauncher:
1. `Adicionar Instância` → `Importar` → paste the Pack URL above
2. Download [packwiz-installer-bootstrap.jar](https://github.com/packwiz/packwiz-installer-bootstrap/releases)
3. Place it in `minecraft/` and configure it as the pre-launch command

## See also
- [[crafty]] — Crafty Controller
- [[psicopompo]] — Server
- [[psicopompo-gaming]] — Games on psicopompo
