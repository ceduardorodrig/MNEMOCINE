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

- **Tailscale:** `http://kavure.chimaera-heptatonic.ts.net:3000` (`100.124.146.77:3000`)
- **Público:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Tailscale Funnel)

> 📌 **Binds de Rede (04/10/2026):** O container publica tanto em `100.124.146.77:3000` (Zona 1 - Tailnet) quanto em `127.0.0.1:3000` (Zona 0 - Loopback). O bind em loopback é necessário para que o daemon do Tailscale Funnel consiga encaminhar o tráfego público recebido na porta `10000` sem expor o serviço na LAN física (`0.0.0.0`). Configuração em `/home/kavure/homelab/aiostreams/compose.yml`.

## Funcionamento

Proxy que recebe requisições de players (ex: Stremio) e retorna streams resolvidos via serviços de terceiros.
