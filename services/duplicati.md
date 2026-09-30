---
tags: [homelab, service, duplicati, backup]
---

# Duplicati

> **🟥 REMOVIDO (06/08/2026)** — não cobria dados de valor; substituído pelo
> [backup canônico de configs](../backups/config-backup.md) (espelho NAS + restic + git + snapper) e off-site (rclone → Drive).

Backup automatizado com interface web.

**Servidor:** ~~kuaray~~ (histórico)
**Porta:** ~~`8200`~~

## Stack

| Container | Imagem | Função |
|---|---|---|
| duplicati | linuxserver/duplicati:latest | Backup |

## Acesso

`http://kuaray.chimaera-heptatonic.ts.net:8200`

## Estado Atual

**Removido** — não roda mais. Mantido como registro histórico.

## Recomendações

- Configurar backup off-site para a nuvem (B2, S3, etc.)
- Backup dos bancos PostgreSQL do StênioBOT e Umami
- Backup das configs do Tailscale (não essencial, mas útil)
- Testar restore periodicamente
