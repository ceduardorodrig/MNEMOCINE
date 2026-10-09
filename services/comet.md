---
tags: [homelab, service, comet, download]
---

# Comet

Debrid stream scraping and metadata indexing service.

**Host Node:** kavure  
**Port:** `8000`  
**Web Console:** `http://kavure.chimaera-heptatonic.ts.net:8000`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `comet` | `ghcr.io/g0ldyy/comet:latest` | Debrid torrent scraper and media indexer |

## Functionality

Aggregates stream metadata from debrid providers (Real-Debrid, AllDebrid, etc.) and presents a standard API endpoint consumed by media players such as Stremio.

## Port Matrix

| Port | Protocol | Purpose |
|---|---|---|
| `8000` | TCP | REST API and configuration endpoint |
