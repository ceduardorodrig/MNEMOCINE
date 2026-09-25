---
tags: [homelab, service, calibre-web, media]
---

# Calibre-web Automated

Ebook server with automatic downloads.

**Server:** kavure (migrated 09/08/2026)
**Port:** `8083`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8083`

## Stack

| Container | Image | Role |
|---|---|---|
| calibre-web-auto | crocodilestick/calibre-web-automated:latest | Ebook server + automatic download |

## Access

`http://kavure.chimaera-heptatonic.ts.net:8083`

## Operation

Web interface for reading and managing ebooks. The "automated" version includes automatic book downloads based on configurable rules.
