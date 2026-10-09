---
tags: [homelab, service, kavita, media]
---

# Kavita

> **⚠️ DECOMMISSIONED (2026-08-10):** Digital comic and manga reader uninstalled from kavure (container removed and local storage `/srv/data/kavita` purged). References decommissioned from dashboards and active operational guides. Preserved for historical inventory tracking.

Historical digital manga, comic book, and eBook library service.

**Host Node:** kavure (migrated 2026-08-09, decommissioned 2026-08-10)  
**Port:** `5000`  
**Web Console:** `http://kuaray.chimaera-heptatonic.ts.net:5000`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `kavita` | `jvmilazz0/kavita:latest` | Manga and eBook reading platform |

## Access

```text
http://kuaray.chimaera-heptatonic.ts.net:5000
```

## Functionality

Specialized digital reading server optimized for:
- Manga collections
- Graphic novels and comics (CBZ, CBR)
- EPUB/PDF formats
- In-browser reading and mobile client synchronization
