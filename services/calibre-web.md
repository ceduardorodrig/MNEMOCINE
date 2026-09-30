---
tags: [homelab, service, calibre-web, media]
---

# Calibre-web Automated

Servidor de ebooks com download automático.

**Servidor:** kavure (migrado 09/08/2026)
**Porta:** `8083`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8083`

## Stack

| Container | Imagem | Função |
|---|---|---|
| calibre-web-auto | crocodilestick/calibre-web-automated:latest | Ebook server + download automático |

## Acesso

`http://kavure.chimaera-heptatonic.ts.net:8083`

## Funcionamento

Interface web para leitura e gerenciamento de ebooks. A versão "automated" inclui download automático de livros baseado em regras configuráveis.
