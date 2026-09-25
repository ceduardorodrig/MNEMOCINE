---
tags: [homelab, service, comet, download]
---

# Comet

Media server via debrid.

**Server:** kavure
**Port:** `8000`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8000`

## Stack

| Container | Image | Role |
|---|---|---|
| comet | ghcr.io/g0ldyy/comet:latest | Debrid media aggregator |

## Operation

Aggregates content from debrid services (Real-Debrid, AllDebrid, etc.) and exposes it through an API compatible with media players.

## Ports

| Port | Role |
|---|---|
| `8000` | Web API |
