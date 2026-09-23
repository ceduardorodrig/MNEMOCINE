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
> **Resolver global da tailnet:** aponta para `100.124.146.77` (kavure). Upstream: Google `8.8.8.8/8.8.4.4`.

## Listas de bloqueio (18/08/2026 — revisado)

> **Nota importante:** Pi-hole v6 **parseia sim** listas ABP-style (`||domínio^`)? — o OISD big é distribuído em ABP e foi corretamente consumido como "ABP-style domains". Para listas em formato hosts/domain, também funciona.
> **Gerenciamento:** a v6 armazena as adlists no **gravity.db** (não no `adlists.list`). Inserir via:
> `sqlite3 /srv/data/pihole/etc-pihole/gravity.db "INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('<url>',1,'');"` + `docker exec pihole pihole -g`.
> ⚠️ gravity.db é **excluído** do config-backup (`*.db`) — a fonte da verdade das listas é ESTE DOC.

**6 listas (gravity ~512.000 domínios):**

1. StevenBlack hosts — ads/malware base
2. AdAway (registry `filter_2.txt`) — ads
3. Phishing Army (registry `filter_18.txt`) — phishing
4. NoCoin (registry `filter_8.txt`) — crypto-mining
5. WindowsSpyBlocker (`data/hosts/spy.txt`) — telemetria Windows (parcial)
6. **OISD big** (`https://big.oisd.nl`) — **substituiu a 1Hosts Xtra em 18/08**: cobertura grande (~1.4M hosts equivalentes) com **prioridade em funcionalidade e baixo falso positivo** ("Block. Don't break.")

> **Histórico — por que saiu a 1Hosts Xtra:** em 18/08 a Xtra (~1.1M hosts) gerou uma cascata de falsos positivos que quebravam sites funcionais (pzwiki.net, CDNs do turbo.cr, backend do Darktide `fatsharkgames.com`/`atoma.cloud`). Foi substituída pelo OISD big, que bloqueia volume similar sem derrubar serviços legítimos. **As whitelists manuais criadas para contornar a Xtra foram todas removidas** — com o OISD os domínios voltaram a resolver sem allow.

## Telemetria Microsoft (denylist exata — prioridade)

Adicionados como **exact deny** (não dependem de lista):

- `telemetry.microsoft.com`, `telemetry.microsoft.us`
- `settings-win.data.microsoft.com`, `vortex.data.microsoft.com`
- `v10.events.data.microsoft.com`, `settings-sandbox.data.microsoft.com`
- `settings-ios.events.data.microsoft.com`, `diagnostics.support.microsoft.com`
- Wildcard: `events.data.microsoft.com` (`*.events.data.microsoft.com`)

Validado 09/08: todos → `0.0.0.0` (bloqueado) na tailnet inteira.

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