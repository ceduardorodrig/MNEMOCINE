---
tags: [homelab, service, navidrome, media]
---

# Navidrome

Streaming de música — servidor Subsonic-API compatível.

**Servidor:** kavure (migrado 09/08/2026)
**Porta:** `4533`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:4533`

## Stack

| Container | Imagem | Função |
|---|---|---|
| navidrome | deluan/navidrome:latest | Streaming de música |

## Acesso

`http://kuaray.chimaera-heptatonic.ts.net:4533`

## Clientes Compatíveis

- **Ultrasonic** (Android)
- **SonicWeb** (navegador)
- **Substreamer** (iOS)
- **Tauon Music Box** (Linux) — integração com `localhost:7813`

## Integração

Música gerenciada pelo **Lidarr** que baixa e organiza as faixas automaticamente. O Navidrome lê a biblioteca de música e serve para os clientes.

## Dados

Biblioteca de música montada como volume Docker nos discos do kuaray.
