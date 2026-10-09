---
tags: [homelab, service, dnscrypt, dns, kavure]
---

# dnscrypt-proxy

> ## ⛔ DESATIVADO em 08/10/2026 — substituído pelo [`unbound`](unbound.md) · **COLD STORAGE**
>
> O egress anonimizado custava **353 ms por consulta fria** (dois saltos EUA, sem relay
> na América do Sul) e a navegação ficou lenta. O **unbound recursivo nativo** assumiu a
> porta `5053` — os upstreams do Pi-hole/AdGuard **não mudaram de endpoint**, só o que
> há atrás deles. Metodologia completa em [`../guides/cold-storage-servicos.md`](../guides/cold-storage-servicos.md).
>
> **Congelamento aplicado (08/10/2026):**
> - `profiles: ["cold"]` + `restart: "no"` no compose (backup `compose.yml.bak-20261008-cold`)
>   → o `docker compose up -d` da rotina **nem enxerga** o serviço;
> - container `exited` com policy `no` (`docker update --restart=no`);
> - **fail-closed provado:** subir de propósito → `[FATAL] listen udp4 127.0.0.1:5053:
>   bind: address already in use`, exit 255, **sem crash-loop**, unbound intacto;
> - **backup provado:** `/srv/data/dnscrypt-proxy/` (compose + `.bak` + `config/`)
>   espelhado no NAS via `hl-config-backup` (execução manual confirmada 08/10).
>
> **Rollback (reativação):**
> ```bash
> systemctl stop unbound                                  # libera a 5053
> # reverter hl-dns-watchdog.service: --service unbound → --container dnscrypt-proxy
> cd /srv/data/dnscrypt-proxy && docker compose --profile cold up -d
> docker update --restart=unless-stopped dnscrypt-proxy   # policy antiga (opcional)
> ```
> (Reverter também o watchdog: `--service unbound` → `--container dnscrypt-proxy`.)
> Este doc ficou como **referência histórica e de rollback**.

Camada de **egress DNS cifrado e anonimizado** do homelab — roda no **kavure**, atrás do
Pi-hole (ver [`pihole.md`](pihole.md)). **Desativado em 08/10/2026** (ver nota acima).

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

| Elemento | Operador | Endpoints |
|---|---|---|
| Servidores | `dnscry.pt` (**operador A**) | `dnscry.pt-tampa/miami/jacksonville/atlanta-ipv4` |
| Relays | CryptoStorm (**EUA**) | `anon-cs-{fl,ga,dc,nyc,il,la}` (Miami/Atlanta/DC/Nova York/Chicago/LA) |

> ⚠️ **Regra de ouro do anonimato:** relay e servidor têm de ser de **operadores
> diferentes**. A doc dos servidores avisa que *"all dnscry.pt resolvers can also be used
> as Anonymized DNSCrypt relays"* — parear `dnscry`↔`dnscry` faria **uma única entidade**
> enxergar IP + consulta (anonimato nulo).

### Relays: 100% EUA — prioridade LATÊNCIA (08/10/2026)

**Histórico:** em **07/10** os relays foram espalhados por **6 operadores e 6 países**
(Scaleway/Holanda, DNSWarden/Suíça, litepay/NL, μODNS/JP, Tiarap/SG) para dar redundância de
anonimato. **Em 08/10 isso foi revertido:** o desvio transatlântico (**Brasil → Europa → EUA**)
custava **+200 ms por consulta fria** e a navegação ficou perceptivelmente mais lenta
("segundos" num primeiro acesso).

```toml
routes = [
  { server_name = 'dnscry.pt-miami-ipv4',        via = ['anon-cs-fl', 'anon-cs-ga', 'anon-cs-dc'] },
  { server_name = 'dnscry.pt-tampa-ipv4',        via = ['anon-cs-ga', 'anon-cs-dc', 'anon-cs-nyc'] },
  { server_name = 'dnscry.pt-jacksonville-ipv4', via = ['anon-cs-dc', 'anon-cs-fl', 'anon-cs-il'] },
  { server_name = 'dnscry.pt-atlanta-ipv4',      via = ['anon-cs-nyc', 'anon-cs-il', 'anon-cs-la'] }
]
```

- **Relays:** todos **CryptoStorm (EUA)**, em cidades diferentes (FL/GA/DC/NYC/IL/LA) para não
  concentrar num único PoP. Como é **operador único**, a diversidade de operador fica por conta
  do **fallback DoT do AdGuard** (`tls://9.9.9.9`) se a CryptoStorm cair.
- **Latência fria medida:** **~160–310 ms** (EUA) · era **~360–550 ms** com os relays europeus.
  RTT do servidor mais rápido (miami): **127 ms**.
- **Trade-off assumido:** menos redundância de operador em troca de navegação ~2× mais rápida.
  Reverter é só recolocar relays não-EUA nas rotas — backup:
  `dnscrypt-proxy.toml.bak-20261008-latency`.
- **`skip_incompatible = true`** → nunca cai para conexão direta (sem vazar o IP).
- **Failover completo:** se *todos* os relays caírem, o proxy não resolve → o Pi-hole para →
  a corrida entrega ao AdGuard, que cai no **DoT cifrado** → **sem perda de internet**
  (só degrada o anonimato para "cifrado").

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
| `cache_min_ttl` | **`2400`** | valor do **exemplo oficial** (wiki *Performance*): retém ≥40 min → menos re-consultas no caminho anonimizado. *Revisado 08/10/2026 — a decisão anterior (`0`) contrariava a doc* |
| `block_ipv6` | **`true`** | **sem IPv6** na rede → responde AAAA na hora (0–1 ms) em vez de consultar o upstream à toa (wiki *Performance*) |
| `cache_max_ttl` | `86400` | teto são. **Com `0` o cache não funciona** (erro cometido e corrigido em 06/10) |
| `keepalive` | `30` | conexões quentes |
| `lb_estimator` / `lb_strategy` | `true` / `wp2` | escolhe o servidor mais rápido medido |
| `cert_refresh_delay` | `60` (min) | o relay é sorteado por servidor **por ciclo**; 60 min = rotação/recuperação mais rápidas (era 240) |
| `[anonymized_dns] routes` | 3 relays/servidor, **CryptoStorm EUA** | prioridade latência (08/10) — ver acima |
| `skip_incompatible` | `true` | nunca contornar o relay (sem vazamento do IP) |
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

> ⛔ Serviço em **cold storage** desde 08/10/2026 — qualquer comando de gestão do
> container exige o perfil: `docker compose --profile cold ...`.

```bash
cd /srv/data/dnscrypt-proxy
docker compose --profile cold ps
docker logs --tail 50 dnscrypt-proxy      # pares "Anonymizing ... via ..." (se ativo)
docker compose --profile cold restart      # só com unbound parado (porta 5053)
```

### Watchdog (Rust) — `hl-dns-watchdog` (**repontado em 08/10 para o unbound**)

A imagem é *distroless* (sem shell), então **não aceita healthcheck interno**. A cobertura
vinha de um **watchdog externo em Rust** (`scripts/dns-watchdog/`, binário em
`/usr/local/bin/dns-watchdog` no kavure), disparado por `hl-dns-watchdog.timer` a cada
**2 min**. **Desde 08/10/2026** a unit roda `--service unbound` (flag nova no binário) e
faz `systemctl restart unbound` — ver [`unbound.md`](unbound.md). Restaurar o proxy exige
reverter a unit para `--container dnscrypt-proxy`. Log: `journalctl -u hl-dns-watchdog.service`.

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
> estável); a corrida **não tem vencedor fixo** (ver [`network/dns.md`](../network/dns.md)).

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
