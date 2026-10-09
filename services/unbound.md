---
tags: [homelab, service, unbound, dns, kavure]
---

# Unbound

DNS **recursivo local** com validação DNSSEC — **instalação nativa (apt) no kavure**,
substituiu o `dnscrypt-proxy` como upstream do Pi-hole/AdGuard em **08/10/2026**.

**Servidor:** kavure
**Pacote:** `unbound` **1.19.2-1ubuntu3.10** (Ubuntu noble — versão base 2022 com
backports de segurança, últimos em 02/10/2026)
**Bind:** `127.0.0.1:5053` (Pi-hole) + `100.124.146.77:5053` (tailnet — AdGuard)
**Config:** `/etc/unbound/unbound.conf.d/mnemocine.conf`
**Serviço:** `unbound.service` (systemd, nativo) · watchdog `hl-dns-watchdog.timer` (2 min) ·
status `unbound-status.service` (`:9097`, para o chip do Homepage)

## Por que existe (e por que substituiu o dnscrypt-proxy)

O caminho anonimizado (dnscrypt-proxy → relay CryptoStorm EUA → servidor dnscry.pt US-Leste)
tinha **dois saltos transatlânticos por consulta fria**: medido em 08/10, frio = **353 ms**
vs **21 ms** do Cloudflare direto. Não existe relay DNSCrypt na América do Sul — o piso de
latência era o RTT kavure↔Miami (~121 ms) + salto relay→servidor.

**Decisão (08/10/2026, usuário):** trocar anonimato por navegação fluida. O unbound
resolve **direto da raiz** (root → TLD → autoritativo), sem provedor intermediário:

| Cadeia | Quem vê a consulta |
|---|---|
| ~~Pi-hole → dnscrypt → relay → servidor~~ | relay (IP) + servidor (consulta), operadores diferentes |
| **Pi-hole → unbound → autoritativos** | só os servidores autoritativos do domínio consultado (e o ISP vê que é DNS porta 53, sem destino fixo) |

> **O que se perde:** o ISP passa a ver *que* tráfego DNS sai (não para qual provedor
> específico — a recursão vai para raiz/TLD/autoritativos espalhados). O que se ganha:
> navegação sem penalidade de 200–300 ms e zero dependência de terceiros.

## Por que NATIVO (apt) e não container

Comparação feita em 08/10/2026 com fontes oficiais:

| | Nativo apt (**escolhido**) | `klutchell/unbound` (Docker) | `alpinelinux/unbound:edge` |
|---|---|---|---|
| Versão | 1.19.2 + backports | **1.13.2 (2021)** — congelado | 1.26.1 (atual) |
| CVEs 2026 | ✅ 13 backportados (Canonical, 02/10) | ❌ nenhum | ✅ upstream |
| Origem | Canonical security team | repo GitHub **arquivado** ("moved" p/ GitLab) | comunidade Alpine |
| Guia Pi-hole | ✅ caminho oficial (`apt install unbound`) | — | — |

- **Nenhuma imagem oficial da NLnetLabs existe** (verificado no Docker Hub — a org
  `nlnetlabs` publica routinator/krill/etc., mas não unbound).
- A imagem popular `klutchell/unbound` é **1.13.2 estático de 2021** (label
  `org.opencontainers.image.version`), sem nenhum dos CVEs de 2026 (incl. RCE
  CVE-2026-81642) — inadmissível para resolvedor recursivo exposto.
- Nativamente o **systemd dá de graça** o que exigiria compose: `Restart=`,
  logs no journal, `unbound-checkconf`, e o pacote atualiza root hints
  (`dns-root-data`) + âncora DNSSEC automaticamente.
- O kavure é nó **Swarm manager** com histórico de incidente Docker
  (`live-restore`, 02/10) — a cadeia crítica de DNS não ganha mais uma dependência do dockerd.

## Pre-flight (obrigatório antes de instalar — guia Pi-hole)

