---
tags: [homelab, service, scryfall, cache, arandu, psicopompo, kavure, nfs]
---

# Scryfall Mirror

Mirror completo do Scryfall (bulk JSON + imagens alta resolução) para o Arandu. Roda no **kavure** (scraper/sync), armazena no **psicopompo** (`/mnt/SSD_SATA/scryfall-mirror`) via NFS — psicopompo é apenas NAS.

**Status:** 🏗 Em implantação
**Servidor:** kavure (sync) / psicopompo (storage NFS)
**Storage:** `/mnt/SSD_SATA/scryfall-mirror` — 446GB livres (SSD SATA psicopompo)
**Sync:** diário 03:00 via `hl-scryfall-mirror.timer` (fora da janela 05:00 backup)
**Consumo:** `sae-core` no kavure lê via `/srv/data/scryfall-mirror` (NFS)

## Arquitetura

```
psicopompo (/mnt/SSD_SATA/scryfall-mirror)  ←→ NFS →  kavure (/srv/data/scryfall-mirror)
   ↑ NAS (BTRFS)                                   scraper + serve
```

- **JSON:** `default-cards.jsonl.gz` (75MB) → `bulk/` + `.last_updated` (sync idempotente: só baixa se `updated_at` da API mudar)
- **Imagens:** layout **sharded 1:1 com o CDN Scryfall** — `cards/{formato}/{front|back}/{h1}/{h2}/{uuid}.{ext}`
  (ex: `cards/png/front/6/d/6da045f8-....png` = espelho de `cards.scryfall.io/png/front/6/d/...`)
  6 formatos (`png/small/normal/large/art_crop/border_crop`) + verso `back/` para DFC. ~352k arquivos totais (~55-90GB).
- **Por que sharded:** diretório flat com 20k+ entradas via NFS é lento por design (servidor ordena a listagem — estoura timeouts). Shard hex 2 níveis = ~256 dirs/nível, listagem instantânea. Mesmo padrão de `.git/objects`.
- **API Scryfall:** bulk `api.scryfall.com` com `User-Agent: AranduTCG/1.0` + `Accept: */*` (obrigatório desde 08/2024), `/cards/search` 2/s. CDN `*.scryfall.io` sem rate limit. Cache 24h obrigatório (Scryfall exige).

## NFS + Subvolume BTRFS

**Subvolume dedicado** `@scryfall` (filehandles estáveis sob churn pesado + snapshots snapper):

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

Padrão `soft` + `x-systemd.automount` (nunca `hard`). Ver `network/nfs.md`.

**⚠️ Lição (31/08):** diretório flat `cards/{uuid}/` com 19.917 entradas fez `ls`/`du` via NFS travarem em D-state e o service estourar `TimeoutStartSec` (TERM às 03:30). Correção: shard 1:1 CDN + service hardening. Se listar o mirror lento, verificar contagem de entradas por dir (`find cards -maxdepth 4 -type d`).

## Serviço no kavure

`/srv/data/scryfall-mirror/` é consumido diretamente por `sae-core` (`ARANDU_CACHE_DIR=/srv/data/scryfall-mirror`). Sync roda como timer systemd no kavure:

- `hl-scryfall-mirror.service` (Type=oneshot, `RuntimeMaxSec=2h`, `Nice=19`, `IOSchedulingClass=idle`, `Restart=on-failure`, `OnFailure=notify-backup-failure@`)
- `hl-scryfall-mirror.timer` (OnCalendar=*-*-* 03:00, Persistent=true)

Script `scryfall-sync` (`/usr/local/bin`): checa `updated_at` vs `bulk/.last_updated` (idempotente), baixa `default-cards.jsonl.gz` se novo, grava health file `/srv/health/scryfall-mirror-last-ok`. **Nunca lista `cards/`** (só toca `bulk/`, dir pequeno).

**Prefetch** (`/tmp/prefetch-shard.py` → `/var/log/scryfall-prefetch.log` local): resumível (skip exists), 4 workers, `--limit-rate 2M`, `nice -19 ionice -c3`. On-demand também funciona: cache miss no front baixa 1 imagem via `get_or_cache_card_image` (path sharded, fallback CDN).

## Backup

Cache é recriável via CDN — **não** precisa off-box. Apenas configs do timer/script vão para `/mnt/BACKUP/configs-homelab` via `hl-config-backup` 05:00.

## Referências

- `services/arandu.md` — serviço Arandu (consome este mirror)
- `app/core/arandu_scryfall.py` — `CACHE_DIR`, `User-Agent`, rate limit
- Scryfall docs: `api.scryfall.com/bulk-data`, `scryfall.com/docs/api/rate-limits`
