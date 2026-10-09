---
tags: [homelab, service, arandu, tcg, sumaenima, nfs, cache]
---

# Arandu

TCG (Trading Card Game) digital platform integrated into Sumænimá HUB. Third pillar of the Portal Aggregator: Social binder + Collaborative deck builder + Player radar.

**Status:** 🔶 Planned — MVP v0.1 scheduled for Sumænimá Phase 4 migration  
**Server:** kavure (Swarm `sae-core` — shared application stack with Sumænimá)  
**Initial Domain:** `arandu.chimaera-heptatonic.ts.net`  
**Future Public Domain:** `arandu.app` (subject to availability)  
**Etymology:** Arandu — Guarani: *wisdom, accumulated knowledge*  

## Image Caching Engine — SATA SSD on Psicopompo

Arandu utilizes an intelligent LRU card image cache (Scryfall) hosted on **psicopompo's SATA SSD**, exported via NFS to kavure.

| Property | Details |
|---|---|
| **Drive** | Kingston A400 448GB SATA SSD — `/mnt/SSD_SATA` |
| **Directory** | `/mnt/SSD_SATA/scryfall-mirror/cards/{id}/{format}.jpg\|png` (Scryfall-compatible structure) |
| **Capacity** | ~446GB (99% free as of 2026-08-22) — `default_cards` high-res ≈ 33GB, `all_cards` ≈ 88GB |
| **Policy** | Full mirror + On-demand LRU: Frontend search triggers cache miss → fetch CDN `c1.scryfall.com` → persist locally; bulk `default-cards.jsonl.gz` updates database daily at 03:00 via `hl-scryfall-mirror.timer` (kavure) |
| **Formats** | `small/normal/large/png/art_crop/border_crop` (6) + `card_faces[1]` back face — `png` 744×1040 preferred |
| **Prefetch** | On-demand (single image) + daily bulk (database & pricing) + `xargs -P8` parallel prefetch |

**Storage Allocation Rationale:**

| Drive | Mount | Free | Decision |
|---|---|---|---|
| NVMe PCI 1.9TB | `/mnt/NVME_PCI` | 676GB | ❌ 64% utilized (codebase, models, vault) |
| **SSD SATA 448GB** | `/mnt/SSD_SATA` | **446GB** | ✅ **99% free — optimal dedicated target** |
| HDD SATA 932GB | `/mnt/HDD_SATA` | 713GB | ❌ High seek latency over NFS |
| HDD Backup 932GB | `/mnt/BACKUP` | 681GB | ❌ Do not mix volatile caches with disaster recovery |

### NFS Export Configuration

**psicopompo `/etc/exports`:**
```bash
/mnt/SSD_SATA/scryfall-mirror 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
exportfs -arv
```

**kavure `/etc/fstab`:**
```bash
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

> Adheres strictly to the canonical Tailnet NFS standard: `soft,timeo=30,retrans=2` + `x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s`. See [`network/nfs.md`](../network/nfs.md).

### Image Proxy Flow

```
GET /api/arandu/cards/{scryfall_id}/image?format=normal
  1. Inspect local sharded mirror: /srv/data/scryfall-mirror/cards/{fmt}/{face}/{h1}/{h2}/{id}.{ext}
  2. Cache miss: Fetch GET https://cards.scryfall.io/normal/... → persist to disk → return
  3. Cache hit: Stream local cached file (zero network latency)
```

## Scryfall Sync Cadence (04:00 Daily)

```bash
# Fetch Scryfall bulk dataset JSON (~300MB)
curl -L https://data.scryfall.io/oracle-cards/oracle-cards-YYYYMMDD.json -o /tmp/scryfall-bulk.json

# Ingest into PostgreSQL cards table
python3 manage.py scryfall_sync --file /tmp/scryfall-bulk.json
```

## Storage Footprint Projections

| Scope | Cards | Normal JPEG | PNG |
|---|---|---|---|
| Single Player Collection (500 cards) | 500 | ~40 MB | ~140 MB |
| Average Binder (2,000 cards) | 2,000 | ~160 MB | ~560 MB |
| All Unique Printings | ~87,000 | ~7 GB | ~24 GB |
| All Unique Oracle Entries | ~28,000 | ~2 GB | ~8 GB |

The cache initializes empty and scales organically with user activity.

## Dependencies

- PostgreSQL 16 (`sae-core` on kavure)
- Valkey 8 (`sae-core` on kavure) — real-time deck co-op via Pub/Sub
- NFS on psicopompo (`/mnt/SSD_SATA/scryfall-mirror`) — image asset cache (see [scryfall-mirror.md](scryfall-mirror.md))
- Scryfall API (free tier, unauthenticated bulk dumps)
- Google OAuth (scopes: `openid email profile`)
- PostGIS (planned for Phase 4 v0.2 player radar)

## Product Specification

Consult the complete Product Requirements Document (PRD) in **Sumænimá Hub** repository (`docs/arandu-prd.md`).

## See also
- [[steniobot]] — Shared sae-core infrastructure stack
- [[kavure]] — Production node running Arandu backend
- [[psicopompo]] — Storage node providing NFS image cache
- [[network/nfs]] — Tailnet NFS configuration standards
