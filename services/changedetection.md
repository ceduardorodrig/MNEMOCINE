---
tags: [homelab, service, changedetection, monitoring, ybytu]
---

# Changedetection.io

Web page change monitoring and notification daemon. Runs on ybytu (Docker).

**Server:** ybytu

## Deployment

Managed as a **Compose service** (`/home/ubuntu/homelab/changedetection/compose.yml`) — the homelab
rule forbids orphan `docker run` containers:

```yaml
name: changedetection
services:
  changedetection:
    image: dgtlmoon/changedetection.io:latest
    container_name: changedetection
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/', timeout=5)\""]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s
    volumes:
      - ./data:/datastore
      - /etc/localtime:/etc/localtime:ro
      - /usr/share/zoneinfo:/usr/share/zoneinfo:ro
    environment:
      - TZ=America/Sao_Paulo
    ports:
      - "8082:5000"
    network_mode: "bridge"
```

> **Correction (2026-10-13):** this doc previously showed an orphan `docker run …` command. Verified
> live: the container is created and owned by the Compose project above (`docker ps` →
> `changedetection`, `com.docker.compose.project=changedetection`), consistent with the
> config-as-code rule in [`AGENTS.md`](../AGENTS.md).

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
