---
tags: [homelab, service, crafty, gaming]
---

# Crafty Controller

Painel de gerenciamento de servidores Minecraft.

**Servidor:** kavure
**Porta Admin:** `8444` (host `8444` → container `8443`)
**Porta Jogo:** `25565`
**URL:** `https://kavure.chimaera-heptatonic.ts.net:8444`

> **✅ Migrado para o kavure (08/08/2026 — Fase C1):** Crafty + servidor Dominium (Minecraft 1.21.1/Fabric) movidos do psicopompo com **rsync `--checksum` (0 diferenças)**. O **backup (AdvancedBackups) agora vai direto para o NAS** via NFS (`/srv/data/minecraft/offbox` → `/mnt/BACKUP/minecraft-server-kavure/`), seguindo o padrão do zomboid. JVM configurada com **flags G1** (piso 2G / teto 8G / soft 5G) para coexistir com o Zomboid. O psicopompo ficou intacto (crafty parado, nada deletado).
>
> **Backup (13/09/2026):** o AdvancedBackups grava em `/minecraft-backups` (= offbox → NAS) a cada 2h **apenas enquanto o servidor está rodando**. Servidor parado desde 08/08 → último backup completo 28/06 (parciais até 08/08). **Gap esperado** — quando o servidor voltar, o backup automático retoma. Se for reativar sem ligar o servidor, fazer rsync manual do mundo primeiro.

> **🔄 Update de modpack + loader (06/10/2026):** o servidor foi ressincronizado com a instância **Dominium** do Prism Launcher (psicopompo), que teve update massivo em 06/10. **Fabric Loader 0.18.4 → 0.19.5** (obrigatório: `fabric-language-kotlin 1.14.1` exige `>=0.19.5` e `puzzleslib 21.1.62` exige `>=0.19.0`; o cliente em 0.19.3 também estava quebrado e foi corrigido). Sincronia feita **por `id` do `fabric.mod.json`** (nunca por nome de arquivo) e **excluindo `environment: "client"`**: **33 mods compartilhados atualizados**, `armor_model_api` **adicionado** (novo requisito de `archers/paladins/rogues/wizards` 3.1.3), 118 `.pw.toml` soltos e 2 mods client-only (`libIPN`, `reflex`) removidos. Estado final: **103 jars no servidor × 111 no cliente → 77 compartilhados em versões idênticas** (paridade), 33 client-only e 24 server-only por design. Boot validado em sandbox (`Done`, 256 mods) e no servidor real (`Done (205s)`, 257 mods; SLP `:9095` → HTTP 200 "up"). Backup pré-update: `/srv/data/minecraft/pre-update/20261006/` (mods/config, 459 MB) + off-box `offbox/archive/pre-update-20261006/` (mundo, 37 GB / 12 427 arquivos). Ver [[dominium-permissions]].
>
> **Backup retomado (06/10/2026):** o servidor voltou a rodar (parado desde 08/08) → o **AdvancedBackups** retoma a gravação a cada 2 h em `/minecraft-backups` (offbox → NAS). O gap 08/08–06/10 foi coberto pelo snapshot manual pré-update.
>
> **⚠️ Distribuição packwiz morta (06/10/2026):** o repositório `ceduardorodrig/DOMINIUM-MODPACK` e o GitHub Pages `https://ceduardorodrig.github.io/DOMINIUM-MODPACK/pack.toml` respondem **404** (repo privado ou removido), e não há credencial git no kavure para push. A distribuição do modpack para novos clientes está **quebrada**; a fonte de verdade passou a ser a **instância do Prism** em psicopompo.

## Stack

| Container | Imagem | Função |
|---|---|---|
| crafty-controller | crafty-4 | Gerenciamento + servidor Minecraft |

## Portas

| Porta | Função |
|---|---|
| `8443` | Interface web (HTTPS) |
| `25565` | Servidor Minecraft (Java) |
| `25575` | RCON (localhost) |
| `8123` | Mapa dinâmico |
| `5520-5550` | Proxy/portais |
| `19132` | Bedrock |

## Acesso

`https://kavure.chimaera-heptatonic.ts.net:8444`

## Dados

Volumes Docker persistentes com configurações, mundos e backups automáticos do Crafty.

## Servidores

- [[dominium-permissions]] — Servidor modded Dominium (grupos, players, permissões)
