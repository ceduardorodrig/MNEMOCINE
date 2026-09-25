---
tags: [homelab, service, searxng, search]
---

# SearXNG

**Private** search engine (meta-search) — no tracking/profiling. It also exposes a **JSON API** for n8n to use in workflows.

**Server:** kavure
**Port:** `8080`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8080`
**JSON:** `http://kavure.chimaera-heptatonic.ts.net:8080/search?q=<termo>&format=json`

> **Deploy (28/08/2026):** config-as-code in `/srv/data/searxng/` (official compose + `.env` via the sops store, `SEARXNG_*` prefix).

## Stack

| Container | Image | Role |
|---|---|---|
| searxng-core | `docker.io/searxng/searxng:latest` | Meta-search |
| searxng-valkey | `docker.io/valkey/valkey:9-alpine` | Cache/limiter |

## Configuration

- `/srv/data/searxng/core-config/settings.yml`: `use_default_settings: true` + **`search.formats: [html, json]`** (JSON enables the API for n8n) + `server.public_instance: false`.
- `.env`: `SEARXNG_SECRET` (sops store — required for the rate limiter/cookies), `SEARXNG_HOST=0.0.0.0`, `SEARXNG_PORT=8080`.

## Usage

- **Browser:** point the search to `http://kavure.chimaera-heptatonic.ts.net:8080/search?q=%s` (private search day to day).
- **n8n:** use an HTTP Request node on `…/search?q=<query>&format=json` (engine "SearXNG") in research/summarizing workflows.
- **Limitations:** engines may rate-limit; the limiter/valkey is in use. Access via the tailnet (not publicly exposed by default).

## Maintenance

- **Update:** kavure's watchtower manages it.
- **Config:** edit `settings.yml` and `docker compose restart searxng-core` (or `up -d`).
- **Mirror:** `config-backup` mirrors `/srv/data/searxng` (`.env` excluded; secret in the store).

## See also
- [[n8n]] — consumes the SearXNG JSON API
- [[monitoring]] — kavure's Prometheus (same host)
