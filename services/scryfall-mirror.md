---
tags: [homelab, service, scryfall, cache, arandu, psicopompo, kavure, nfs]
---

# Scryfall Mirror

Complete offline mirror of Scryfall data (bulk card JSON data and high-resolution card artwork) serving Arandu. Operates on **kavure** (ingestion, scraper, and sync daemons) storing datasets on **psicopompo** (`/mnt/SSD_SATA/scryfall-mirror`) over NFS.

**Operational Status:** Active  
**Server:** kavure (sync and ingestion daemons) / psicopompo (dedicated NFS storage provider)  
**Storage Target:** `/mnt/SSD_SATA/scryfall-mirror` (Btrfs subvolume `@scryfall`)  
**Sync Window:** Daily at 03:00 BRT via `hl-scryfall-mirror.timer`  
**Consumer Service:** `sae-core` on kavure parses datasets via `/srv/data/scryfall-mirror`  

## Architectural Overview

```text
psicopompo (/mnt/SSD_SATA/scryfall-mirror)  ←── NFSv4 ──→  kavure (/srv/data/scryfall-mirror)
   ↑ Central NAS Storage (Btrfs)                                Scraper & API consumer
```

- **Bulk JSON:** `default-cards.jsonl.gz` (75 MB) stored under `bulk/` with `.last_updated` timestamps (idempotent synchronization; only downloads when upstream Scryfall API `updated_at` increments).
- **Artwork Layout (1:1 Sharded CDN Mapping):** `cards/{format}/{front|back}/{h1}/{h2}/{uuid}.{ext}`  
  Maps directly to `cards.scryfall.io/png/front/6/d/...` across 6 distinct image formats (`png`, `small`, `normal`, `large`, `art_crop`, `border_crop`) alongside reverse card faces (`back/`) for dual-faced cards (~352k files totaling 55–90 GB).
- **Why Sharded Directory Trees Matter:** Storing 20k+ flat image entries in a single directory across NFS leads to kernel D-state locks during directory listing lookups. Two-tier hexadecimal sharding (~256 directories per tier) ensures instantaneous directory traversal identical to the Git object database design.

## Dedicated Btrfs Subvolume & NFS Export

Subvolume `@scryfall` configured on psicopompo:
```bash
btrfs subvolume create /mnt/SSD_SATA/@scryfall
```

Export on psicopompo (`/etc/exports`):
```text
/mnt/SSD_SATA/scryfall-mirror 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

Mount on kavure (`/etc/fstab`):
```text
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

## Systemd Automation Daemons (kavure)

Ingestion pipelines execute under native systemd units:
- `hl-scryfall-mirror.service` (Type=oneshot, `RuntimeMaxSec=2h`, `Nice=19`, `IOSchedulingClass=idle`, `Restart=on-failure`, `OnFailure=notify-backup-failure@`)
- `hl-scryfall-mirror.timer` (Runs daily at 03:00 BRT, `Persistent=true`)

The native sync utility touches `/srv/health/scryfall-mirror-last-ok` upon zero-exit completion to inform health check monitors.

## See Also
- [`arandu.md`](arandu.md) — Arandu service architecture
- [`../network/nfs.md`](../network/nfs.md) — NFS storage network configurations
- [`../backups/strategy.md`](../backups/strategy.md) — Central backup policies
