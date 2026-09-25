---
tags: [homelab, service, changedetection, monitoring, ybytu]
---

# Changedetection.io

Web page change monitoring. Runs on ybytu (Docker).

**Server:** ybytu

## Deploy

```bash
docker run -d --restart unless-stopped --name changedetection \
  -p 8082:5000 \
  -v changedetection-data:/datastore \
  dgtlmoon/changedetection.io
```

## Access

- URL: `http://100.115.253.109:8082`
- Tailscale DNS: `http://ybytu.chimaera-heptatonic.ts.net:8082`
- API token: Settings → API
- Notification: ntfy (`ntfy://100.115.253.109:8083/cambiomonitor`)

## Config

- Text/HTML mode (`html_requests`), without Playwright (saves RAM)
- Default interval: 3h
- Workers: 5
- Timeout: 45s

## RAM

~50-80 MB.

## Suggested Uses

- Graduate program websites (UFSC, USP, CAPES, international)
- Job openings
- Public notices, tenders, and grants
- Product prices
