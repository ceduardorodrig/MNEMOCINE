---
tags: [homelab, service, casaos, monitoring]
---

# CasaOS

Management dashboard for kuaray node — container and service orchestration.

> **⚠️ DECOMMISSIONED (08/08/2026):** CasaOS uninstalled from kuaray (rendered obsolete; SSH/Docker CLI suffices). Port 80 released, systemd units and assets purged (`casaos-uninstall` + manual cleanup). References purged from Homepage and active documentation. Preserved strictly for historical context.

**Server:** ~~kuaray~~ (decommissioned)  
**Port:** ~~`8800`~~  

## Systemd Services

| Service | Function |
|---|---|
| casaos.service | Primary control panel |
| casaos-gateway.service | Internal reverse proxy |
| casaos-app-management.service | App ecosystem management |
| casaos-local-storage.service | Local disk manager |
| casaos-message-bus.service | Message bus daemon |
| casaos-user-service.service | User authentication service |

## Operational Model

CasaOS previously managed Docker containers on kuaray through a visual web interface. It served as a lightweight alternative to Portainer for graphical management on that node.

## Historical Access

`http://kuaray.chimaera-heptatonic.ts.net:8800`

## Legacy Maintenance Commands

```bash
systemctl status casaos.service
systemctl restart casaos-gateway.service
```
