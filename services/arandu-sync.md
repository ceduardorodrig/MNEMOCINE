---
tags: [homelab, service, arandu, scryfall, postgres, psicopompo, kavure]
---

# Arandu — Catálogo Scryfall (sync)

Sincroniza o bulk do Scryfall para a tabela `arandu_cartas` do PostgreSQL
(`stenio_db`), alimentando o catálogo do Arandu TCG.

**Binário:** `app/arandu-sync` (Rust) — compilado no **psicopompo** (build-node, ADR-026)
**Banco:** `sae-core_db` (kavure), alcançado pela overlay `sae-net`
**Agendamento:** diário **04:00** via `hl-arandu-sync.timer`

## Por que o timer roda "depois" do mirror

A cadeia de horários é intencional e não deve ser alterada sem reavaliar tudo:

| Hora | Unit | O que faz |
|---|---|---|
| **03:00** | `hl-scryfall-mirror` | Baixa o bulk e as imagens do Scryfall (no kavure) |
| **04:00** | `hl-arandu-sync` | Lê o bulk e popula `arandu_cartas` |
| **05:00** | `hl-config-backup` | Espelha as configs dos hosts |

## Onde roda e por quê

O sync roda no **psicopompo**, não no kavure: o binário é compilado lá (é a máquina
de build) e o kavure não tem toolchain Rust. O contato com o banco é feito por um
container efêmero anexado à overlay `sae-net` — o `DATABASE_URL` aponta para
`db:5432`, o nome do **serviço** dentro da overlay, que só resolve de dentro dela.
**O 5432 não é publicado no host** (a matriz de `network/ports.md` está desatualizada
nesse ponto).

## Operação

```console
# status / próximo disparo
$ systemctl list-timers hl-arandu-sync.timer

# rodar agora (manual)
$ sudo systemctl start hl-arandu-sync.service
$ journalctl -u hl-arandu-sync -f

# conferir o catálogo (dentro do container do banco, pela overlay)
$ SELECT count(*) FROM arandu_cartas;
```

**Health:** o wrapper grava `/srv/health/arandu-sync-last-ok`, que o
`health-files-metrics.sh` (timer de 5 min) expõe como métrica ao Prometheus.
**Falha:** alerta por **ntfy** (`ybytu:8083/backup`). Não usa
`OnFailure=notify-backup-failure@` por padrão porque aquele template **não existia
em nenhum host** até 29/09/2026 — o `hl-scryfall-mirror` apontava para ele e falhava
em silêncio. O template foi criado e testado.

## Nuances da unit (aprendidas no teste ponta a ponta)

| Nuance | Detalhe |
|---|---|
| **`User=edu`** (não root) | A chave age do cofre (`~/.config/sops/age/keys.txt`, `0600`) é do `edu`; como root o `sops` não decripta e o sync morre na leitura do `DATABASE_URL` |
| **`RuntimeMaxSec` não vale aqui** | Não tem efeito com `Type=oneshot` — o systemd avisa e ignora. É a **mesma armadilha do `Restart=`** já documentada no `sumaenima-gpu.service`. O teto de tempo fica no wrapper |
| **`/srv/health` é do root** | O health file é escrito via `tmpfiles.d` (`/etc/tmpfiles.d/hl-arandu-sync.conf`) concedendo escrita ao **grupo `edu`** só nesse arquivo — não a world |
| **Imagem runner** | `rust:1-slim-bookworm` (já traz `libssl.so.3`). A `debian:bookworm-slim` exigia `apt-get install libssl3` em runtime — lento e sujeito a falha de rede no meio do job |
| **Roda na overlay** | O `DATABASE_URL` aponta para `db:5432`, nome do **serviço** dentro da `sae-net`; container efêmero é anexado a essa rede para alcançá-lo |

> ⚠️ **Lição de método:** rodar só o binário à mão não valida o serviço. Os três
> defeitos acima **só apareceram** no `systemctl start` de verdade — é o mesmo
> princípio de "testar o artefato implantado, não a fonte".

## Bugs corrigidos em 29/09/2026 (o catálogo estava em 0,5%)

O catálogo tinha **600 de 118.406 cartas** e o sync reportava *sucesso*. Eram
**quatro defeitos encadeados**, cada um mascarando o próximo:

| # | Defeito | Efeito |
|---|---|---|
| 1 | A API renomeou `download_uri` → **`jsonl_download_uri`** | Falhava com "não encontrada URL", parecendo erro de `bulk_type` |
| 2 | Bulk **gzip lido como texto** | Nenhuma linha virava JSON → "sucesso" com **0 cartas** |
| 3 | `arandu_cartas.id` é `NOT NULL` **sem DEFAULT** e o INSERT não o listava | Abortava por constraint |
| 4 | Default era `oracle_cards` (~33k, carta única) em vez de `default_cards` (~118k impressões) | Indexava um conjunto que não bate com o produto |

**Resultado:** 118.448 cartas, 118.286 com imagem, 1.052 sets distintos, em ~50 s.
O sync agora **falha explicitamente** se nenhuma carta for lida, em vez de fingir
sucesso.

Ver [`scryfall-mirror.md`](scryfall-mirror.md) (o mirror das imagens) e
[`../servers/kavure.md`](../servers/kavure.md).

---
Última revisão: **2026-09-29**.
