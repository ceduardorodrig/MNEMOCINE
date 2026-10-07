---
tags: [homelab, service, pihole, dns]
---

# Pi-hole

DNS com bloqueio de anúncios — **container Docker no kavure** (migrado 09/08/2026, antes era kuaray).

**Servidor:** kavure
**Porta:** `53` (TCP/UDP, tailnet) · **Admin:** `http://100.124.146.77/admin`
**URL:** `http://kavure.chimaera-heptatonic.ts.net/admin`
**Senha admin:** `PI_HOLE_ADMIN_PASSWORD` no store sops (`/mnt/NVME_PCI/secrets/secrets.env`).

> **Config "ver IPs reais dos devices"** (recriada 09/08): `network_mode: host` + `FTLCONF_dns_listeningMode: BIND` + `FTLCONF_dns_interface: tailscale0` — escuta só na interface tailscale e enxerga o IP de cada device (não conflita com o systemd-resolved do kavure em `127.0.0.53`).
> **Resolver global da tailnet:** um dos dois resolvers da corrida Tailscale (ver [`network/dns.md`](../network/dns.md)). **Upstream (desde 06/10/2026):** `127.0.0.1#5053` — o `dnscrypt-proxy` local (Anonymized DNSCrypt), **único** upstream. Sem DNS plano no caminho normal.

## Listas de bloqueio (18/08/2026 — revisado)

> **Nota importante:** Pi-hole v6 **parseia sim** listas ABP-style (`||domínio^`)? — o OISD big é distribuído em ABP e foi corretamente consumido como "ABP-style domains". Para listas em formato hosts/domain, também funciona.
> **Gerenciamento:** a v6 armazena as adlists no **gravity.db** (não no `adlists.list`). Inserir via:
> `sqlite3 /srv/data/pihole/etc-pihole/gravity.db "INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('<url>',1,'');"` + `docker exec pihole pihole -g`.
> ⚠️ gravity.db é **excluído** do config-backup (`*.db`) — a fonte da verdade das listas é ESTE DOC.

**8 listas (gravity: 465.077 domínios / 445.888 únicos — medido em 06/10/2026):**

1. StevenBlack hosts — ads/malware base
2. AdAway (registry `filter_2.txt`) — ads
3. Phishing Army (registry `filter_18.txt`) — phishing
4. NoCoin (registry `filter_8.txt`) — crypto-mining
5. WindowsSpyBlocker (`data/hosts/spy.txt`) — telemetria Windows (parcial)
6. **OISD big** (`https://big.oisd.nl`) — **substituiu a 1Hosts Xtra em 18/08**: cobertura grande (~1.4M hosts equivalentes) com **prioridade em funcionalidade e baixo falso positivo** ("Block. Don't break.")
7. **fightback-consumer-tv core** (`blocklists/hosts/fightback-tv-core.txt`, CC0) — **+06/10**: 118 endpoints de Smart TV (Roku/Samsung/LG/Amazon/Apple/Xiaomi/Sony). Lista do autor BR com lista-irmã `do-not-block` (73 domínios que **não** podem ser bloqueados — loja de apps, firmware, EPG, relógio) — domains que quebram TV são excluídos na geração.
8. **HaGeZi Windows/Office tracker** (registry `filter_63.txt`) — **+06/10**: 381 regras ABP de rastreadores Windows/Office (paridade com o AdGuard, que já a usava)

> **Histórico — por que saiu a 1Hosts Xtra:** em 18/08 a Xtra (~1.1M hosts) gerou uma cascata de falsos positivos que quebravam sites funcionais (pzwiki.net, CDNs do turbo.cr, backend do Darktide `fatsharkgames.com`/`atoma.cloud`). Foi substituída pelo OISD big, que bloqueia volume similar sem derrubar serviços legítimos. **As whitelists manuais criadas para contornar a Xtra foram todas removidas** — com o OISD os domínios voltaram a resolver sem allow.

## Telemetria Microsoft (denylist exata — prioridade)

Adicionados como **exact deny** (não dependem de lista):

- `telemetry.microsoft.com`, `telemetry.microsoft.us`
- `settings-win.data.microsoft.com`, `vortex.data.microsoft.com`
- `v10.events.data.microsoft.com`, `settings-sandbox.data.microsoft.com`
- `settings-ios.events.data.microsoft.com`, `diagnostics.support.microsoft.com`
- Wildcard: `events.data.microsoft.com` (`*.events.data.microsoft.com`)

Validado 09/08: todos → `0.0.0.0` (bloqueado) na tailnet inteira.

### Deny exatos adicionados em 06/10/2026 (paridade + blindagem)

A bateria de `dig` comparando os dois resolvers encontrou vazamentos em ambos e um
conjunto de domínios bloqueado só no AdGuard. Para que a corrida da Tailscale seja
**determinística** (quem responde primeiro aplica as suas regras), os dois lados
passaram a ter o mesmo conjunto:

- **Vazavam nos DOIS (agora negados nos dois):** `browser.events.data.msn.com`,
  `us.lgtvsdp.com` (LG)
