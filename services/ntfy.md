---
tags: [homelab, service, ntfy, monitoring, ybytu]
---

# Ntfy

Push notification server. Runs on ybytu (Docker).

**Server:** ybytu

## Deploy

```bash
docker run -d --restart unless-stopped --name ntfy \
  -p 8083:80 \
  -v ntfy-data:/etc/ntfy \
  binwiederhier/ntfy serve
```

## Access

- URL: `http://100.115.253.109:8083`
- Tailscale DNS: `http://ybytu.chimaera-heptatonic.ts.net:8083`

## Topics

| Topic | Source |
|---|---|
| `chimaera-heptatonic` | Changedetection.io (page changes) |
| `uptimekuma` | Uptime Kuma (downtime alerts) |

## Integrations

- ntfy app on the phone
- Changedetection.io → `ntfy://100.115.253.109:8083/chimaera-heptatonic`
- Uptime Kuma → webhook `http://100.115.253.109:8083/uptimekuma`

## RAM

~15 MB.
