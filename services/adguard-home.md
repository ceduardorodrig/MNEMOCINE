---
tags: [homelab, service, adguard, dns]
---

# AdGuard Home

DNS com bloqueio de anúncios, rastreadores e telemetria — **container Docker no ybytu**.

**Servidor:** ybytu
**Porta DNS:** `53` (TCP/UDP, publicada pelo Docker em `0.0.0.0`)
**Porta Admin:** `3000`
**URL:** `http://ybytu.chimaera-heptatonic.ts.net:3000`

## Instância (revisado 06/10/2026)

Roda **apenas como container Docker**. Não existe instância nativa no host:

| Item | Valor |
|---|---|
| Container | `adguardhome` (`adguard/adguardhome:latest`, `restart: unless-stopped`) |
| Config | `/var/lib/docker/volumes/adguard_conf/_data/AdGuardHome.yaml` |
| Dados | `/var/lib/docker/volumes/adguard_workdir/_data/` (`querylog.json`, `stats.db`, `filters/`) |
| Compose | **não há** — os containers do ybytu foram criados com `docker run` (ver [`servers/ybytu.md`](../servers/ybytu.md)) |

> **Correção de doc antiga:** a versão anterior afirmava que "o binário nativo (`/opt/adguardhome/`) é a instância ativa". Errado: `/opt/adguardhome` é o caminho **de dentro do container** e não existe no host. O processo que aparecia no `ps aux` do host com esse caminho era o do próprio container (pai = `containerd-shim-runc-v2`) — investigado em 06/10 antes de qualquer mudança para evitar apagar um processo legítimo.

## Papel na rede — co-resolvedor (corrida com o Pi-hole)

Serve em **paralelo** ao [`Pi-hole`](pihole.md) (detalhes em [`network/dns.md`](../network/dns.md)):
a Tailscale encaminha cada consulta para os dois resolvers **em paralelo** (corrida) e usa
a primeira resposta. **Não é só failover:** a medição de 08/10/2026 mostra que o vencedor
não é fixo — o AdGuard ganha sempre que tem o nome em cache e o Pi-hole não. Medições:

| Métrica | Pi-hole (kavure) | AdGuard (ybytu) |
|---|---|---|
| Latência | ~2 ms (LAN, cache) | ~66 ms (Oracle + tailnet) |
| Vence quando **os dois** têm em cache | ✅ (2 ms) | — |
| Vence quando **só ele** tem em cache | — (~290 ms) | ✅ (35–92 ms) |
| Tráfego real | ~5 M consultas/28 d | recebe **todas** as corridas + tráfego local |

> **Limitação de cliente:** como a porta é publicada pelo Docker (userland-proxy), o
> querylog registra **tudo como `172.17.0.1`** — o IP real do device se perde.
> (O Pi-hole usa `network_mode: host` justamente para preservar os IPs.)
> Candidatos a correção futura: `userland-proxy: false` no `daemon.json` (host fora do
> Swarm) ou `network_mode: host` — **exige pesquisa/documentação antes de mudar**.

## Listas de bloqueio (9 — 06/10/2026)

| # | Lista | Papel |
|---|---|---|
| 1 | AdGuard DNS filter | privacidade/segurança base |
| 2 | AdAway (`filter_2`) | anúncios |
| 3 | HaGeZi Normal (`filter_34`) | bloqueio geral |
| 4 | Phishing Army (`filter_18`) | phishing |
| 5 | NoCoin (`filter_8`) | crypto-mining |
| 6 | AdGuard Portuguese (`extension/chromium/filters/2.txt`) | PT-BR |
| 7 | HaGeZi Windows/Office tracker (`filter_63`) | telemetria Microsoft |
| 8 | **WindowsSpyBlocker `spy.txt`** | +06/10 — paridade com o Pi-hole |
| 9 | **fightback-consumer-tv core** | +06/10 — Smart TV (118 entradas, CC0) |

