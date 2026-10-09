---
tags: [homelab, network, dns, tailscale]
---

# DNS

Cadeia de resolução de nomes no homelab.

## Visão Geral

Dois servidores DNS **com filtro**, servindo a tailnet inteira pela Tailscale:

```mermaid
graph TB
    subgraph clientes[Clientes da tailnet]
        psicopompo[psicopompo<br>100.82.51.112]
        kuaray[kuaray<br>100.94.209.99]
        kavure[kavure<br>100.124.146.77]
        desktop[desktop Windows<br>100.72.116.114]
        celulares[Celulares / IoT]
    end

    quad100[MagicDNS<br>100.100.100.100]

    subgraph resolvers[Resolvers com filtro]
        pihole[Pi-hole :53<br>kavure · ~2 ms]
        adguard[AdGuard Home :53<br>ybytu · ~66 ms]
    end

    subgraph egress[Camada de egress — quem fala com a internet]
        unbound[unbound recursivo 127.0.0.1:5053<br>DNSSEC · kavure]
        roots[Raiz / TLD / autoritativos<br>consulta direta, sem provedor]
        dot[fallback DoT<br>Quad9 9.9.9.9 · Cloudflare 1.1.1.1]
    end

    psicopompo --> quad100
    kuaray --> quad100
    kavure --> quad100
    desktop --> quad100
    celulares --> quad100

    quad100 -->|corrida paralela| pihole
    quad100 -->|corrida paralela| adguard

    pihole -->|"127.0.0.1#5053"| unbound
    unbound --> roots

    adguard -->|"tcp://100.124.146.77:5053"| unbound
    adguard -.->|se o unbound cair| dot
    unbound -.->|se o unbound cair: AdGuard assume (corrida)| adguard
```

## Como a Tailscale escolhe entre os dois (medido 06/10 e reconfirmado 08/10/2026)

