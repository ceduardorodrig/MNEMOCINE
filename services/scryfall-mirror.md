---
tags: [homelab, service, scryfall, cache, arandu, psicopompo, kavure, nfs]
---

# Scryfall Mirror

Full mirror of Scryfall (bulk JSON + high-resolution images) for Arandu. Runs on **kavure** (scraper/sync), stores on **psicopompo** (`/mnt/SSD_SATA/scryfall-mirror`) over NFS — psicopompo is only a NAS.

**Status:** 🏗 Being deployed
**Server:** kavure (sync) / psicopompo (NFS storage)
**Storage:** `/mnt/SSD_SATA/scryfall-mirror` — 446GB free (psicopompo SATA SSD)
**Sync:** daily 03:00 via `hl-scryfall-mirror.timer` (outside the 05:00 backup window)
**Consumption:** `sae-core` on kavure reads via `/srv/data/scryfall-mirror` (NFS)

## Architecture

```
psicopompo (/mnt/SSD_SATA/scryfall-mirror)  ←→ NFS →  kavure (/srv/data/scryfall-mirror)
   ↑ NAS (BTRFS)                                   scraper + serve
```

- **JSON:** `default-cards.jsonl.gz` (75MB) → `bulk/` + `.last_updated` (idempotent sync: only downloads if the API's `updated_at` changes)
- **Images:** layout **sharded 1:1 with the Scryfall CDN** — `cards/{formato}/{front|back}/{h1}/{h2}/{uuid}.{ext}`
  (e.g.: `cards/png/front/6/d/6da045f8-....png` = mirror of `cards.scryfall.io/png/front/6/d/...`)
  6 formats (`png/small/normal/large/art_crop/border_crop`) + `back/` for DFC. ~352k files total (~55-90GB).
- **Why sharded:** a flat directory with 20k+ entries over NFS is slow by design (the server sorts the listing — it blows past timeouts). 2-level hex sharding = ~256 dirs per level, instant listing. Same pattern as `.git/objects`.
- **Scryfall API:** bulk `api.scryfall.com` with `User-Agent: AranduTCG/1.0` + `Accept: */*` (mandatory since 08/2024), `/cards/search` 2/s. The `*.scryfall.io` CDN has no rate limit. A 24h cache is mandatory (Scryfall requires it).

## NFS + Subvolume BTRFS

**Dedicated subvolume** `@scryfall` (stable filehandles under heavy churn + snapper snapshots):

```
btrfs subvolume create /mnt/SSD_SATA/@scryfall
UUID=2f59eee5-... /mnt/SSD_SATA/scryfall-mirror btrfs subvol=@scryfall,compress=zstd:3,ssd,noatime,discard=async 0 0
```

**psicopompo `/etc/exports`:**
```
/mnt/SSD_SATA/scryfall-mirror 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

**kavure `/etc/fstab`:**
```
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

Pattern `soft` + `x-systemd.automount` (never `hard`). See `network/nfs.md`.

**⚠️ Lesson (31/08):** a flat `cards/{uuid}/` directory with 19,917 entries made `ls`/`du` over NFS hang in D-state and the service blow past `TimeoutStartSec` (TERM at 03:30). Fix: 1:1 CDN sharding + service hardening. If listing the mirror is slow, check the entry count per dir (`find cards -maxdepth 4 -type d`).

## Service on kavure

`/srv/data/scryfall-mirror/` is consumed directly by `sae-core` (`ARANDU_CACHE_DIR=/srv/data/scryfall-mirror`). The sync runs as a systemd timer on kavure:

- `hl-scryfall-mirror.service` (Type=oneshot, `RuntimeMaxSec=2h`, `Nice=19`, `IOSchedulingClass=idle`, `Restart=on-failure`, `OnFailure=notify-backup-failure@`)
- `hl-scryfall-mirror.timer` (OnCalendar=*-*-* 03:00, Persistent=true)

The `scryfall-sync` script (`/usr/local/bin`): checks `updated_at` against `bulk/.last_updated` (idempotent), downloads `default-cards.jsonl.gz` if new, writes the health file `/srv/health/scryfall-mirror-last-ok`. **Never lists `cards/`** (it only touches `bulk/`, a small dir).

**Prefetch** (`/tmp/prefetch-shard.py` → local `/var/log/scryfall-prefetch.log`): resumable (skip if exists), 4 workers, `--limit-rate 2M`, `nice -19 ionice -c3`. On-demand also works: a cache miss in the front downloads 1 image via `get_or_cache_card_image` (sharded path, CDN fallback).

## Backup

The cache is recreatable via the CDN — it does **not** need an off-box copy. Only the timer/script configs go to `/mnt/BACKUP/configs-homelab` via `hl-config-backup` at 05:00.

## References

- `services/arandu.md` — Arandu service (consumes this mirror)
- `app/core/arandu_scryfall.py` — `CACHE_DIR`, `User-Agent`, rate limit
- Scryfall docs: `api.scryfall.com/bulk-data`, `scryfall.com/docs/api/rate-limits`
