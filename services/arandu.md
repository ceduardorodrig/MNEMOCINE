---
tags: [homelab, service, arandu, tcg, sumaenima, nfs, cache]
---

# Arandu

TCG (Trading Card Game) platform integrated with the Sumænimá HUB. Third pillar of the Aggregator Portal: social digital binder + co-op Deck Builder + player Radar.

**Status:** 🔶 Planned — MVP v0.1 expected for Phase 4 of the Sumænimá migration
**Server:** kavure (Swarm `sae-core` — same stack as Sumænimá)
**Initial domain:** `arandu.chimaera-heptatonic.ts.net`
**Future public domain:** `arandu.app` (availability to be checked)
**Name:** Arandu — Guarani: *wisdom, accumulated knowledge*

## Image Cache — psicopompo's SATA SSD

Arandu uses an intelligent LRU card image cache (Scryfall) on **psicopompo's SATA SSD**, served over NFS to kavure.

| Item | Detail |
|---|---|
| **Disk** | Kingston A400 448GB SATA SSD — `/mnt/SSD_SATA` |
| **Directory** | `/mnt/SSD_SATA/scryfall-mirror/cards/{id}/{formato}.jpg\|png` (full mirror, Scryfall-compatible) |
| **Available** | ~446GB (99% free in 2026-08-22) — high-res `default_cards` ≈ 33GB, `all_cards` ≈ 88GB |
| **Policy** | Full mirror + on-demand LRU: a search/view in the front triggers a cache miss → CDN `c1.scryfall.com` → persisted; the 74M bulk `default-cards.jsonl.gz` updates the DB daily at 03:00 via `hl-scryfall-mirror.timer` (kavure) + a manifest diff for new art |
| **Formats** | `small/normal/large/png/art_crop/border_crop` (6) + `card_faces[1]` back — `png` 744×1040 whenever possible |
| **Download** | On-demand (1 image) + daily bulk (DB + prices) + parallel `xargs -P8` for a 30k prefetch |

**Why SSD_SATA and not the other disks:**

| Disk | Mount | Free | Decision |
|---|---|---|---|
| NVMe PCI 1.9TB | `/mnt/NVME_PCI` | 676GB | ❌ Already 64% used (code, models, vault) |
| **448GB SATA SSD** | `/mnt/SSD_SATA` | **446GB** | ✅ **99% free — ideal** |
| 932GB SATA HDD | `/mnt/HDD_SATA` | 713GB | ❌ Too slow for images over NFS |
| 932GB Backup HDD | `/mnt/BACKUP` | 681GB | ❌ Don't mix cache with backup |

### NFS export (to configure in Phase 4)

**psicopompo `/etc/exports` — add:**
```bash
/mnt/SSD_SATA/scryfall-mirror 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
exportfs -arv
```

**kavure `/etc/fstab` — add:**
```bash
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

> Follow the tailnet's canonical NFS pattern: `soft,timeo=30,retrans=2` + `x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s`. See [`network/nfs.md`](../network/nfs.md).

### Image endpoint (FastAPI)

```
GET /api/arandu/cards/{scryfall_id}/image?format=normal
  1. Verifica mirror local sharded: /srv/data/scryfall-mirror/cards/{fmt}/{face}/{h1}/{h2}/{id}.{ext}
  2. Cache miss: GET https://cards.scryfall.io/normal/... → salva → retorna
  3. Cache hit: retorna imagem local (latência ~0)
```

## Scryfall Sync (cron 04:00 daily)

```bash
# Download bulk data JSON (~300MB)
curl -L https://data.scryfall.io/oracle-cards/oracle-cards-YYYYMMDD.json -o /tmp/scryfall-bulk.json

# Upsert no PostgreSQL (tabela cards)
python3 manage.py scryfall_sync --file /tmp/scryfall-bulk.json
```

## Cache Storage Estimates

| Scope | Count | normal JPEG | PNG |
|---|---|---|---|
| Single player (500 cards) | 500 | ~40 MB | ~140 MB |
| Average collection (2,000 cards) | 2,000 | ~160 MB | ~560 MB |
| All unique printings | ~87,000 | ~7 GB | ~24 GB |
| All unique oracles | ~28,000 | ~2 GB | ~8 GB |

The cache starts empty and grows only with what is actually being used.

## Dependencies

- PostgreSQL 16 (sae-core — kavure)
- Valkey 8 (sae-core — kavure) — co-op decks via Pub/Sub
- psicopompo NFS (`/mnt/SSD_SATA/scryfall-mirror`) — image cache (see [scryfall-mirror.md](scryfall-mirror.md))
- Scryfall API (free, no mandatory authentication)
- Google OAuth auth (minimum scopes: `openid + email + profile`)
- PostGIS (to be added in Phase 4 v0.2, for the Map/Radar)

## Full PRD

See the product spec (PRD) in the **Sumænimá Hub** repository (`docs/arandu-prd.md`).

## See also

- [[steniobot]] — Shared sae-core stack
- [[kavure]] — Server where Arandu runs in production
- [[psicopompo]] — Server that serves the image cache over NFS
- [[network/nfs]] — Tailnet NFS configuration
