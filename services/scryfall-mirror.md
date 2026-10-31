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

## Architectural Decision: Pipeline & Download Isolation (scryfall-sync vs scryfall-prefetch)

**Date:** 2026-10-30  
**Status:** Accepted (Conscious Architectural Decision)  
**Context:**  
Both `scryfall-sync` (bulk dataset catalog updater) and `scryfall-prefetch` (card artwork cache warmer) share the pattern of atomic disk writes (`<dest>.part` followed by atomic `rename`), triggering low-density AST token warnings in static analysis (Stenio `ARCH-DRY-DUPLICATION` Warning).

**Decision:**  
Intentionally maintain `scryfall-sync` and `scryfall-prefetch` as decoupled, independent Rust binaries without a shared library or unified download abstraction.

**Rationale:**
1. **Divergent I/O Profiles:** `scryfall-prefetch` downloads small individual image assets (tens of KB to a few MB) buffered into memory (`resp.bytes().await`), whereas `scryfall-sync` streams multi-gigabyte card dumps (`bulk/default-cards.jsonl.gz`) in chunks (`resp.bytes_stream()`) to prevent host memory exhaustion.
2. **Zero Blast Radius for Arandu Ingestion:** Daily catalog ingestion (`hl-arandu-sync` at 04:00) requires a strictly valid, uncorrupted dataset. Keeping `scryfall-sync` completely isolated from image prefetching guarantees that artwork scraping heuristics never introduce silent regressions into database ingestion.
3. **Governance & Gate Compliance:** The shared HTTP request and rename sequence reflects standard idiomatic Rust. Stenio Sentinel classifies this low-density overlap as non-blocking `Severity::Warning`, confirming full release compliance (`[GATE PASSED]` with 0 blocking errors).

## See Also
- [`arandu.md`](arandu.md) — Arandu service architecture
- [`../network/nfs.md`](../network/nfs.md) — NFS storage network configurations
- [`../backups/strategy.md`](../backups/strategy.md) — Central backup policies
