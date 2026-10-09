---
tags: [homelab, service, soularr, slskd, lidarr, media, download, kuaray]
---

# Soularr + Slskd

P2P music download pipeline utilizing Soulseek — serves as an acquisition channel for obscure music unavailable through public BitTorrent indexers.

**Host Node:** kuaray  
**Web Consoles:** `http://kuaray.chimaera-heptatonic.ts.net:5030` (slskd) · `:8265` (soularr)  

## Stack

| Container | Base Image | Port | Operational Role |
|---|---|---|---|
| `slskd` | `slskd/slskd:latest` | `5030` | Headless Soulseek client daemon |
| `soularr` | `mrusse08/soularr:latest` | `8265` | Automation bridge connecting Lidarr wanted lists with Soulseek |

## Data Flow (From Soulseek to Lidarr Library)

```text
Lidarr (Wanted Queue)
   │  Soularr queries every 5 minutes
   ▼
soularr  ── Searches Soulseek ──►  slskd ── Downloads ──►  /data/downloads/soulseek/
   │                                                             (Staging storage on kuaray)
   │  Download complete → Dispatches "DownloadedAlbumsScan"
   ▼
Lidarr imports from /data/downloads/soulseek/<album>
   ▼
/data/media/music  (Root storage = NFS share on psicopompo /mnt/BACKUP/media/music)
```

1. Soularr inspects missing album lists from Lidarr (port `8686`, API key from `config.xml`).
2. Dispatches search queries across Soulseek using slskd REST APIs (`:5030`).
3. Slskd downloads incoming files into `/app/downloads/` (`/mnt/storage/data/downloads/soulseek/`).
4. Upon transfer completion, Soularr instructs Lidarr to initiate an album import.
5. Lidarr validates audio tags and transfers assets over NFS into the central library.

## Filesystem Mounts

| Container | Container Mount | Host Path (kuaray) |
|---|---|---|
| `slskd` | `/app/downloads` | `/mnt/storage/data/downloads/soulseek` |
| `soularr` | `/downloads` | `/mnt/storage/data/downloads/soulseek` |
| `lidarr` | `/data` | `/mnt/storage/data` |

## Failed Import Quarantine (`failed_imports.json`)

When automated imports fail (e.g. incomplete downloads or mismatched album releases):
- Soularr moves problematic folders to `failed_imports/` and logs the album in `failed_imports.json` to prevent repetitive download loops.
- To re-trigger an album: purge the corresponding entry in `failed_imports.json` and delete the quarantined folder in `failed_imports/`.

## Manual Import API Reference

To manually force an import of an album via the Lidarr API:

```json
POST /api/v1/command
{
  "name": "ManualImport",
  "importMode": "move",
  "replaceExistingFiles": true,
  "files": [{
    "path": "/data/downloads/soulseek/<album>/01 - Track.flac",
    "artistId": 47,
    "albumId": 326,
    "albumReleaseId": 4206,
    "trackIds": [56103],
    "quality": {"quality": {"id": 10, "name": "FLAC"}, "revision": {"version": 1, "real": 0, "isRepack": false}},
    "indexerFlags": 0,
    "disableReleaseSwitching": false
  }]
}
```

## See Also
- [`lidarr.md`](lidarr.md) — Main music library manager
- [`navidrome.md`](navidrome.md) — Personal audio streaming service
- [`../network/nfs.md`](../network/nfs.md) — Shared storage exports
