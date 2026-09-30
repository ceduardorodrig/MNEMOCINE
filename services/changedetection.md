---
tags: [homelab, service, changedetection, monitoring, ybytu]
---

# Changedetection.io

Monitoramento de mudanças em páginas web. Roda no ybytu (Docker).

**Servidor:** ybytu

## Deploy

```bash
docker run -d --restart unless-stopped --name changedetection \
  -p 8082:5000 \
  -v changedetection-data:/datastore \
  dgtlmoon/changedetection.io
```

## Acesso

- URL: `http://100.115.253.109:8082`
- Tailscale DNS: `http://ybytu.chimaera-heptatonic.ts.net:8082`
- API token: Settings → API
- Notificação: ntfy (`ntfy://100.115.253.109:8083/cambiomonitor`)

## Config

- Modo text/HTML (`html_requests`), sem Playwright (economia de RAM)
- Intervalo padrão: 3h
- Workers: 5
- Timeout: 45s

## RAM

~50-80 MB.

## Uso sugerido

- Páginas de programas de mestrado (UFSC, USP, CAPES, exterior)
- Vagas de emprego
- Editais e bolsas
- Preço de produtos
