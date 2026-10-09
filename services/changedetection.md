---
tags: [homelab, service, changedetection, monitoring, ybytu]
---

# Changedetection.io

Web page change monitoring and notification daemon. Runs on ybytu (Docker).

**Server:** ybytu

## Deployment

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
- Notifications: ntfy (`ntfy://100.115.253.109:8083/chimaera-heptatonic`)

## Configuration

- Text/HTML fetch mode (`html_requests`), without Playwright (saves RAM)
- Default interval: 3h
- Workers: 5
- Timeout: 45s

## RAM Usage

~50–80 MB.

## Suggested Use Cases

- Master's program portals and academic notices (UFSC, USP, CAPES, international)
- Job boards and postings
- Public procurement and grants
- Product price alerts
