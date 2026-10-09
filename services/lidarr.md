---
tags: [homelab, service, lidarr, media, download, kuaray]
---

# Lidarr

Automated music collection manager and acquisition pipeline.

**Host Node:** kuaray  
**Port:** `8686`  
**Web Console:** `http://kuaray.chimaera-heptatonic.ts.net:8686`  

## Stack

| Container | Base Image | Operational Role |
|---|---|---|
| `lidarr` | `linuxserver/lidarr:latest` | Music library management and automated metadata indexing |
| `transmission` | `linuxserver/transmission:latest` | BitTorrent download client |
| `prowlarr` | `linuxserver/prowlarr:latest` | Torrent and Usenet indexer proxy |
| `soularr` | `mrusse08/soularr:latest` | Bridge integrating Lidarr missing queues with Soulseek |
| `slskd` | `slskd/slskd:latest` | Headless Soulseek client daemon |
| `navidrome` | `deluan/navidrome:latest` | Audio streaming frontend (kavure) |

## Physical File Pipeline & Storage Boundaries

```text
1) ACQUISITION — Local disk on kuaray (/dev/sdb1)
   - Transmission  → /mnt/storage/data/torrents/lidarr/      (Torrents via Prowlarr)
   - slskd/soularr → /mnt/storage/data/downloads/soulseek/   (Soulseek P2P)

2) AUTOMATED IMPORT (Lidarr) — Cross-filesystem copy and purge
   - soularr triggers DownloadedAlbumsScan / ProcessMonitoredDownloads
   - Moves files from /mnt/storage/data/{torrents,downloads}/<album>
     → /mnt/storage/data/media/music/<artist>/<album>        (NFS export on psicopompo)

3) CANONICAL LIBRARY — Primary NAS storage on psicopompo (Btrfs)
   - /mnt/BACKUP/media/music (NFS export mounted on kuaray at /mnt/nas/media/music)
   - Navidrome reads from this target; Syncthing maintains cold backups.
```

> ⚠️ **Cross-Filesystem Movement:** Downloads stage on kuaray while canonical library directories reside on psicopompo over NFS. Every imported release undergoes a network copy-and-delete sequence rather than an instantaneous hardlink. This trade-off isolates library storage on healthy NAS pools away from aging disks.

## Container Volume Bindings

| Container | Internal Path | Host Path (kuaray) |
|---|---|---|
| `lidarr` | `/config` | `/DATA/AppData/lidarr/config` |
| `lidarr` | `/data` | `/mnt/storage/data` (Accesses staging downloads) |
| `lidarr` | `/data/torrents` | `/mnt/storage/data/torrents` |
| `transmission` | `/data/torrents` | `/mnt/storage/data/torrents` |
| `slskd` | `/app/downloads` | `/mnt/storage/data/downloads/soulseek` |
| `soularr` | `/downloads` | `/mnt/storage/data/downloads/soulseek` |
| `navidrome` | `/music` | `/srv/data/navidrome/music` (on kavure) |

- **Lidarr Root Folder:** `/data/media/music` (Mounts NFS share from psicopompo).
- **Transmission Client Integration:** Targets `100.94.209.99:9091`, urlBase `/transmission/`, category `lidarr`.
- **Soularr Config:** `/DATA/AppData/soularr/config/config.ini` — see [`soularr-slskd.md`](soularr-slskd.md).

## Operational Workflow

1. Artists are marked as monitored in Lidarr → missing discography items populate the wanted queue.
2. **Soularr** scans missing albums every 5 minutes, searches the Soulseek P2P network, enqueues matching files in slskd, and invokes Lidarr import APIs upon completion.
3. **Lidarr + Prowlarr + Transmission** handles BitTorrent feeds (RSS feeds and automatic searches).
4. Completed releases transfer over NFS to the central library pool for immediate streaming via Navidrome.

## Troubleshooting

- **`/data/torrents/lidarr` Warning:** The target path must exist on the host filesystem (`/mnt/storage/data/torrents/lidarr`, owned by user `kuaray`).
- **Rescan Stalls on Wi-Fi:** Extensive full-library scans over wireless connections bottleneck throughput. Prioritize targeted `RefreshArtist` actions until dedicated Gigabit Ethernet cabling is connected.
- **API Secret Store:** The 32-character Lidarr API key is secured inside SOPS (`LIDARR_API_KEY`).

## See Also
- [`soularr-slskd.md`](soularr-slskd.md) — Soulseek integration bridge
- [`navidrome.md`](navidrome.md) — Music playback server
- [`../network/nfs.md`](../network/nfs.md) — NFS storage architecture
