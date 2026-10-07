---
tags: [homelab, service, dnscrypt, dns, kavure]
---

# dnscrypt-proxy

Camada de **egress DNS cifrado e anonimizado** do homelab — roda no **kavure**, atrás do
Pi-hole (ver [`pihole.md`](pihole.md)).

**Servidor:** kavure
**Imagem:** `klutchell/dnscrypt-proxy@sha256:8911f7478837d42fa2c54504058b843415294c19233d424c5730987b05d987d7` (dnscrypt-proxy **2.1.18**)
**Bind:** `127.0.0.1:5053` (UDP/TCP)
**Config:** `/srv/data/dnscrypt-proxy/config/dnscrypt-proxy.toml`
**Compose:** `/srv/data/dnscrypt-proxy/compose.yml` (`network_mode: host`, `restart: unless-stopped`)

## Por que existe

O Pi-hole v6 **não fala DoH/DoT** — só DNS plano (porta 53) para o upstream. Para cifrar o
tráfego DNS, o caminho oficial é um proxy local; para **anonimizar** (não só cifrar) é o
`dnscrypt-proxy`. O guia usado é o do próprio Pi-hole:
[docs.pi-hole.net/guides/dns/dnscrypt-proxy](https://docs.pi-hole.net/guides/dns/dnscrypt-proxy/).

> **Nota para o futuro (Pi-hole v7):** o v7 trará DoT/DoH/DoH3 nativos, mas **não ODoH**
> — ou seja, resolverá a *criptografia*, mas **não** o anonimato. Enquanto o anonimato
> for desejado, este proxy continua necessário.

## Anonimato (Anonymized DNSCrypt)

Fluxo: **kavure → relay → servidor DNSCrypt → (resolve) → relay → kavure**.

- O **relay** vê o IP da casa, mas não a consulta.
- O **servidor** vê a consulta, mas não o IP da casa.

| Elemento | Operador | Endpoints (06/10/2026) |
|---|---|---|
| Servidores | `dnscry.pt` (**operador A**) | `dnscry.pt-tampa/miami/jacksonville/atlanta-ipv4` |
| Relays | CryptoStorm (**operador B**) | `anon-cs-fl` (Miami 146.70.240.203), `anon-cs-ga` (Atlanta 130.195.212.211), `anon-cs-dc` (DC 198.7.58.227) |

> ⚠️ **Regra de ouro do anonimato:** relay e servidor têm de ser de **operadores
> diferentes**. A doc dos servidores avisa que *"all dnscry.pt resolvers can also be used
> as Anonymized DNSCrypt relays"* — parear `dnscry`↔`dnscry` faria **uma única entidade**
> enxergar IP + consulta (anonimato nulo).

- **Não existe relay na América do Sul.** O mais próximo é Miami (RTT kavure↔Miami ~121 ms)
  — isso define o piso de latência.
- `skip_incompatible = true`: nunca cair para conexão direta (bypass do relay).
- Verificação usada: `[query_log]` temporário (coluna `relay` deve estar preenchida).

## Parâmetros relevantes do `dnscrypt-proxy.toml`

| Chave | Valor | Motivo |
|---|---|---|
| `listen_addresses` | `['127.0.0.1:5053']` | loopback (Pi-hole é `network_mode: host`) |
| `server_names` | 4 servidores `dnscry.pt` US-Leste | latência + operador distinto do relay |
| `cache` / `cache_size` | `true` / `16384` | 2ª camada de cache — o Pi-hole não pode subir o cache dele sem degradar o lookup |
| `cache_min_ttl` | `0` | **NUNCA** usar o `2400` do exemplo oficial (40 min de dado velho) |
| `cache_max_ttl` | `86400` | teto são. **Com `0` o cache não funciona** (erro cometido e corrigido em 06/10) |
| `keepalive` | `30` | conexões quentes |
| `lb_estimator` / `lb_strategy` | `true` / `wp2` | escolhe o servidor mais rápido medido |
| `bootstrap_resolvers` | `['9.9.9.11:53']` | só para baixar a lista de servidores; sem Google |
| `block_unqualified` / `block_undelegated` | `true` | não vazar nomes locais |
| `[query_log]` | **ausente** | sem log de consultas (privacidade) |
| `doh_servers` / `odoh_servers` | `false` | ODoH tem só **2 relays** no registro oficial (frágil); Anonymized DNSCrypt tem 310 |

## Desempenho medido (06/10/2026)

| Cenário | Latência |
|---|---|
| Cache quente (proxy ou Pi-hole) | **0 ms** |
| Consulta fria (domínio novo) | **147–323 ms** (média ~220 ms) |
| Piso teórico | ~121 ms (RTT kavure↔Miami) + salto relay→servidor |
| % das consultas que chegam ao upstream | **4,5%** (o resto: cache 26,5% + stale 18,9% + bloqueado 44,6% + em voo 5%) |

Impacto prático: só a **primeira visita** a cada domínio novo paga o custo; o resto é
idêntico ao DNS plano (que era ~18 ms).

## Operação

```bash
cd /srv/data/dnscrypt-proxy
docker compose ps
docker logs --tail 50 dnscrypt-proxy      # pares "Anonymizing ... via ..."
docker compose restart
```

### Watchdog (Rust) — `hl-dns-watchdog`

A imagem é *distroless* (sem shell), então **não aceita healthcheck interno**. A cobertura
vem de um **watchdog externo em Rust** (`scripts/dns-watchdog/`, binário em
`/usr/local/bin/dns-watchdog` no kavure), disparado por `hl-dns-watchdog.timer` a cada
**2 min**: consulta `127.0.0.1:5053` e, se não houver resposta após 3 tentativas,
`docker restart dnscrypt-proxy`. Cobre o caso "travado", que o `restart: unless-stopped`
sozinho não cobre. Log: `journalctl -u hl-dns-watchdog.service`.

### Consumo pelo AdGuard (Opção A — 06/10/2026)

O `dnscrypt-proxy` passou a escutar também na **tailnet** (`100.124.146.77:5053`), e o
AdGuard (ybytu) consome ele como upstream — assim **os dois resolvedores resolvem
anonimizado** e quem vence a corrida não importa mais. Verificado por captura
(`100.115.253.109 → 100.124.146.77:5053`).

> **Nota de transporte (pendência encerrada):** o AdGuard usa `tcp://100.124.146.77:5053`.
> O caminho **UDP** do dnsproxy apresentou timeouts intermitentes (4/6) por esse trajeto,
> enquanto sockets UDP crus (dig, python conectado/não-conectado) passavam 6/6 e 20/20 numa
> rajada — **não é a rede nem este proxy**. É uma **classe de bug conhecida do AdGuard Home com
> UDP** ([#7628](https://github.com/AdguardTeam/AdGuardHome/issues/7628),
> [#7346](https://github.com/AdguardTeam/AdGuardHome/issues/7346),
> [#7390](https://github.com/AdguardTeam/AdGuardHome/issues/7390)); `tcp://` é protocolo
> **oficialmente suportado**. Com TCP: **8/8**. O Pi-hole segue em UDP pelo loopback (rápido e
> estável) e vence a corrida.

### Dashboard

Entrada no **Homepage** (ybytu, grupo *Kavure*) — informativa, sem `href` (o proxy não tem
UI). Backup: `/home/ubuntu/homelab/homepage/config/services.yaml.bak-20261006-dnscrypt`.
Como o Homepage renderiza no cliente, a conferência visual deve ser feita no navegador.

Para auditar o relay em uso (temporário, remover depois):
adicionar `[query_log]` com `file = "/dev/stdout"` e ver a **8ª coluna** (relay).

## Rollback (1 linha)

```bash
docker exec pihole pihole-FTL --config dns.upstreams '["9.9.9.9", "8.8.8.8"]'
```
Backup do config do Pi-hole: `/srv/data/pihole/etc-pihole/pihole.toml.bak-20261006-dnscrypt`.

## Tentativa no ybytu — descartada por ora (06/10/2026)

Um segundo proxy foi instalado no ybytu (Opção A: `172.17.0.1:5053`, AdGuard →
`upstream_dns: ['172.17.0.1:5053']`, `fallback_dns: ['9.9.9.9','8.8.8.8']`). **Funcionou**
(anonymizing via CryptoStorm, AdGuard a ~134 ms), mas apresentou **instabilidade
recorrente a partir da Oracle** (`[ERROR] Resolver couldn't be reached anonymously`), além
de exigir exceção no `INPUT` default-deny (bridge Docker → porta 5053).

**Decisão:** reverter o ybytu para os upstreams DoH/DoT originais, **mantendo** as
melhorias `fallback_dns` e `cache_optimistic`. A configuração fica **estagiada** em
`/home/ubuntu/homelab/dnscrypt-proxy/` (coberta pelo `config-backup`) para nova tentativa
futura — candidata a investigação: alcançabilidade de relays UDP/443 a partir da Oracle.

## Observações

- Imagem **distroless** (sem shell) → **não** aceita healthcheck por script; a resiliência
  é `restart: unless-stopped` + o failover do Pi-hole (ver abaixo).
- **Falha do proxy:** o Pi-hole fica sem resposta e **a corrida da Tailscale entrega a
  consulta ao AdGuard (não-anonimizado, porém cifrado)** → sem perda de internet.
  Ver [`network/dns.md`](../network/dns.md).
