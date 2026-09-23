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

`https://psicopompo.chimaera-heptatonic.ts.net:8443`

## Dados

Volumes Docker persistentes com configurações, mundos e backups automáticos do Crafty.

## Servidores

- [[dominium-permissions]] — Servidor modded Dominium (grupos, players, permissões)
