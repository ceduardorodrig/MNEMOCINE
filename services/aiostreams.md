---
tags: [homelab, service, aiostreams, media]
---

# aiostreams

Proxy de streaming para players de mídia.

**Servidor:** kavure
**Porta:** `3000`
**Funnel:** `kavure.chimaera-heptatonic.ts.net:10000`
**URL interna:** `http://localhost:3000`
**URL pública:** `https://kavure.chimaera-heptatonic.ts.net:10000`

## Stack

| Container | Imagem | Função |
|---|---|---|
| aiostreams | viren070/aiostreams:latest | Proxy de streaming |

## Acesso

- **Tailscale:** `http://kavure.chimaera-heptatonic.ts.net:3000`
- **Público:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Funnel)

## Funcionamento

Proxy que recebe requisições de players (ex: Stremio) e retorna streams resolvidos via serviços de terceiros.
