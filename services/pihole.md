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
> **Resolver global da tailnet:** um dos dois resolvers da corrida Tailscale (ver [`network/dns.md`](../network/dns.md)). **Upstream (desde 08/10/2026):** `127.0.0.1#5053` — o **`unbound` recursivo local** (DNSSEC). Até 08/10 era o `dnscrypt-proxy` (Anonymized DNSCrypt); o endpoint é o mesmo, mudou o serviço atrás dele ([`unbound.md`](unbound.md)). Sem DNS plano no caminho normal.

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

## Egress recursivo local (implementado 08/10/2026)

O upstream do Pi-hole é **`127.0.0.1#5053`** — o **`unbound` recursivo nativo** no kavure
(raiz → TLD → autoritativo, com validação DNSSEC). Medições e config em
[`unbound.md`](unbound.md).

- **Endpoint inalterado:** o `FTLCONF_dns_upstreams` do `compose.yml` continua
  `127.0.0.1#5053` — a troca dnscrypt → unbound foi transparente para o compose
  (mesma porta).
- **Upstream único (`127.0.0.1#5053`).** O FTL recebe **só** o unbound — em operação normal
  toda consulta forwardada vai para o unbound (privacidade: nada sai em claro). O failover do
  Pi-hole é a **corrida da Tailscale → AdGuard** (que tem fallback DoT): com o unbound parado,
  consultas via `100.100.100.100` seguem resolvendo (provado 08/10: 131/87 ms). Ver
  [`network/dns.md`](../network/dns.md).

> **⚠️ Fallback próprio do Pi-hole — investigado e descartado por ora (08/10/2026).**
> Tentamos dar ao Pi-hole o mesmo fallback do AdGuard (Quad9 plano), medindo pela coluna
> `forward` do FTL. **Nenhum modo do FTL expressa "prefira unbound → Quad9 só na queda →
> volte sozinho":**
> - **multi-upstream `[unbound, 9.9.9.9, 149.112.112.112]`** (default): o FTL **não prefere**
>   o unbound. Depois de uma queda ele **gruda no Quad9** e segue mandando consultas em
>   claro mesmo com o unbound saudável (medido: 10/10 nomes frios → `9.9.9.9`); **não volta
>   sozinho** (≥25 min observados). `pihole reloaddns` **não** reseta a escolha.
> - **`strict-order`** (força a ordem): prefere o unbound, mas **quebra o failover** — com o
>   unbound parado, **8/8 consultas deram timeout** (o dnsmasq insiste no 1º e o cliente
>   desiste antes de tentar o Quad9). Confirma a nota antiga do homelab.
> - `pihole restartdns` **não existe no v6**; só `docker restart pihole` reseta (com blip).
>
> **Decisão:** manter **upstream único** (normal = sempre unbound) e usar a corrida/AdGuard
> como fallback. Para um **fallback próprio do Pi-hole com privacidade** (preferir unbound +
> DoT na queda + retorno automático), o caminho limpo é um **forwarder local dedicado**
> (127.0.0.1 → unbound, com fallback cifrado) — **pendente de decisão**. Backups do
> experimento: `compose.yml.bak-20261008-upstreams` e `.bak-20261008-strictorder`.

**Medições (08/10/2026, com unbound):** cache quente **~19–22 ms**; consulta fria
**160–484 ms** (média ~280 ms; registries DNSSEC pagam mais na 1ª consulta) contra
**353 ms** da era dnscrypt. Poucas consultas chegam ao upstream — **medido 08/10**
(24 h): **85 799** consultas, **45,7%** servidas de cache, **43,2% bloqueadas**,
**8,8%** forwardadas ao unbound (numa hora de pico o forward caiu a **3,6%**). O
`optimizer` do Pi-hole serve cache expirado por até 1 h enquanto revalida — o custo real
recai na **primeira visita** a cada domínio novo.

> **Paridade de bloqueio (medida 08/10/2026):** Pi-hole **43,2%** (24 h) × AdGuard
> **44%** (log completo) → as duas listas estão de fato alinhadas (a paridade foi
> construída em 06/10 — ver [`network/dns.md`](../network/dns.md)). Isso importa porque a
> corrida da Tailscale **não** tem vencedor fixo (medição 08/10: ver dns.md).

> **Histórico da decisão:** o Pi-hole v6 (Core 6.4.3 / FTL 6.7.1) **não** aceita upstream
> `tls://`/`https://`; o v7 trará DoT/DoH nativos mas **não ODoH**. Alternativas avaliadas:
> **dnscrypt-proxy** (escolhido em 06/10, **descartado em 08/10** por 353 ms frios — ver
> [`dnscrypt-proxy.md`](dnscrypt-proxy.md)), **cloudflared** (depreciado pela Cloudflare
> em 02/2026), **ODoH** (só 2 relays no registro oficial) e **unbound** (descartado em
> 06/10 por "não esconder da operadora", **reavaliado e adotado em 08/10**: recursão
> própria sem provedor central, com latência de rede local — o trade-off aceito foi ISP
> vendo tráfego DNS genérico).

**Rollback (1 linha):** `docker exec pihole pihole-FTL --config dns.upstreams '["9.9.9.9", "8.8.8.8"]'`
Backup do config: `/srv/data/pihole/etc-pihole/pihole.toml.bak-20261006-dnscrypt`.