> **Decisão registrada (06/10):** o **OISD big NÃO foi adicionado** ao AdGuard. São
~1,4 M de regras em RAM num host de 954 MB (swap já em ~750 MB) — risco de OOM real.
A paridade de *política* foi feita pelas regras de usuário abaixo, que cobrem os
domínios onde as listas divergiam de fato (medido por bateria de `dig` nos dois).

## Regras de usuário (`user_rules` — 17, 06/10/2026)

Espelho dos **deny exatos do Pi-hole** + vazamentos medidos:

- **Microsoft (8 exatas):** `telemetry.microsoft.com`, `telemetry.microsoft.us`,
  `settings-win.data.microsoft.com`, `vortex.data.microsoft.com`,
  `v10.events.data.microsoft.com`, `settings-sandbox.data.microsoft.com`,
  `settings-ios.events.data.microsoft.com`, `diagnostics.support.microsoft.com`
- **Regex:** `/(^|\.)events\.data\.microsoft\.com$/`
- **Vazamentos medidos:** `firebaselogging.googleapis.com`, `ads.spotify.com`,
  `browser.events.data.msn.com`
- **Smart TV:** `us.lgtvsdp.com` (LG)
- **Blocklist BR (aprovada pelo usuário, 06/10):** `ge.globo.com`,
  `analytics.mercadolivre.com.br`, `log.ifood.com.br`

> Para desbloquear em caso de quebra: remover a linha em `user_rules` e `docker restart adguardhome`.
> Complemento de bloqueio BR/TV: [`pihole.md`](pihole.md).

## Upstreams

```
tcp://100.124.146.77:5053    (unbound recursivo do kavure — endpoint inalterado desde 06/10;
                               até 08/10/2026 havia um dnscrypt-proxy atrás dele)
```

**Fallback (cifrado, 06/10/2026):** `fallback_dns = ['tls://9.9.9.9', 'tls://1.1.1.1']`
— Quad9 (fundação suíça, sem fins lucrativos) e Cloudflare, ambos em **DoT**. Antes estava
vazio (uma falha de DoH derrubava a resolução).

**Cache:** `cache_optimistic = true` — responde com cache expirado enquanto revalida.

