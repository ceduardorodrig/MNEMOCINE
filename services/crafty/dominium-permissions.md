---
tags: [homelab, service, crafty, gaming, server, psicopompo]
---

# Dominium — Servidor Minecraft

Servidor modded Fabric gerenciado pelo Crafty Controller no psicopompo.

**Servidor físico:** psicopompo
**Container:** crafty-controller
**Diretório:** `/mnt/NVME_PCI/minecraftserver [dominium]/`

## Acesso

| Tipo | Como |
|---|---|
| IP do servidor | `psicopompo.chimaera-heptatonic.ts.net` |
| Porta | `25565` (Java Edition) |
| Console | Crafty Admin → `https://psicopompo.chimaera-heptatonic.ts.net:8443` |
| RCON | localhost:25575 (apenas do host) |

## Grupos do LuckPerms

| Grupo | Prefixo | Herda de | Permissões principais |
|---|---|---|---|
| `admin` | `<dark_gray>[<red>Admin<dark_gray>]` | — | All commands: give, time, weather, tp, gamemode, selector, advancedbackups, ledger |
| `dominium` | — | default | Survival + confiança total |
| `builder` | — | default | Survival + `/gamemode` |
| `lonewanderer` | — | default | Survival + `/tpa`, `/tpaccept`, `/back`, `/home`, `/sethome`, `/spawn` |
| `default` | — | — | `/msg`, `/tpa`, `/tpaccept`, `/back`, `/home`, `/sethome`, `/spawn` |

## Players Registrados

| Player | UUID | Grupo |
|---|---|---|
| oxelytrum | `86869f39-8b2e-4519-bfa1-6c86e0b49d4c` | `dominium` |
| twister2700 | `9d6c62d9-16ca-4159-8614-9a067848bf53` | `dominium` |
| onidsouza | `f971f8da-379e-4190-9032-c3ba8fc3eda5` | `builder` |

## Comandos Úteis (LuckPerms)

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

As permissões estão no banco H2 do LuckPerms dentro do container:
`/crafty/servers/dominium/mods/luckperms/luckperms-h2-v2.mv.db`

Para backup:
```bash
docker cp crafty-controller:/crafty/servers/dominium/mods/luckperms/luckperms-h2-v2.mv.db /backup/
```

Para restaurar:
```bash
docker cp /backup/luckperms-h2-v2.mv.db crafty-controller:/crafty/servers/dominium/mods/luckperms/
docker restart crafty-controller
```

## Modpack (DOMINIUM-MODPACK)

O modpack é distribuído via **Packwiz + GitHub Pages** com auto-update.

| Item | Valor |
|---|---|
| Repositório | [ceduardorodrig/DOMINIUM-MODPACK](https://github.com/ceduardorodrig/DOMINIUM-MODPACK) |
| Pack URL | `https://ceduardorodrig.github.io/DOMINIUM-MODPACK/pack.toml` |
| Mod loader | Fabric 0.19.3 |
| MC Version | 1.21.1 |
| Mods | 112 (Modrinth) |

### Atualizar mods

```bash
cd /home/edu/DOMINIUM-MODPACK
packwiz update --all
packwiz refresh
git add -A
git commit -m "Atualizar mods $(date +%d/%m/%Y)"
git push
```

### Adicionar mod novo

```bash
packwiz mr add <slug>
packwiz refresh
git add -A && git commit -m "Adicionar <mod>" && git push
```

### Sincronizar servidor

O servidor Crafty precisa dos mesmos mods (lado `server`/`both`). Use o script:

```bash
python3 "/mnt/NVME_PCI/minecraftserver [dominium]/sync_mods.py"
```

### Instalação limpa

Para testar a instalação do zero no PrismLauncher:
1. `Adicionar Instância` → `Importar` → colar a Pack URL acima
2. Baixar [packwiz-installer-bootstrap.jar](https://github.com/packwiz/packwiz-installer-bootstrap/releases)
3. Colocar em `minecraft/` e configurar como comando de pré-lançamento

## See also
- [[crafty]] — Crafty Controller
- [[psicopompo]] — Servidor
- [[psicopompo-gaming]] — Jogos no psicopompo
