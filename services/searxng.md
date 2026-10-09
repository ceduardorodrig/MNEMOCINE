---
tags: [homelab, service, searxng, search]
---

# SearXNG

**Privacy-respecting** metasearch engine — zero tracking or user profiling. Also exposes a **JSON API** consumed by n8n automation workflows.

**Server:** kavure  
**Port:** `8080`  
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8080`  
**JSON Endpoint:** `http://kavure.chimaera-heptatonic.ts.net:8080/search?q=<query>&format=json`  

> **Deployment (28/08/2026):** Config-as-code at `/srv/data/searxng/` (official compose + `.env` managed via sops store, prefix `SEARXNG_*`).

## Stack

| Container | Image | Function |
|---|---|---|
| searxng-core | `docker.io/searxng/searxng:latest` | Metasearch aggregator |
| searxng-valkey | `docker.io/valkey/valkey:9-alpine` | Query caching & rate limiting |

## Configuration

- `/srv/data/searxng/core-config/settings.yml`: `use_default_settings: true` + **`search.formats: [html, json]`** (JSON enables programmatic API queries for n8n) + `server.public_instance: false`.
- `.env`: `SEARXNG_SECRET` (sops store — mandatory for cookies/rate-limiter hashing), `SEARXNG_HOST=0.0.0.0`, `SEARXNG_PORT=8080`.

## Usage

- **Browser Search:** Configure default search provider to `http://kavure.chimaera-heptatonic.ts.net:8080/search?q=%s`.
- **n8n Workflows:** Execute HTTP Request nodes targeting `…/search?q=<query>&format=json` (engine "SearXNG") in research pipelines.
- **Constraints:** Upstream search engines may throttle requests; local Valkey cache mitigates duplicate queries. Access strictly over tailnet (private by design).

## Maintenance

- **Updates:** Kavure Watchtower manages image updates.
- **Configuration:** Edit `settings.yml` and execute `docker compose restart searxng-core` (or `up -d`).
- **Backup Mirror:** `config-backup` mirrors `/srv/data/searxng` (`.env` excluded; secret persisted in sops).

## See also
- [[n8n]] — Consumes SearXNG JSON API
- [[monitoring]] — Prometheus on kavure (same host)