A **ordem dos nameservers no painel admin da Tailscale não decide nada** — não existe
"primário" e "secundário" fixos. O forwarder local da Tailscale (Quad100) envia **cada
consulta para os dois resolvers em paralelo e usa a primeira resposta** que chegar
(comportamento descrito em [tailscale/tailscale#19024](https://github.com/tailscale/tailscale/issues/19024):
*"the forwarder races them in parallel"*):

| | Pi-hole (kavure) | AdGuard (ybytu) |
|---|---|---|
| Latência (cache quente) | **~2 ms** (LAN gigabit + cache) | **~66 ms** (Oracle + tailnet) |
| Vence quando **os dois** têm o nome em cache | ✅ (2 ms ≪ 66 ms) | — |
| Vence quando só o **AdGuard** tem em cache | — (~290 ms: recursão) | ✅ (35–92 ms) |
| Papel real | resolve a **maioria** das consultas (hits quentes) | **não é só failover**: vence quando tem o nome em cache e o Pi-hole não |

**Evidência de duplicação (captura no `tailscale0` do ybytu, 06/10; reconfirmada 08/10):**
as mesmas sondas enviadas via `100.100.100.100` apareceram **no Pi-hole (log FTL) e no
AdGuard** — os dois recebem tudo; só o mais rápido "vence". Reconfirmado em 08/10 com uma
**sonda de nome inédito**: apareceu no FTL do Pi-hole (forwarded) **e** no log do AdGuard.
Por isso as **contagens parecidas não são "empate"** — são a duplicação em paralelo. O
AdGuard também recebe tráfego direto de dispositivos (top clients: docker bridge `172.22.0.1`,
`100.115.253.109`, `127.0.0.1`).

> ⚠️ **O "Pi-hole vence quase sempre / é o decisor padrão" NÃO se confirma (medição 08/10/2026).**
> Teste do vencedor: psicopompo → `100.100.100.100`, 25 domínios populares, 1 consulta cada —
> **7** rápidas (2–22 ms → Pi-hole, cache hit), **8** médias (35–92 ms → AdGuard, cache hit),
> **10** frias (>150 ms, 1ª recursão). A corrida é decidida pela **latência**, e a latência
> depende de **quem tem aquele nome em cache**: onde ambos têm, o Pi-hole ganha (2 ms ≪ 66 ms);
> onde só o AdGuard tem, ele ganha. **Não há vencedor fixo** — os dois precisam de paridade.

> **Consequência prática (por que a paridade importa):** quem responde primeiro é quem
> aplica **as suas** regras. Se as listas divergirem, o bloqueio fica nondeterminístico
> — um domínio negado só no Pi-hole pode passar toda vez que o AdGuard vencer a corrida.
> Por isso os dois têm o mesmo conjunto de deny exatos/regras de telemetria/BR/TV desde
> 06/10/2026 (ver [`services/pihole.md`](../services/pihole.md) e
> [`services/adguard-home.md`](../services/adguard-home.md)). **Paridade medida em 08/10:**
> bloqueio Pi-hole **43,2%** × AdGuard **44%** ✅.

**Volumes medidos:** Pi-hole **85 799 consultas/24 h** (08/10) · AdGuard ~**79 k/dia**
(log de ~2 dias: 158 431 entradas) — volume parecido porque **os dois recebem tudo**.
Histórico Pi-hole 09/08→06/10: 5,08 M consultas; top clients `100.72.116.114` (desktop
Windows) 1,46 M · kavure 1,38 M · psicopompo 1,03 M · kuaray 332 k · ybytu 325 k.

## Camada de egress — recursão local (08/10/2026)

O **filtro** (Pi-hole/AdGuard) decide o que bloquear; o **egress** decide quem vê a consulta.
Desde **08/10/2026** o egress do kavure é **recursivo local** (`unbound` nativo na porta 5053):

| Resolver | Egress | Esconde do ISP | Esconde do provedor |
|---|---|---|---|
| Pi-hole (kavure) | `unbound` local → **recursão direta** (raiz → TLD → autoritativo) | parcial — o ISP vê DNS porta 53 saindo, mas sem provedor único de destino | ✅ — nenhum resolvedor central vê o histórico (só os autoritativos do domínio) |
| AdGuard (ybytu) | `tcp://100.124.146.77:5053` → **o mesmo unbound do kavure** · fallback `tls://9.9.9.9`/`tls://1.1.1.1` (DoT) | parcial (mesmo caminho) | ✅; no fallback, cifrado para Quad9/Cloudflare |
| Hosts (systemd-resolved) | fallback global `9.9.9.9`/`1.1.1.1` com `DNSOverTLS=opportunistic` | ✅ (quando usado) | parcial (DoT) |

> **Decisão 08/10/2026 (usuário):** a cadeia anonimizada anterior (Anonymized DNSCrypt com
> relays CryptoStorm US-Leste) custava **353 ms frios** por consulta — dois saltos
> transatlânticos, **sem relay na América do Sul** — e a navegação ficou perceptivelmente
> lenta. Escolha: **navegação fluida > anonimato total**. O unbound elimina o provedor
> intermediário (recursão própria com DNSSEC), ao custo de o ISP enxergar tráfego DNS
> genérico. Detalhes, comparação de imagens e medições: [`services/unbound.md`](../services/unbound.md).

### Provas de falha (re-verificadas 08/10/2026)

| Cenário testado | Resultado |
|---|---|
| **`unbound` do kavure parado (08/10)** | Consultas via `100.100.100.100` resolveram em **131/87 ms** (o AdGuard caiu no `fallback_dns` DoT) → **sem perda de internet**. Unbound religado e normalizado ✅ |
| `dnscrypt-proxy` do kavure parado (era 06/10 → 08/10, servidores de referência) | O Pi-hole para de responder, mas as consultas via `100.100.100.100` seguem resolvendo em 60 ms (AdGuard no `fallback_dns` DoT) → sem perda de internet |
| `dnscrypt-proxy` do ybytu parado (tentativa, revertida) | AdGuard degradou para `fallback_dns` em ~197 ms |
| Pi-hole com `strict-order` + fallback plano | **Não fazia failover** (6 timeouts seguidos) → desenho descartado |

> **Lição arquitetural:** a redundância do DNS aqui é a **corrida entre resolvedores**, não
> uma lista de upstreams do dnsmasq. Um fallback plano dentro do Pi-hole ou **vaza** (sem
> `strict-order`) ou **trava** (com `strict-order`).

## Cache (três níveis) — medido 07/10/2026, revisado 08/10

| Nível | Onde | Tamanho | Estado medido |
|---|---|---|---|
| **unbound** | kavure | `msg-cache 128m` · `rrset-cache 256m` · `key-cache 64m` · `neg-cache 16m` · `prefetch` + `prefetch-key` + `serve-expired 24 h` (tuning v2, 08/10) · 2 threads | substituiu o cache do dnscrypt em 08/10 (o proxy tinha 16384 entradas / ~14 MB RSS); telemetria: `unbound-control stats_noreset` (⚠️ `stats` sem `noreset` zera os contadores; o watchdog loga a cada 2 min) |
| **Pi-hole (FTL)** | kavure | `dns.cache.size = 10000` · `optimizer = 3600` (serve-stale) | **0 evictions** em 22.422 inserções · **~82 % de acerto** (33.312 hits / 7.516 misses) |
| **AdGuard** | ybytu | `cache_size = 4194304` (4 MiB, default) · `cache_ttl_min/max = 0` (usa o TTL do upstream) | — |

**Tem espaço para crescer?** Em **memória, sim**: o kavure tem ~6,3 GB livres e os dois
resolvedores juntos usam ~60 MB. Mas a [doc oficial do Pi-hole](https://docs.pi-hole.net/ftldns/dns-cache)
é explícita: *"não há benefício em aumentar esse número a menos que as evictions sejam maiores
que zero"* — e acima de 10.000 entradas a **busca degrada**. Como as evictions estão em
**zero**, o Pi-hole está no tamanho certo. O AdGuard fica modesto de propósito: o ybytu tem
só ~270 MB livres.

> Consultar as métricas do cache a qualquer momento:
> `dig +short chaos txt {cachesize,insertions,evictions,hits,misses}.bind @127.0.0.1` (no kavure).

## Por Máquina

### Psicopompo
| Item | Valor |
|---|---|
| Resolvedor | systemd-resolved (`stub` → `/run/systemd/resolve/stub-resolv.conf`) |
| DNS da tailnet | `100.100.100.100` (Quad100) — escopo `~.` (rota padrão) |
| Fallback | Quad9 `9.9.9.9` → Cloudflare `1.1.1.1` (DoT `opportunistic`, **sem Google**) — só se a Tailscale cair |

> **Fix resolve-nm (21/09/2026):** NetworkManager passou a usar `dns=systemd-resolved`
> (em `[main]` do `/etc/NetworkManager/NetworkManager.conf`) e o `/etc/resolv.conf`
> virou symlink para o stub do systemd-resolved (era `foreign`). Isso resolveu o
> aviso do Tailscale `tailscale.com/s/resolve-nm` e habilitou o MagicDNS
> (`*.chimaera-heptatonic.ts.net` resolve via `100.100.100.100`).

### Kavure
| Item | Valor |
|---|---|
| Servidor | **Pi-hole** (container `pihole`, `network_mode: host`, escuta só em `tailscale0`) |
| Porta | `53` · admin `http://100.124.146.77/admin` |
| Upstream | `127.0.0.1#5053` → **unbound recursivo local** (DNSSEC, desde 08/10/2026 — [`services/unbound.md`](../services/unbound.md)) |
| Papel | um dos dois resolvedores da corrida da tailnet (**sem vencedor fixo** — ver seção acima) |

### Ybytu
| Item | Valor |
|---|---|
| Servidor | **AdGuard Home** (container `adguardhome`) |
| Porta | `53` · admin `http://ybytu.chimaera-heptatonic.ts.net:3000` |
| Upstream | `tcp://100.124.146.77:5053` → **o mesmo unbound do kavure** (endpoint inalterado desde a era dnscrypt) · fallback DoT `tls://9.9.9.9`/`tls://1.1.1.1` |
| Papel | **failover** do Pi-hole + clientes diretos (desktop Windows) |
| Atenção | 954 MB de RAM — querylog `7d`/`size_memory 200` desde 06/10 (era 90d/1000 = 4 GB) |

### Kuaray
| Item | Valor |
|---|---|
| Resolvedor | Tailscale MagicDNS (`100.100.100.100`) |
| DNS local | **nenhum** — o Pi-hole morava aqui e migrou para o kavure (09/08/2026) |

### Ybyra
| Item | Valor |
|---|---|
| Resolvedor | Oracle Metadata DNS (`169.254.169.254`) + MagicDNS |
| DNS local | Nenhum |

> **Fix MagicDNS (21/09/2026):** `tailscale set --accept-dns=true` estava com
> `CorpDNS: false` (MagicDNS não injetava no systemd-resolved — `getent` retornava
> vazio apesar de `dig @100.100.100.100` funcionar). Após habilitar:
> `resolvectl status tailscale0` mostra `Current Scopes: DNS` + `DNS Domain:
> chimaera-heptatonic.ts.net` e `getent hosts kuaray...` resolve corretamente.

## Domínios

| Domínio | Resolvido por |
|---|---|
| `*.chimaera-heptatonic.ts.net` | Tailscale MagicDNS |
| `ybytuvcn.oraclevcn.com` | Oracle DNS |
| `ybyravcn.oraclevcn.com` | Oracle DNS |
| Nomes locais LAN | Pi-hole (kavure) / AdGuard (ybytu) |
| Internet geral | upstreams do resolver que venceu a corrida |

## Testar a paridade dos dois resolvers

```bash
# Um domínio nos DOIS (espera-se o mesmo resultado)
for d in telemetry.microsoft.com ge.globo.com www.google.com; do
  printf '%-35s pihole=%s adguard=%s\n' "$d" \
    "$(dig +short A "$d" @100.124.146.77 | head -1)" \
    "$(dig +short A "$d" @100.115.253.109 | head -1)"
done

# Ver para onde uma consulta do sistema realmente foi
ssh root@100.124.146.77 "sqlite3 /srv/data/pihole/etc-pihole/pihole-FTL.db \
  \"SELECT domain,client,status FROM queries ORDER BY timestamp DESC LIMIT 10;\""

# Provar que a Tailscale manda para os DOIS
ssh root@100.115.253.109 'timeout 15 tcpdump -nntt -i any \
  "udp port 53 and src net 100.64.0.0/10" -c 20'
```

## Comandos Úteis

```bash
# Ver resolução de um nome
resolvectl query servico.chimaera-heptatonic.ts.net

# Ver servidores DNS configurados
resolvectl status
tailscale dns status

# Testar DNS por servidor específico
dig @100.100.100.100 google.com        # Quad100 (encaminhador da Tailscale)
dig @100.124.146.77 google.com         # Pi-hole (kavure)
dig @100.115.253.109 google.com        # AdGuard (ybytu)
```
