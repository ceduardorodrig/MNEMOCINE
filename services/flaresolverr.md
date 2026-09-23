---
tags: [homelab, service, flaresolverr, download]
---

# Flaresolverr

Proxy que resolve desafios Cloudflare para scrapers e indexers.

**Servidor:** kuaray
**Porta:** `8191`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:8191`

## Stack

| Container | Imagem | Função |
|---|---|---|
| flaresolverr | flaresolverr/flaresolverr:latest | Proxy Cloudflare |

## Integração

Usado pelo **Prowlarr** para acessar indexers de torrent que usam proteção Cloudflare.

## Funcionamento

1. Prowlarr envia requisição via Flaresolverr
2. Flaresolverr resolve o desafio JavaScript/Cloudflare
3. Retorna o conteúdo resolvido para o Prowlarr