- **Blocklist BR (aprovada pelo usuário):** `ge.globo.com`,
  `analytics.mercadolivre.com.br`, `log.ifood.com.br`
  > Se algum app/site do grupo Globo/ML/iFood quebrar após a mudança,
  > desbloquear com `docker exec pihole pihole allow <domínio>` e documentar aqui.

**Total:** 13 deny exatos + 1 regex (gravity confirmada 06/10).

Aplicação: `docker exec pihole pihole deny <domínio>` (recarrega o DNS automaticamente).

### Regras espelhadas no AdGuard (06/10/2026)

Os mesmos 13 deny + a regex + `firebaselogging.googleapis.com` e `ads.spotify.com`
(saíam bloqueados aqui pelo OISD e não no AdGuard) foram para os `user_rules` do
AdGuard Home — ver [`adguard-home.md`](adguard-home.md). Bateria final de verificação
(06/10): **todos os alvos de telemetria/BR/TV → `0.0.0.0` nos dois resolvers**, e
domínios de sanidade (Google, Facebook, Instagram, iFood, Globoplay) continuam resolvendo.

## Whitelist manual (histórico — REMOVIDA em 18/08/2026)

A tabela abaixo documenta o que **já foi** whitelistado e **removido** em 18/08 junto com a troca Xtra → OISD. Sem a 1Hosts Xtra, nenhum destes domínios precisa de allow — todos resolvem normalmente via OISD:

- `static.licdn.com`, `static.es.lnkdns.net`, `platform.linkedin.com` (LinkedIn)
- `log.tailscale.com` (admin console Tailscale)
- `pzwiki.net` (wiki Project Zomboid)
- `static.scdn.st` (CDN turbo.cr)
- `bunnyfonts.b-cdn.net` (fontes Bunny)
- `fatsharkgames.com`, `telemetry-global.fatsharkgames.com` (backend Darktide)
- `atoma-discovery.com`, `bsp-sup-sd.atoma-discovery.com` (discovery Darktide)
- `atoma.cloud`, `bsp-auth-prod.atoma.cloud`, `bsp-td-prod.atoma.cloud`, `bsp-cdn-prod.atoma.cloud` (serviços Atoma Darktide)

> Se um domínio funcional voltar a quebrar com o OISD, aí sim criar um allow pontual e documentar aqui — mas com o OISD isso deve ser raro.
> Aplicar allow (se necessário no futuro): `docker exec pihole pihole allow <domínio>` (recarrega o DNS automaticamente).

## Instância

- Compose: `/srv/data/pihole/compose.yml` (`network_mode: host`).
- Config: `/srv/data/pihole/etc-pihole/` (espelhada no NAS via `config-backup` do kavure).
- Atualizar gravity: `docker exec pihole pihole -g`.

## Egress anonimizado (implementado 06/10/2026)

O upstream do Pi-hole é **`127.0.0.1#5053`** — o `dnscrypt-proxy` local em modo
**Anonymized DNSCrypt** (relay ≠ servidor, de operadores diferentes). Detalhes, parâmetros
e medições em [`dnscrypt-proxy.md`](dnscrypt-proxy.md).

- Aplicado com: `docker exec pihole pihole-FTL --config dns.upstreams '["127.0.0.1#5053"]'`.
- **Desde 06/10 o upstream é declarativo no `compose.yml`** (`FTLCONF_dns_upstreams`), então
  o compose é a fonte da verdade (o campo fica read-only na UI). O valor efetivo continua
  `[127.0.0.1#5053]`.
- **Sem `strict-order` e sem upstream plano.** Esta decisão veio de teste: com
  `strict-order` + fallback plano (`9.9.9.9`), o dnsmasq **não fazia failover** quando o
  proxy morria (6 timeouts seguidos) — o Pi-hole viraria dependência dura e silenciosamente
  quebrada.
- **O failover é a corrida da Tailscale → AdGuard** (também cifrado, embora não
  anonimizado). Com o proxy parado, consultas via `100.100.100.100` seguem resolvendo
  (medido: 153–169 ms) porque o AdGuard responde primeiro. Ver
  [`network/dns.md`](../network/dns.md).

**Medições (06/10/2026):** cache quente **0 ms**; consulta fria **147–323 ms** (média
~220 ms) contra ~18 ms do DNS plano anterior. Apenas **4,5%** das consultas chegam ao
upstream (o resto é cache/bloqueio) e o `optimizer` do Pi-hole serve cache expirado por até
1 h enquanto revalida — o custo real recai na **primeira visita** a cada domínio novo.

> **Histórico da decisão:** o Pi-hole v6 (Core 6.4.3 / FTL 6.7.1) **não** aceita upstream
> `tls://`/`https://`; o v7 trará DoT/DoH nativos mas **não ODoH**. Alternativas
> descartadas: **Unbound** (não esconde da operadora), **cloudflared** (depreciado pela
> Cloudflare em 02/2026), **ODoH** (só 2 relays no registro oficial).

**Rollback (1 linha):** `docker exec pihole pihole-FTL --config dns.upstreams '["9.9.9.9", "8.8.8.8"]'`
Backup do config: `/srv/data/pihole/etc-pihole/pihole.toml.bak-20261006-dnscrypt`.
