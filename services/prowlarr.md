---
tags: [homelab, service, prowlarr, download]
---

# Prowlarr

Indexer unificado para o *arr stack.

**Servidor:** kuaray
**Porta:** `9696`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:9696`

## Stack

| Container | Imagem | Função |
|---|---|---|
| prowlarr | linuxserver/prowlarr:latest | Gerenciamento de indexers |

## Integração

Alimenta os indexers para:
- Lidarr (música)
- Demais *arr conforme necessidade

## Funcionamento

1. Centraliza múltiplos indexers de torrent/usenet
2. Sincroniza automaticamente com os apps *arr conectados
3. Usa Flaresolverr para sites protegidos por Cloudflare

## Segredos

- **API key** no store sops (`PROWLARR_API_KEY`, 32-char — fonte `config.xml` `<ApiKey>`). O `config.xml` é **excluído** do espelho `config-backup` (nunca vai pro NAS). Restore após wipe: `inject-secrets.sh` (ver `guides/secrets-centralizados.md`).
