---
tags: [homelab, service, ntfy, monitoring, ybytu]
---

# Ntfy

Servidor de notificações push. Roda no ybytu (Docker).

**Servidor:** ybytu

## Deploy

```bash
docker run -d --restart unless-stopped --name ntfy \
  -p 8083:80 \
  -v ntfy-data:/etc/ntfy \
  binwiederhier/ntfy serve
```

## Acesso

- URL: `http://100.115.253.109:8083`
- Tailscale DNS: `http://ybytu.chimaera-heptatonic.ts.net:8083`

## Tópicos

| Tópico | Origem |
|---|---|
| `chimaera-heptatonic` | Changedetection.io (mudanças em páginas) |
| `uptimekuma` | Uptime Kuma (alertas de downtime) |

## Integrações

- App ntfy no celular
- Changedetection.io → `ntfy://100.115.253.109:8083/chimaera-heptatonic`
- Uptime Kuma → webhook `http://100.115.253.109:8083/uptimekuma`

## RAM

~15 MB.