Os 3 testes do guia oficial ([docs.pi-hole.net/guides/dns/unbound](https://docs.pi-hole.net/guides/dns/unbound/))
contra `a.root-servers.net` (198.41.0.4) — **todos passaram no kavure (08/10)**:

```bash
dig @198.41.0.4 . NS +norec +time=3          # flags: qr aa → sem interceptação ISP ✅
dig @198.41.0.4 . NS +norec +tcp +time=3     # TCP/53 aberto (CG-NAT não bloqueia) ✅
dig @198.41.0.4 version.bind CH TXT +time=3  # resposta "ATLAS" → é o root de verdade ✅
```

> Se `aa` faltar ou `ra` aparecer, o ISP está sequestrando a porta 53 → **não instalar**
> antes de resolver (o unbound falharia de formas difíceis de diagnosticar).

## Configuração (`/etc/unbound/unbound.conf.d/mnemocine.conf`)

Baseada no `pi-hole.conf` do guia oficial, ajustada para o cenário Mnemocine:

| Chave | Valor | Motivo |
|---|---|---|
| `interface` / `port` | `127.0.0.1` + `100.124.146.77` / **`5053`** | loopback (Pi-hole `network_mode: host`) + tailnet (AdGuard ybytu); **5053 = mesma porta do antigo proxy → nenhum upstream mudou de endpoint** |
| `do-ip6` | `no` | sem IPv6 nativo (só ULA da tailscale) — evita esperar AAAA inalcançáveis; AAAA ainda resolve via IPv4 |
| `access-control` | `127.0.0.0/8` + `100.64.0.0/10` allow, resto `refuse` | só loopback e tailnet |
| `harden-dnssec-stripped` | `yes` | **opção correta da 1.19.2** (o rascunho usava `harden-dnssec-stubs`, que não existe) |
| `edns-buffer-size` | `1232` | DNS Flag Day 2020 — evita fragmentação UDP |
| `use-caps-for-id` | `no` | capitalização aleatória causa problemas DNSSEC (guia) |
| `prefetch` | `yes` | revalida itens quase expirados antes do acesso |
| *(TCP / módulos)* | `incoming-num-tcp 64`, `outgoing-num-tcp 32`, `tcp-idle-timeout 120000`, `module-config "validator iterator"` | buffers de rajada, pool do dnsproxy e correção do `subnetcache` — ver *Correção TCP* |
| `so-rcvbuf` | `1m` | exige `net.core.rmem_max=1048576` → `/etc/sysctl.d/99-unbound.conf` (warning documentado do guia) |
| `msg-cache` / `rrset-cache` | `128m` / `256m` (eram 32m/64m — tuning v2) | kavure tem ~6 GB livres; ver seção *Tuning v2* |
| `private-address` | RFC1918 + TEST-NET + **`100.64.0.0/10`** | anti DNS-rebinding (RFC6303 4.2) |
| `verbosity` | `0` | só erros no dia a dia |

Root hints: pacote `dns-root-data` (atualizado via apt) · âncora DNSSEC:
`root-auto-trust-anchor-file.conf` → `/var/lib/unbound/root.key` (do pacote).

### Passo do guia que NÃO pode faltar

```bash
systemctl disable --now unbound-resolvconf.service
```
Sem isso, o `unbound-resolvconf` escreve `nameserver 127.0.0.1` **sem a porta 5053** no
`/etc/resolv.conf` (Debian Bullseye+). No kavure o `/etc/resolv.conf` é do systemd-resolved
e o pacote já ignora (LP #2078599), mas foi desabilitado por igual.

## Tuning v2 (08/10/2026 — aplicado e medido na mesma data)

Após a entrada em operação, a config passou por otimização com **defaults verificados na
1.19.2** (`unbound-checkconf -o <op>`) e doc oficial (`unbound.conf(5)`):

| Opção | Antes | Depois | Por quê |
|---|---|---|---|
| `prefetch-key` | no (default) | **yes** | evita busca **serial** de DNSKEY na 1ª visita a domínio DNSSEC — corta um roundtrip do caminho frio |
| `serve-expired` + `serve-expired-ttl: 86400` | no | **yes** | item expirado responde **na hora** (stale, `reply-ttl 30 s`) e revalida em background — mesma filosofia do optimizer do Pi-hole/AdGuard, agora no layer do unbound; teto de 24 h |
| `msg-cache-size` | 32m | **128m** | espaço para crescer (kavure ~6 GB livres) |
| `rrset-cache-size` | 64m | **256m** | idem |
| `key-cache-size` | 4m | **64m** | chaves DNSSEC em RAM — dono direto do frio pesado |
| `neg-cache-size` | 1m | **16m** | NXDOMAINs não refazem recursão |
| `num-threads` | 1 | **2** | headroom p/ rajada de frios (navegador = ~20 domínios novos); `so-reuseport` é default yes, slabs ajustam sozinhos |
| `cache-min-ttl` | 0 | **0 (mantido)** | ⚠️ docs oficiais: subir faz o cache "não bater mais com o domínio" |

**Pós-tuning validado (08/10):** `unbound-checkconf` OK · DNSSEC (SERVFAIL / `ad`) OK ·
TCP 8/8 do ybytu · **0 erros** no AdGuard na janela curta do restart (os `EOF` de rajada só
apareceram com uso real — ver *Correção TCP*) · RSS 24 MB (caches
alocam sob demanda) · frio normal **197–478 ms (média ~290)** — limite físico do RTT até
os servidores autoritativos no 1º contato; o ganho do tuning aparece no **reuso**
(key-cache, serve-expired, prefetch). Rollback: `mnemocine.conf.bak-20261008-tuning` + restart.

### Telemetria (crescer o cache com números)

O `remote-control` já vem ativo no pacote (socket `/run/unbound.ctl`). **O watchdog loga a
telemetria a cada 2 min** (`--stats` — ver *Watchdog*): uma linha com hit-rate, hits, misses,
queries, `stale` e RSS.

```bash
journalctl -u hl-dns-watchdog.service -n 3 --no-pager | rg telemetry
# ex.: hit-rate=55.8% hits=63 misses=50 queries=113 stale=20 rss=17960kB

unbound-control stats_noreset | rg "total.num.(cachehits|cachemiss|expired)"
# hit-rate = cachehits / (cachehits + cachemiss)
```

> ⚠️ **Use `stats_noreset`.** `unbound-control stats` (sem `noreset`) **zera** os contadores
> ao imprimir — o número vira "desde a última leitura". Este build **não expõe `mem.*`** em
> nenhum stats command: a memória se observa pelo **RSS** (o watchdog loga `rss=`). Crescer
> `msg/rrset/key/neg-cache` quando a hit-rate estabilizar **baixa** com `misses` subindo.

### Correção TCP (08/10/2026 — duas causas de `EOF`, ambas provadas)

**Sintoma:** o AdGuard (upstream `tcp://100.124.146.77:5053`) logava
`exchange failed ... over tcp: EOF` **~2,5×/min em horário de uso** (123 erros em 50 min),
quase todo em consultas AAAA/SRV frias de 475–945 ms.

**Causa 1 — `incoming-num-tcp` estourando em rajada (reproduzida):** o default `10` é
**por thread** → 20 buffers no total. Consultas TCP novas rápidas passam sempre (30/30 e
8/8 ok — por isso os testes simples não pegavam), mas uma **rajada com recursão fria
acima de ~20 simultâneas** esgota os buffers e o unbound **fecha as conexões excedentes**
→ dnsproxy recebe EOF. Prova: 216 consultas TCP paralelas a domínios frios → **15
falhas** (14 EOF + 1), agrupadas acima de 20 simultâneas.

**Causa 2 — `tcp-idle-timeout` de 30 s fechando o pool do dnsproxy (reproduzida):** o
default `30000` fecha conexão **ociosa**; o dnsproxy faz *pool* do upstream TCP e reusa a
conexão depois de 30 s ociosa → EOF. Prova: conexão nova → ok, idle 5 s → ok, **idle real
33 s → EOF** (a 1ª tentativa de teste foi inválida: a consulta de 12 s resetou o timer —
o periodo ocioso real era só 24 s). O journal fica **silencioso** nesses fechamentos
(fecha limpo, sem erro do unbound).

**Fix (`mnemocine.conf`, 08/10):**

| Opção | Antes | Depois | Por quê |
|---|---|---|---|
| `incoming-num-tcp` | 10 (default, por thread) | **64** | ×2 threads = 128 conexões de cliente simultâneas — cabe a maior rajada de page load |
| `outgoing-num-tcp` | 10 (default) | **32** | recursão de saída em TCP (resposta truncada) na mesma rajada |
| `tcp-idle-timeout` | 30000 (default) | **120000** | pool do dnsproxy reusa conexão >30 s ociosa; 2 min = **teto desta build** — valores maiores são **clampeados** (`unbound-checkconf -o`: 120001→120000, 300000→120000, 99999999→120000; o man não menciona o clamp) e o **runtime confirma**: idle 33 s/100 s → ok, idle 130 s → EOF. Man: sob pressão de buffers o valor cai dinamicamente (50%→1%, 35%→0,2%, 20%→0, piso 200 ms) — a proteção contra exaustão continua valendo |
| `module-config` | `subnetcache validator iterator` (default do build `--enable-subnet`) | **`validator iterator`** | man `unbound.conf(5)`: `subnetcache` só para resolver e clientes em **redes diferentes** (open resolver); aqui é a mesma rede (loopback + tailnet), não usamos ECS e o módulo degrada cache/prefetch |

**Validado:** mesmo teste de 216 → **216/216, 0 EOF** (1,2 s vs 3,2 s) · regressão de
idle pós-fix: **33 s → ok** (era EOF), **100 s → ok**, **130 s → EOF** (= o clamp de
120 s em runtime, comportamento esperado) · warnings `subnetcache: serve-expired/prefetch
... not working` **sumiram** do log · **0 erros** no AdGuard após as correções ·
`unbound-checkconf` OK. Backups: `mnemocine.conf.bak-20261008-tcpfix` (causa 1) e
`.bak-20261008-idle` (causa 2).

## Limitações conhecidas

- **`tcp-idle-timeout: 120000` é o teto desta build** (valores maiores são clampeados, provado
  em runtime). O dnsproxy reusa conexão do pool: se uma ficar **ociosa >2 min** e for reusada,
  um `EOF` isolado ainda pode aparecer no AdGuard. É raro e **não interrompe** o cliente — o
  dnsproxy refaz a consulta (ou cai no `fallback_dns`). Fica no radar do soak.
- **`mem.*` ausente no `unbound-control`** desta build → memória observada pelo **RSS**.
- **`unbound-control stats` (sem `noreset`) zera os contadores** ao imprimir — sempre usar
  `stats_noreset` para inspecionar (ver *Telemetria*).

## Validação (08/10/2026 — tudo passou)

```bash
dig @127.0.0.1 -p 5053 pi-hole.net +short           # resolve ✅
dig fail01.dnssec.works @127.0.0.1 -p 5053          # SERVFAIL (domínio DNSSEC quebrado) ✅
dig +ad dnssec.works @127.0.0.1 -p 5053             # NOERROR + flag `ad` (validado) ✅
# TCP (AdGuard usa tcp://): 6/6 local, 8/8 do ybytu ✅
```

## Latência medida (08/10/2026 — antes × depois)

| Cenário | dnscrypt-proxy (antes) | Unbound (depois) |
|---|---|---|
| Fria (12 domínios via Pi-hole) | **353 ms** | **~280 ms** (160–484) · pós-tuning ~290 ms (197–478, mesmas condições) |
| Fria ponta-a-ponta (psicopompo → MagicDNS) | ~284 ms | **58–352 ms** (mediana ~220) |
| Quente | 0 ms | **~19–22 ms** |
| Frios extremos (registries DNSSEC pesados) | ~360–550 ms (relays EUA) | 700–1900 ms (primeing; só na 1ª consulta) |

- O pior caso (iana.org 1,9 s) é **primeing único** — root/TLD/autoritativo pela 1ª vez;
  depois disso o cache (Pi-hole ~82% hit + unbound prefetch) absorve.
- Cadeia ativa: `cliente → MagicDNS → Pi-hole(:53) → unbound(:5053) → raiz/TLD/autoritativo`.

## Failover (provado, não presumido)

**Teste 08/10:** `systemctl stop unbound` → consultas via `100.100.100.100`
seguiram resolvendo em **131/87 ms** (o AdGuard do ybytu assumiu pela `fallback_dns`
DoT `tls://9.9.9.9`/`tls://1.1.1.1`) → **sem perda de internet**. Unbound religado e
normalizado ✅. Mesma estrutura de prova da era dnscrypt (ver
[`network/dns.md`](../network/dns.md)).

## Watchdog (`hl-dns-watchdog` — Rust)

O mesmo watchdog de antes, **repontado** de `--container dnscrypt-proxy` para
`--service unbound` (o binário ganhou a flag `--service` em 08/10/2026):

- Fonte: [`scripts/dns-watchdog/`](../../scripts/dns-watchdog/) · binário
  `/usr/local/bin/dns-watchdog` (kavure, reconstruído 08/10)
- Unit: `hl-dns-watchdog.service` (+ `.bak-20261008-unbound` = cópia da antiga)
- Timer a cada 2 min: sonda `127.0.0.1:5053` com label único
  (`watchdog-<epoch>.cloudflare.com` — pega também cadeia de upstream quebrada) e, se 3
  tentativas falharem, `systemctl reset-failed` (best-effort, cobre start-limit-hit) +
  `systemctl restart unbound`.
- `--stats` (08/10/2026): loga a telemetria do cache (`stats_noreset`) a cada ciclo —
  hit-rate, hits, misses, queries, `stale` e RSS. Só observabilidade: falha na telemetria
  não altera (nem mascara) o resultado da sonda. Ver *Telemetria*.
- Log: `journalctl -u hl-dns-watchdog.service`

> ⚠️ **Por que era obrigatório repontar:** com a unit apontando para o container antigo,
> uma indisponibilidade do unbound faria o watchdog **ressuscitar o dnscrypt-proxy**,
> que brigaria pela porta 5053 — cenário de conflito.

## Endpoint de status (Homepage) — `unbound-status`

O `unbound` é **nativo (systemd), sem HTTP**. Pela convenção do Homepage (**serviço nativo
sem HTTP → mini endpoint HTTP de status + `siteMonitor`**), existe um endpoint Rust —
**irmão do `minecraft-status`**, mesma forma:

- **Porta:** `9097` (kavure) · **Serviço:** `unbound-status.service` (systemd, nativo)
- **Fonte:** `SUMAENIMA-HUB/provisioning/unbound-status/` (+ unit em `provisioning/systemd/`)
- `GET /` → **200 `up`** quando o unbound responde a um DNS A com **rótulo único** na
  `127.0.0.1:5053`; **503 `down`** caso contrário · `HEAD` → mesmos cabeçalhos, **sem corpo**
  (RFC 7231 §4.3.2).
- Homepage: `siteMonitor: http://kavure:9097` no tile *Unbound* (chip de ms, padrão).
- **Provado 08/10/2026:** unbound parado → `503 down`; religado → `200 up`.

## Operação

```bash
systemctl status unbound
journalctl -u unbound -n 50 --no-pager
unbound-checkconf                        # valida config
systemctl restart unbound
dig @127.0.0.1 -p 5053 example.com       # teste local
```

## Rollback (voltar ao dnscrypt-proxy)

```bash
cd /srv/data/dnscrypt-proxy && docker start dnscrypt-proxy   # container intacto
systemctl stop unbound
# upstreams NÃO mudam: Pi-hole continua 127.0.0.1#5053, AdGuard tcp://100.124.146.77:5053
```
(Reverter também o watchdog: `--service unbound` → `--container dnscrypt-proxy`.)

## Backup

- `/etc/unbound/unbound.conf.d/mnemocine.conf` + `/etc/sysctl.d/99-unbound.conf`
  → **GOLDEN_FILES** do `/etc/config-backup.conf` (kavure), adicionado em 08/10/2026.
- Container/compose do dnscrypt mantidos em `/srv/data/dnscrypt-proxy/` (coberto pelo
  `SRC_DIRS=/srv/data`) para rollback.

## Referências

- Guia oficial: [docs.pi-hole.net/guides/dns/unbound](https://docs.pi-hole.net/guides/dns/unbound/)
- Projeto: [nlnetlabs.nl/projects/unbound](https://nlnetlabs.nl/projects/unbound/about/)
- Histórico do proxy substituído: [`dnscrypt-proxy.md`](dnscrypt-proxy.md)
