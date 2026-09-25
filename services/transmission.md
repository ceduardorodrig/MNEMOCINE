---
tags: [homelab, service, transmission, download]
---

# Transmission

Lightweight server torrent client.

**Server:** kuaray
**Web Port:** `9091`
**DHT Port:** `51413` (TCP/UDP)
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:9091`

## Stack

| Container | Image | Role |
|---|---|---|
| transmission | linuxserver/transmission:latest | Torrent client |

## Access

`http://kuaray.chimaera-heptatonic.ts.net:9091`

## Integration

- Receives downloads from Lidarr via the *arr stack
- Direct download via the web interface
- Bandwidth-limited so as not to saturate the server

## Secrets

- **RPC password** in the sops store (`TRANSMISSION_RPC_PASSWORD` — the **hash+salt** value from `settings.json`; restoring it verbatim preserves the password). The `settings.json` is **excluded** from the `config-backup` mirror. Restore after a wipe: `inject-secrets.sh` (see `guides/secrets-centralizados.md`).
