---
tags: [homelab, service, soularr, slskd, lidarr, media, download, kuaray]
---

# Soularr + Slskd

Music download via Soulseek — an alternative for music not found in public torrents (Prowlarr/Transmission).

**Server:** kuaray
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:5030` (slskd) · `:8265` (soularr)

## Stack

| Container | Image | Port | Role |
|---|---|---|---|
| slskd | slskd/slskd:latest | `5030` | Soulseek client (downloads files) |
| soularr | mrusse08/soularr:latest | `8265` | Lidarr → Soulseek bridge (every 5 min) |

## Flow (how the music reaches Lidarr)

```
Lidarr (wanted/missing)
   │  soularr consulta a cada 5 min
   ▼
soularr  ── busca no Soulseek ──►  slskd ── baixa ──►  /data/downloads/soulseek/
   │                                                       (bind kuaray)
   │  download completo → dispara "DownloadedAlbumsScan"
   ▼
Lidarr importa de /data/downloads/soulseek/<álbum>
   ▼
/data/media/music  (root folder = NFS → psicopompo /mnt/BACKUP/media/music)
```

1. Soularr reads Lidarr's wanted/missing (port `8686`, api_key from `config.xml`).
2. Searches Soulseek via slskd's API (`:5030`, the bridge's api_key).
3. Slskd downloads to `/app/downloads/` = `/mnt/storage/data/downloads/soulseek/` (bind).
4. On completion, soularr triggers Lidarr's **DownloadedAlbumsScan** pointing at the folder.
5. Lidarr imports to the root folder `/data/media/music` (NFS → psicopompo) and Navidrome consumes it.

## Paths and mounts

| Container | Mount | Host (kuaray) |
|---|---|---|
| slskd | `/app/downloads` | `/mnt/storage/data/downloads/soulseek` |
| soularr | `/downloads` | `/mnt/storage/data/downloads/soulseek` |
| lidarr | `/data` | `/mnt/storage/data` (sees the same folder as `/data/downloads/soulseek`) |

Configs:
- slskd: `/DATA/AppData/slskd/slskd.yml` + `/DATA/AppData/slskd/data/`
- soularr: `/DATA/AppData/soularr/config/config.ini` (hosts, api_keys, `rename_tracks`) + `soularr.log` + `failed_imports.json`

## Denylist of failed imports (`failed_imports.json`)

- When the automatic import fails, soularr **moves the folder** to `failed_imports/` and **denylists** the album (it does not retry automatically).
- Common failures (the Soulseek download does not match the album exactly):
  - **`Has missing tracks`** — incomplete download (album tracks are missing).
  - **`Has unmatched tracks`** — extra/duplicate files that do not match (multi-disc, bonus tracks).
  - **Wrong album** — a download that is not the work (e.g. "Flying Lotus - 1983" contained the album *Pooh - Tropico del nord*).
- To unblock: remove the entry from `failed_imports.json` (soularr will try again) and delete the folder from `failed_imports/`.
- Clearing the whole denylist is safe: complete albums drop out of wanted (soularr does not re-search) and partial albums get re-searched to complete.

## Manual import via API (reference)

Lidarr's `ManualImport` command requires **all** fields per file — omitting any causes `Artist with ID 0 does not exist`:

```json
POST /api/v1/command
{
  "name": "ManualImport",
  "importMode": "move",
  "replaceExistingFiles": true,
  "files": [{
    "path": "/data/downloads/soulseek/<álbum>/01 - Track.flac",
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

- Preview (read-only, no import): `GET /api/v1/manualimport?folder=/data/downloads/soulseek/<álbum>` — returns files, matched `tracks`, `quality` and `rejections`.
- Using explicit `trackIds` allows a **partial** import (the album stays monitored → soularr completes it later).
- Files with no `tracks` in the preview (duplicates) must be **skipped** — do not include them in the payload.
- API import can be **slow** (copy to the NFS): issue it and wait for the status (`GET /api/v1/command/{id}`) until `completed`.

## Troubleshooting

- **"Indexer disabled till ... 429"** in the Lidarr log: Prowlarr request rate limit (TPB/Knaben). Automatic disable; it comes back on its own.
- **"Artists' root folder (/data/media/music) doesn't exist"**: if the folder really exists, it is a transient warning (NFS). Check with `docker exec lidarr ls /data/media/music`.
- **Transmission "No data found"**: torrents at 100% whose data was wiped from the disk (already imported). Remove them from Transmission.
- **Folders stuck in the soularr root**: orphan downloads that soularr ignores (denylisted album, or a download not started by soularr). Move to `failed_imports/` or import manually.
- **⚠️ Never delete a download folder while Lidarr is importing** — the import uses `move` + `replaceExistingFiles` and can delete library files midway (lesson from the 2ª Via incident on 07/08/2026).

## Relevant history

- **2026-08-07**: general cleanup — duplicates removed from `failed_imports/`; manual API imports of Damien Rice 9 (11/11) and Pink Floyd A Saucerful of Secrets (7/7); denylist cleared and soularr restarted (unstuck the queue). Partial albums (Massive Attack Collected, Gorillaz Demon Days) re-downloaded automatically by soularr to complete.