> **Por que TCP e não UDP (pendência ENCERRADA — 07/10/2026):** o caminho UDP do dnsproxy
> apresentou timeouts intermitentes (4/6) para o upstream do kavure, enquanto sockets UDP crus
> passavam 6/6 e 20/20 numa rajada — ou seja, **não é a rede**. Pesquisa nas fontes
> oficiais mostrou que é uma **classe de bug conhecida do AdGuard Home com UDP**:
> [issue #7628](https://github.com/AdguardTeam/AdGuardHome/issues/7628) (timeouts esporádicos em
> UDP — o relator registra explicitamente que **o Pi-hole, com os MESMOS upstreams, não tem
> timeout**), [#7346](https://github.com/AdguardTeam/AdGuardHome/issues/7346) (buffers de socket
> do kernel; quem trocou de transporte não viu mais timeouts) e
> [#7390](https://github.com/AdguardTeam/AdGuardHome/issues/7390).
>
> **`tcp://` é protocolo oficialmente suportado** ("Regular DNS (over TCP)", na doc de upstreams
> do AGH) — não é gambiarra. Com TCP: **8/8**. *Nota 08/10 (corrigida no mesmo dia):* os `EOF`
> intermitentes (`exchange failed ... over tcp: EOF`) **não eram do dnscrypt** — persistiram
> com o unbound (123 em 50 min) até a causa raiz: `incoming-num-tcp: 10`/thread (20
> simultâneas) estourava em rajada e o unbound fechava as conexões excedentes. **Corrigido**
> (`incoming-num-tcp: 64`) e provado: 216 TCP paralelas → 0 EOF e **0 erros** no AdGuard
> pós-fix — ver [`unbound.md`](unbound.md), seção *Correção TCP*. O AdGuard **não é só
> failover** (a corrida não tem vencedor fixo — ver [`network/dns.md`](../network/dns.md)),
> mas em nenhum momento houve perda de internet.
> **Pendência fechada com causa raiz identificada.**

## Instância (revisado 06/10/2026)

- **Container:** `adguardhome` — agora **em compose** (`/home/ubuntu/homelab/adguardhome/compose.yml`),
  corrigindo o débito de `docker run` órfão.
- **Healthcheck:** `nslookup example.com 127.0.0.1` (a imagem tem `nslookup`) — passa a ser
  coberto pelo `autoheal`.
- **Volumes:** `adguard_conf` / `adguard_workdir` (nomeados, externos).

### Tentativa de anonimato local no ybytu — revertida (06/10/2026)

Foi instalado um `dnscrypt-proxy` local no ybytu (bind `172.17.0.1:5053`) para dar
**anonimato** ao failover; chegou a funcionar, mas apresentou **instabilidade recorrente a
partir da Oracle** (`[ERROR] Resolver couldn't be reached anonymously`). **Superado pela
Opção A**: o AdGuard passou a consumir o upstream do **kavure** (o `dnscrypt-proxy` até
08/10/2026, o `unbound` daí em diante), mantendo o failover (que degrada para o
`fallback_dns` cifrado). A config local ficou estagiada em `/home/ubuntu/homelab/dnscrypt-proxy/`.

## Querylog e estatísticas

- Config: `querylog.interval: 7d` (era `90d`) · `size_memory: 200` (era `1000`) · `enabled/file_enabled: true`.
- **Por que o log parecia "congelado":** o AdGuard só grava em disco quando o buffer de
  `size_memory` **entradas** enche (ou no desligamento) — não é defeito. Fonte oficial:
  [`internal/querylog/querylog.go`](https://github.com/AdguardTeam/AdGuardHome/blob/master/internal/querylog/querylog.go)
  (*"The number of entries kept in a memory buffer before they are flushed to disk"*).
  Com `1000`, o arquivo ficava horas sem escrita; com `200` o flush sai a cada ~200 consultas.
- Arquivo: `.../adguard_workdir/_data/data/querylog.json`; rotacionado a cada `interval`
  (retenção efetiva = 2× o intervalo).
- **`querylog.json.1` = 1,6 GB** (histórico de ~6 semanas, até 06/10).
  **Decisão do usuário (06/10): manter até 13/10** — a própria rotação (`interval: 7d`)
  o sobrescreve no próximo ciclo, então não exige ação manual.
  Troca `90d → 7d` devolveu ~2,4 GB de disco (48 GB → 20 GB livres).

## Backup

- **06/10/2026:** `config-backup` do ybytu passou a espelhar também
  `/var/lib/docker/volumes/adguard_conf` → NAS `/mnt/BACKUP/configs-homelab/ybytu/adguard_conf/`
  (antes só `/home/ubuntu/homelab`; ver [`backups/strategy.md`](../backups/strategy.md)).
- Backups de pré-mudança mantidos e documentados:
  `AdGuardHome.yaml.bak-20261006-parity` (no volume) e `/etc/config-backup.conf.bak-20261006`.

## Acesso Admin

```
URL: http://ybytu.chimaera-heptatonic.ts.net:3000
```

- **Login:** a senha admin é **hash (bcrypt)** no `AdGuardHome.yaml` (`users:`) — **não vai ao store sops** (não reutilizável).
- **Reset de senha:** gerar novo hash bcrypt e injetar no YAML:
  ```bash
  htpasswd -B -C 10 -n -b admin '<NOVA_SENHA>'      # ou: mkpasswd -m bcrypt -R 10 '<NOVA_SENHA>'
  ```
  Copiar a parte `$2y$...` para `users:` → `password:` em
  `/var/lib/docker/volumes/adguard_conf/_data/AdGuardHome.yaml` e `docker restart adguardhome`.
  Ver [wiki de configuração do AdGuard Home](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#reset-web-password).

## Manutenção

```bash
# Status e logs
docker ps --filter name=adguardhome
docker logs --tail 100 adguardhome

# Mudança no YAML (para → edita → start): o AGH grava a própria config no SIGTERM
docker stop adguardhome && docker start adguardhome

# Health geral do host
stenio --health
```
