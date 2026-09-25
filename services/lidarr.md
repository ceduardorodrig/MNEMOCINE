---
tags: [homelab, service, lidarr, media, download, kuaray]
---

# Lidarr

Management and automatic music downloading.

**Server:** kuaray
**Port:** `8686`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:8686`

## Stack

| Container | Image | Role |
|---|---|---|
| lidarr | linuxserver/lidarr:latest | Music library management |
| transmission | linuxserver/transmission:latest | Torrent download (Prowlarr) |
| prowlarr | linuxserver/prowlarr:latest | Indexers |
| soularr | mrusse08/soularr:latest | Lidarr → Soulseek bridge |
| slskd | slskd/slskd:latest | Soulseek client |
| navidrome | deluan/navidrome:latest | Library player |

## Physical file flow (important)

```
1) DOWNLOAD — disco LOCAL do kuaray (/dev/sdb1)
   - Transmission  → /mnt/storage/data/torrents/lidarr/      (torrents via Prowlarr)
   - slskd/soularr → /mnt/storage/data/downloads/soulseek/   (Soulseek)
   ├── rápido (disco local), porém /dev/sdb1 = HD com histórico de bad sectors (dados transitórios)

2) IMPORT AUTOMÁTICO (Lidarr) — copy+delete cross-filesystem
   - soularr dispara DownloadedAlbumsScan / ProcessMonitoredDownloads
   - move /mnt/storage/data/{torrents,downloads}/<álbum>
     → /mnt/storage/data/media/music/<artist>/<álbum>   (= NFS → psicopompo)

3) BIBLIOTECA — HD do psicopompo (btrfs, saudável)
   - /mnt/BACKUP/media/music  (NFS export, montado no kuaray em /data/media/music)
   - Navidrome lê daqui; Syncthing (folder `backup`) espelha p/ kuaray
```

> ⚠️ **No hardlinks/atomic move:** downloads (kuaray) and library (NFS/psicopompo) are on **different filesystems** → every import is a **copy+delete over NFS** (slow). This is a **deliberate trade-off**: the library was moved to the NAS because kuaray's HDD has bad sectors. See [`network/nfs.md`](../network/nfs.md) (performance/WiFi note).

## Internal paths (containers)

| Container | Mount | Host (kuaray) |
|---|---|---|
| lidarr | `/config` | `/DATA/AppData/lidarr/config` |
| lidarr | `/data` | `/mnt/storage/data` (sees downloads + music) |
| lidarr | `/data/torrents` | `/mnt/storage/data/torrents` |
| transmission | `/data/torrents` | `/mnt/storage/data/torrents` |
| slskd | `/app/downloads` | `/mnt/storage/data/downloads/soulseek` |
| soularr | `/downloads` | `/mnt/storage/data/downloads/soulseek` |
| navidrome | `/music` | `/mnt/storage/data/media/music` |

- **Lidarr root folder:** `/data/media/music` (= NFS → psicopompo).
- **Transmission download client:** host `100.94.209.99:9091`, urlBase `/transmission/`, category `lidarr` → downloads in `/data/torrents/lidarr/`. **No remote path mapping** (Lidarr and Transmission on the same machine).
- **Soularr:** `config.ini` in `/DATA/AppData/soularr/config/` (hosts/api_keys) — see [`soularr-slskd.md`](soularr-slskd.md).

## Operation (automatic)

1. An artist marked as monitored in Lidarr → missing albums become `wanted/missing`.
2. **Soularr** (every 5 min) reads the wanted/missing, searches Soulseek, queues on slskd and, on completion, triggers the import in Lidarr.
3. **Lidarr + Prowlarr + Transmission** covers torrents (RSS/search) — subject to indexer rate limits (TPB/Knaben → temporarily disables, auto-recovers).
4. The import moves to the NFS library; Navidrome consumes it.

**Only manual steps:** adding artists and, when a bad download lands on soularr's denylist, clearing `failed_imports.json` (see `soularr-slskd.md`).

## Troubleshooting

- **`/data/torrents/lidarr` "does not appear to exist"**: the directory must exist on the host (`/mnt/storage/data/torrents/lidarr`, owner `kuaray:kuaray`) — it is the destination for Transmission's category. If the warning persists in the UI, revalidate the client (test) or restart the container.
- **Full rescans (`RescanFolders`) hang on WiFi**: the NFS library over kuaray's WiFi link is slow/unstable (3.6 MB/s). Avoid a full rescan; use a targeted `RefreshArtist` (also slow, but it progresses). Once kuaray has an **ethernet cable**, a clean rescan reconciles the DB.
- **Album `0/x` in the DB but files on disk**: reconciliation pending from the rescan (DB state oscillates with slow NFS). Files intact; Navidrome plays normally.
- **`Artist with ID 0` in ManualImport**: the API payload requires `artistId` + `albumReleaseId` (on top of `albumId`/`trackIds`) — see `soularr-slskd.md`.
- **Slow import**: copy+delete over NFS/WiFi; see `network/nfs.md` (async + ethernet).

## Relevant history

- **2026-08-07:** general cleanup — 131 dead torrents removed from Transmission, queue zeroed, duplicates/`failed_imports` deleted, `failed_imports.json` (denylist) cleared, manual API imports (Damien Rice 9, Pink Floyd), soularr unstuck.

## Secrets

- **API key** in the sops store (`LIDARR_API_KEY`, 32-char — source `config.xml` `<ApiKey>`). The `config.xml` is **excluded** from the `config-backup` mirror (it never goes to the NAS). Restore after a wipe: `inject-secrets.sh` (see `guides/secrets-centralizados.md`).
