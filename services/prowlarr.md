---
tags: [homelab, service, prowlarr, download]
---

# Prowlarr

Unified indexer for the *arr stack.

**Server:** kuaray
**Port:** `9696`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:9696`

## Stack

| Container | Image | Role |
|---|---|---|
| prowlarr | linuxserver/prowlarr:latest | Indexer management |

## Integration

Feeds the indexers for:
- Lidarr (music)
- Other *arr apps as needed

## Operation

1. Centralizes multiple torrent/usenet indexers
2. Syncs automatically with the connected *arr apps
3. Uses Flaresolverr for sites protected by Cloudflare

## Secrets

- **API key** in the sops store (`PROWLARR_API_KEY`, 32-char — source `config.xml` `<ApiKey>`). The `config.xml` is **excluded** from the `config-backup` mirror (it never goes to the NAS). Restore after a wipe: `inject-secrets.sh` (see `guides/secrets-centralizados.md`).
