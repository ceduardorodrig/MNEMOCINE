---
tags: [homelab, service, calibre-web, media]
---

# Calibre-web Automated

Digital book cataloging and automated eBook ingestion server.

**Host Node:** kavure (migrated 2026-08-09)  
**Port:** `8083`  
**Web Console:** `http://kavure.chimaera-heptatonic.ts.net:8083`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `calibre-web-auto` | `crocodilestick/calibre-web-automated:latest` | eBook management, reader UI, and automated book ingestion |

## Access

```text
http://kavure.chimaera-heptatonic.ts.net:8083
```

## Functionality

Provides an interactive browser-based reading interface and catalog organizer for eBooks. The automated distribution automates book downloads and library categorization based on configurable rule pipelines.
