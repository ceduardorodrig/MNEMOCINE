---
tags: [homelab, service, arandu, tcg, sumaenima, nfs, cache]
---

# Arandu

Plataforma TCG (Trading Card Game) integrada ao Sumænimá HUB. Terceiro pilar do Portal Agregador: Pasta digital social + Deck Builder co-op + Radar de jogadores.

**Status:** 🔶 Planejado — MVP v0.1 previsto para Fase 4 da migração Sumænimá
**Servidor:** kavure (Swarm `sae-core` — mesmo stack do Sumænimá)
**Domínio inicial:** `arandu.chimaera-heptatonic.ts.net`
**Domínio público futuro:** `arandu.app` (a avaliar disponibilidade)
**Nome:** Arandu — Guarani: *sabedoria, conhecimento acumulado*

## Cache de Imagens — SSD SATA do psicopompo

O Arandu usa um cache inteligente LRU de imagens de cartas (Scryfall) no **SSD SATA do psicopompo**, servido via NFS para o kavure.

| Item | Detalhe |
|---|---|
| **Disco** | SSD SATA Kingston A400 448GB — `/mnt/SSD_SATA` |
| **Diretório** | `/mnt/SSD_SATA/scryfall-mirror/cards/{id}/{formato}.jpg\|png` (mirror completo, Scryfall-compatível) |
| **Disponível** | ~446GB (99% livre em 2026-08-22) — `default_cards` alta-res ≈ 33GB, `all_cards` ≈ 88GB |
| **Política** | Mirror completo + LRU sob demanda: pesquisa/visualização no front dispara cache miss → CDN `c1.scryfall.com` → persiste; bulk `default-cards.jsonl.gz` 74M atualiza DB diariamente 03:00 via `hl-scryfall-mirror.timer` (kavure) + manifest diff para arte nova |
| **Formatos** | `small/normal/large/png/art_crop/border_crop` (6) + `card_faces[1]` verso — `png` 744×1040 sempre que possível |
| **Download** | On-demand (1 imagem) + daily bulk (DB + preços) + `xargs -P8` paralelo para prefetch 30k |

**Por que SSD_SATA e não outros discos:**

| Disco | Mount | Livre | Decisão |
|---|---|---|---|
| NVMe PCI 1.9TB | `/mnt/NVME_PCI` | 676GB | ❌ Já 64% usado (código, modelos, vault) |
| **SSD SATA 448GB** | `/mnt/SSD_SATA` | **446GB** | ✅ **99% livre — ideal** |
| HDD SATA 932GB | `/mnt/HDD_SATA` | 713GB | ❌ Lento para imagens via NFS |
| HDD Backup 932GB | `/mnt/BACKUP` | 681GB | ❌ Não misturar cache com backup |

### NFS Export (a configurar na Fase 4)

**psicopompo `/etc/exports` — adicionar:**
```bash
/mnt/SSD_SATA/scryfall-mirror 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
exportfs -arv
```

**kavure `/etc/fstab` — adicionar:**
```bash
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

> Seguir o padrão canônico NFS da tailnet: `soft,timeo=30,retrans=2` + `x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s`. Ver [`network/nfs.md`](../network/nfs.md).

### Endpoint de imagem (FastAPI)

```
GET /api/arandu/cards/{scryfall_id}/image?format=normal
  1. Verifica mirror local sharded: /srv/data/scryfall-mirror/cards/{fmt}/{face}/{h1}/{h2}/{id}.{ext}
  2. Cache miss: GET https://cards.scryfall.io/normal/... → salva → retorna
  3. Cache hit: retorna imagem local (latência ~0)
```

## Scryfall Sync (cron 04:00 diário)

```bash
# Download bulk data JSON (~300MB)
curl -L https://data.scryfall.io/oracle-cards/oracle-cards-YYYYMMDD.json -o /tmp/scryfall-bulk.json

# Upsert no PostgreSQL (tabela cards)
python3 manage.py scryfall_sync --file /tmp/scryfall-bulk.json
```

## Estimativas de Storage do Cache

| Escopo | Qtd | normal JPEG | PNG |
|---|---|---|---|
| Único jogador (500 cartas) | 500 | ~40 MB | ~140 MB |
| Coleção média (2.000 cartas) | 2.000 | ~160 MB | ~560 MB |
| Todas as impressões únicas | ~87.000 | ~7 GB | ~24 GB |
| Todos os oracles únicos | ~28.000 | ~2 GB | ~8 GB |

O cache começa vazio e cresce apenas com o que está sendo usado.

## Dependências

- PostgreSQL 16 (sae-core — kavure)
- Valkey 8 (sae-core — kavure) — co-op de deck via Pub/Sub
- NFS psicopompo (`/mnt/SSD_SATA/scryfall-mirror`) — cache de imagens (ver [scryfall-mirror.md](scryfall-mirror.md))
- Scryfall API (gratuita, sem autenticação obrigatória)
- Auth Google OAuth (escopos mínimos: `openid + email + profile`)
- PostGIS (a adicionar na Fase 4 v0.2, para o Mapa/Radar)

## PRD Completo

Ver [`sumaenima-hub/docs/arandu-prd.md`](../../sumaenimahub/sumaenima-hub/docs/arandu-prd.md) no repositório principal.

## See also

- [[steniobot]] — Stack sae-core compartilhada
- [[kavure]] — Servidor onde o Arandu roda em produção
- [[psicopompo]] — Servidor que serve o cache de imagens via NFS
- [[network/nfs]] — Configuração NFS da tailnet
