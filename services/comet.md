---
tags: [homelab, service, comet, download]
---

# Comet

Servidor de mídia via debrid.

**Servidor:** kavure
**Porta:** `8000`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8000`

## Stack

| Container | Imagem | Função |
|---|---|---|
| comet | ghcr.io/g0ldyy/comet:latest | Debrid media agregator |

## Funcionamento

Agrega conteúdo de serviços de debrid (Real-Debrid, AllDebrid, etc.) e disponibiliza via API compatível com players de mídia.

## Portas

| Porta | Função |
|---|---|
| `8000` | API web |
