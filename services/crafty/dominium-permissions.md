---
tags: [homelab, service, crafty, gaming, server, kavure]
---

# Dominium — Servidor Minecraft

Servidor modded Fabric gerenciado pelo Crafty Controller no kavure (migrado do psicopompo em 08/08/2026).

**Servidor físico:** kavure
**Container:** crafty-controller
**Diretório:** `/srv/data/minecraft/minecraftserver [dominium]/`

## Acesso

| Tipo | Como |
|---|---|
| IP do servidor | `kavure.chimaera-heptatonic.ts.net` |
| Porta | `25565` (Java Edition) |
| Console | Crafty Admin → `https://kavure.chimaera-heptatonic.ts.net:8444` |
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

## Modpack (Dominium)

A **fonte de verdade é a instância do Prism Launcher** em psicopompo (`/home/edu/.local/share/PrismLauncher/instances/Dominium/`).

| Item | Valor |
|---|---|
| Cliente | Prism Launcher — instância `Dominium` (psicopompo) |
| Mod loader | **Fabric 0.19.5** (cliente e servidor) |
| MC Version | 1.21.1 |
| Mods | **111 jars no cliente / 103 no servidor** → 77 compartilhados em versões idênticas, 33 client-only, 24 server-only |
| Diretório do servidor | `/srv/data/minecraft/minecraftserver [dominium]/MINECRAFT SERVER/` (kavure) |
| Scripts | **centralizados na pasta do servidor (kavure)**: `/srv/data/minecraft/minecraftserver [dominium]/` — `client-push.sh`, `sync_mods.py`, `export_mrpack.py`, `README.md` |

> ⚠️ **Canal packwiz + GitHub Pages MORTO (06/10/2026):** o repo [ceduardorodrig/DOMINIUM-MODPACK](https://github.com/ceduardorodrig/DOMINIUM-MODPACK) e a Pack URL `https://ceduardorodrig.github.io/DOMINIUM-MODPACK/pack.toml` respondem **404** (privado ou removido), sem credencial git no kavure. O fluxo antigo (`packwiz update --all`, `packwiz mr add`, `deploy.sh`) **não funciona mais** — ver [[crafty]].

### Sincronizar servidor com o cliente (fluxo canônico desde 06/10/2026)

Regras de ouro:

1. **Fonte de verdade = a instância do Prism.** Não se edita mods "no servidor".
2. Pareamento **por `id` do `fabric.mod.json`** (estável entre versões), **nunca por nome de arquivo**.
3. Mods com `environment: "client"` **nunca** vão para o servidor; mods server-only são **preservados** (LuckPerms + `mods/luckperms/`, AdvancedBackups, Chunky, Ledger…).
4. **Backup antes de mexer** (servidor parado ⇒ mundo estático): `/srv/data/minecraft/pre-update/<data>/` (local, rollback rápido) + `offbox/archive/pre-update-<data>/` (NAS, off-box).
5. Servidor é subido/parado **pelo Crafty** (`POST /api/v2/servers/{id}/action/start_server`, API key `agentic.ai` no store sops).

Todas as ferramentas ficam **na pasta do servidor, no kavure** (fonte canônica, centralizada em 06/10/2026). Como `client-push.sh` e `export_mrpack.py` **precisam rodar no psicopompo** (é onde está a instância do Prism), eles são **buscados do kavure na hora**:

```bash
D="/srv/data/minecraft/minecraftserver [dominium]"

# 1) kavure: parar o servidor pelo Crafty + snapshot pré-update (ver crafty.md)
# 2) psicopompo: buscar e rodar o client-push.sh (envia os mods do Prism -> staging no kavure)
tailscale ssh kavure@kavure "cat '$D/client-push.sh'" > /tmp/dominium-push.sh && bash /tmp/dominium-push.sh
# 3) kavure: aplicar por id (dry-run, depois --apply)
tailscale ssh kavure@kavure "python3 '$D/sync_mods.py'"
tailscale ssh kavure@kavure "python3 '$D/sync_mods.py' --apply"
```

Ao terminar: subir pelo Crafty e conferir `Done (...)` em `MINECRAFT SERVER/logs/latest.log` (e o probe SLP `:9095`).

> **Loader:** o Fabric Loader do servidor é atualizado com o instalador oficial dentro do container do Crafty:
> `java -jar fabric-installer.jar server -mcversion 1.21.1 -loader <versão>` (sem `-downloadMinecraft`, para preservar o `server.jar`) e **apagar o `.fabric/`** em seguida.

> **Instalação limpa no Prism:** o pack URL está morto — uma instalação do zero hoje só é possível copiando a instância `Dominium` do psicopompo ou usando o `.mrpack` (abaixo).

### Distribuir para novos jogadores (`.mrpack`) — desde 06/10/2026

Como o Prism **não tem export por CLI** e o canal packwiz morreu, a distribuição é feita gerando um **`.mrpack` (Modrinth)**. O gerador fica na **pasta do servidor (kavure)** e é buscado na hora (ele precisa rodar no psicopompo, onde está o Prism):

```bash
D="/srv/data/minecraft/minecraftserver [dominium]"
# na máquina com a instância (psicopompo):
tailscale ssh kavure@kavure "cat '$D/export_mrpack.py'" > /tmp/dominium-mrpack.py \
  && python3 /tmp/dominium-mrpack.py 1.1.0
# -> ~/Dominium-1.1.0.mrpack  (~73 MB)
```

O script: resolve cada jar por **sha512** no Modrinth (110 dos 111 viram **link**; o que não resolver — ex.: o `archers`, build CurseForge — vai **embutido** em `overrides/mods/`), monta o `modrinth.index.json` com `dependencies { minecraft 1.21.1, fabric-loader 0.19.5 }` e empacota os overrides (`config/`, `defaultconfigs/`, `resourcepacks/`, `shaderpacks/`, `emi.json`, `ph_config.txt`, `icon.png`).

Regras do script:
- **`env.client = "required"` para TODOS** — o Modrinth marca alguns worldgen/libs como `client=unsupported` (ex.: `structure_pool_api`, dependência do `jewelry`); pular esses quebraria o cliente.
- **Exclui**: `Distant_Horizons_server_data` (cache de LOD, GBs), `saves`, `logs`, `crash-reports`, `xaero`, `screenshots`, `essential`, `pfm`, `options.txt` (keybinds) e as libs nativas do Super Resolution (`config/super_resolution/libraries`, ~135 MB — o mod re-extrai/rebaixa).

O amigo importa no Prism via **Add Instance → Import from file** (funciona também no Modrinth App/ATLauncher).

## See also
- [[crafty]] — Crafty Controller
- [[kavure]] — Servidor (hospeda o Dominium desde 08/08/2026)
- [[mods-list]] — Lista de mods cliente/servidor
