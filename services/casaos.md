---
tags: [homelab, service, casaos, monitoring]
---

# CasaOS

kuaray server management panel — orchestration of containers and services.

> **⚠️ REMOVED (08/08/2026):** CasaOS uninstalled from kuaray (no longer used; SSH/docker is enough). Port 80 freed, systemd services and files removed (`casaos-uninstall` + manual cleanup). References removed from homepage and the docs. This doc stays as history.

**Server:** ~~kuaray~~ (removed)
**Port:** ~~`8800`~~

## Systemd Services

| Service | Role |
|---|---|
| casaos.service | Main panel |
| casaos-gateway.service | Internal reverse proxy |
| casaos-app-management.service | App management |
| casaos-local-storage.service | Disk management |
| casaos-message-bus.service | Message bus |
| casaos-user-service.service | User management |

## Operation

CasaOS manages kuaray's Docker containers through a simplified web interface. It replaces Portainer as the visual management layer on this server.

## Access

`http://kuaray.chimaera-heptatonic.ts.net:8800`

## Maintenance

```bash
systemctl status casaos.service
systemctl restart casaos-gateway.service
```
