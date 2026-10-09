---
tags: [homelab, service, arandu, scryfall, postgres, psicopompo, kavure]
---

# Arandu — Scryfall Catalog Sync

Synchronizes upstream Scryfall bulk card dumps into the PostgreSQL `arandu_cartas` table (`stenio_db`), powering the Arandu TCG card search engine.

**Binary:** `app/arandu-sync` (Rust) — compiled on **psicopompo** (designated build node, ADR-026)  
**Database:** `sae-core_db` (kavure), accessed over `sae-net` Swarm overlay network  
**Schedule:** Daily at **04:00** via `hl-arandu-sync.timer`  

## Execution Order Rationale

The morning schedule sequence is strictly ordered:

| Time | Systemd Unit | Workload |
|---|---|---|
| **03:00** | `hl-scryfall-mirror` | Fetches Scryfall bulk data and card art images (runs on kavure) |
| **04:00** | `hl-arandu-sync` | Ingests bulk JSON into `arandu_cartas` table |
| **05:00** | `hl-config-backup` | Mirrors node configuration files to NAS storage |

## Host Execution Architecture

The synchronization binary executes on **psicopompo**, not kavure: Binaries are compiled locally on the build machine and kavure lacks a Rust compiler toolchain. Database connectivity is achieved via an ephemeral Docker container attached to the `sae-net` overlay — `DATABASE_URL` targets `db:5432`, the internal Swarm service hostname. **Port 5432 is not exposed on host interfaces**.

## Operation

```console
# Check timer schedule
$ systemctl list-timers hl-arandu-sync.timer

# Manual trigger
$ sudo systemctl start hl-arandu-sync.service
$ journalctl -u hl-arandu-sync -f

# Verify database catalog (inside database container via overlay)
$ SELECT count(*) FROM arandu_cartas;
```

**Health Telemetry:** Wrapper touches `/srv/health/arandu-sync-last-ok`, scraped by `health-files-metrics.sh` (5-minute timer) into Prometheus.  
**Alerting:** Dispatches failure notifications to **ntfy** (`ybytu:8083/backup`).

## Systemd Unit Implementation Details

| Nuance | Detail |
|---|---|
| **`User=edu`** (Non-root) | Decryption key (`~/.config/sops/age/keys.txt`, permissions `0600`) belongs to `edu`; running as root fails `sops` decryption. |
| **`RuntimeMaxSec` Unsupported** | Ignored by systemd on `Type=oneshot` units. Execution timeouts enforced within shell wrapper. |
| **Root-Owned `/srv/health`** | Health file permissions managed via `tmpfiles.d` (`/etc/tmpfiles.d/hl-arandu-sync.conf`), granting write permissions specifically to group `edu`. |
| **Runner Image** | `rust:1-slim-bookworm` (includes `libssl.so.3` out of the box). |
| **Overlay Attachment** | Ephemeral container connects to `sae-net` overlay network to reach internal `db:5432` service. |

## Bugs Remediated on 29/09/2026

The catalog previously contained only **600 of 118,406 cards** while falsely reporting success. Four chained root causes were identified and fixed:

| # | Bug | Impact |
|---|---|---|
| 1 | Scryfall API renamed `download_uri` → **`jsonl_download_uri`** | Raised "URL not found" errors. |
| 2 | Gzipped bulk file **parsed as raw plaintext** | Zero lines deserialized into JSON → reported false success on empty ingest. |
| 3 | `arandu_cartas.id` was `NOT NULL` **without DEFAULT** and omitted from INSERT | Failed on database constraint violations. |
| 4 | Default dataset pointed to `oracle_cards` (~33k unique cards) instead of `default_cards` (~118k printings) | Incomplete artwork indexing. |

**Result:** Ingests 118,448 cards (118,286 with artwork) across 1,052 sets in ~50 seconds. The binary now **hard-fails** if zero cards are parsed.

See [`scryfall-mirror.md`](scryfall-mirror.md) and [`../servers/kavure.md`](../servers/kavure.md).
