---
tags: [homelab, server, ybytu, dns, monitoring, changedetection, ntfy]
---

# ybytu

> Hostname real do SO: `ybytu-vnic` (Tailscale exibe como `ybytu`)

**Papel:** Servidor cloud (Oracle Cloud) — DNS, dashboard, sincronização
**Shell padrão:** bash (`/bin/bash`)

## Hardware

| Item | Especificação |
|---|---|
| **SO** | Ubuntu 24.04.4 LTS |
| **Kernel** | 6.17.0-1020-oracle |
| **CPU** | AMD EPYC 7551 (2 vCPUs — Oracle free tier, 1 core/2 threads) |
| **RAM** | 954 MB (ZRAM: 477 MB, 354 MB em uso) |
| **Disco Sistema** | 50 GB — HDD virtual (Oracle Block Volume) — 17% usado (8 GB) |
| **Swap** | 477 MB (ZRAM) |
| **Tailscale IP** | 100.115.253.109 |
| **Tailscale DNS** | ybytu.chimaera-heptatonic.ts.net |
| **Rede** | Oracle internal network (`ens3`: 10.0.0.136/24, MTU 9000) |

## Papéis

- Exit Node da Tailnet
- DNS com bloqueio de anúncios (AdGuard Home)
- Dashboard central do homelab (Homepage)
- Monitoramento de uptime (Uptime Kuma)
- Monitoramento de mudanças em páginas (Changedetection.io)
- Notificações push (Ntfy)

## Tailscale Funnels

Nenhum.

## Containers Docker

| Container | Imagem | Portas | Função |
|---|---|---|---|---|
| adguardhome | adguard/adguardhome:latest | `0.0.0.0:53`, `0.0.0.0:3000` | DNS ad-blocking |
| homePage | ghcr.io/gethomepage/homepage:latest | `0.0.0.0:3001` | Dashboard homelab |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoramento |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `127.0.0.1:2375` | Proxy socket Docker |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| uptime-kuma | louislam/uptime-kuma:latest | `0.0.0.0:3002` | Monitoramento de uptime |
| changedetection | dgtlmoon/changedetection.io:latest | `0.0.0.0:8082` | Monitoramento de mudanças |
| ntfy | binwiederhier/ntfy:latest | `0.0.0.0:8083` | Notificações push |

## Programas Nativos

| Programa | Função | Porta |
|---|---|---|
| ~~filebrowser (systemd)~~ | ~~Servidor web de arquivos v2.63.5~~ — **removido/inativo (28/08/2026)**, unit não existe e porta fechada | ~~`8334`~~ |
| vnstat | Monitor de tráfego | — |
| tailscaled | Agente Tailscale (v1.98.4) | — |

## Portas Importantes

| Porta | Serviço | Bind |
|---|---|---|
| 53 | AdGuard Home (DNS) | `0.0.0.0` |
| 3000 | AdGuard Home (admin) | `0.0.0.0` |
| 3001 | Homepage | `0.0.0.0` |
| ~~8334~~ | ~~Filebrowser~~ | — |
| 2375 | Docker proxy | `127.0.0.1` |
| 61208 | Glances | `0.0.0.0` |
| 3002 | Uptime Kuma | `0.0.0.0` |
| 8082 | Changedetection | `0.0.0.0` |
| 8083 | Ntfy | `0.0.0.0` |

## Observações

- **AdGuardHome** roda **apenas como container** (nativo `/opt/adguardhome/` não existe mais).
- **Filebrowser**: **removido/inativo (28/08/2026)** — unit systemd não existe, binário não instalado, porta 8334 fechada. Doc anterior estava desatualizada.
- Containers **não usam Docker Compose** — foram iniciados individualmente.
- A pasta `/home/ubuntu/homelab/homepage/config/` contém os YAML de configuração do homepage.

## Atualização 28/08/2026

- **Upgrade completo** `apt dist-upgrade` (51 pacotes) + reboot. Kernel **6.17.0-1018 → 6.17.0-1020-oracle**.
- **Docker engine atualizado** (29.5.x → 29.7.2) junto com o apt. Containers com `restart: unless-stopped` subiram sozinhos.
- **Incidente pós-reboot:** host não voltou à tailnet + SSH não respondia banner (IP público `64.181.168.251`) → **force reboot** via painel OCI (OS Management) resolveu. A partir daí tailnet voltou, todos os 9 containers up (dockerproxy reiniciado manualmente após exit 255), exit node ativo, NFS automount (`/srv/backup-configs`, `/srv/backup-gitrepos` → NAS psicopompo) OK.
- **Fix NFS (10/09/2026):** Entries `hard` → `soft` no fstab (`configs-homelab`, `repos/git`). Backup: `/etc/fstab.bak.20260910`. Drop-in Docker: `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). Ver [`network/nfs.md`](../network/nfs.md).

## 06/10/2026 — Auditoria do stack DNS (Pi-hole × AdGuard)

### Incidente OOM (20:23–20:27 UTC)

- **Causa:** script de diagnóstico (agente) leu o `querylog.json` do AdGuard (1,6 GB) com
  `f.read()` **sem limite** → alocou ~1,6 GB num host de 954 MB → OOM killer.
- **Alvos do OOM:** o próprio `python3` **e o `tailscaled`** (mesmo cgroup via Tailscale SSH).
  O `tailscaled` religou sozinho em 20:24 (sem intervenção).
- **Sem reboot** (uptime continuou em 39 dias), os 11 containers ficaram de pé, load
  69 → 18 → normal. Impacto: ~4 min de AdGuard, Homepage, Uptime Kuma e ntfy fora.
- **Regra resultante:** no ybytu **nunca** ler arquivo grande de ponta a ponta — usar
  `tail -c N`, `seek` + janela, ou `head -c N`.

### Mitigação de risco (mesma sessão)

- `querylog.interval` **90d → 7d** e `size_memory` **1000 → 200**: o rotacionamento
  eliminou ~2,4 GB (restou só `querylog.json.1`, 1,6 GB) e o flush passou a sair a cada
  ~200 consultas. Disco: 20 GB livres (60%).
- `config-backup` passou a espelhar a config do AdGuard
  (`/var/lib/docker/volumes/adguard_conf`) — antes só `/home/ubuntu/homelab`.
  Backup pré-mudança: `/etc/config-backup.conf.bak-20261006`.
- **Mount NFS stale:** `/srv/backup-configs` estava com `Stale file handle` (o export do
  NAS estava saudável — o kavure lia normalmente). Corrigido com `umount -l` + retrigger
  do automount; o mount recriou com as opções corretas do fstab (`soft,timeo=30`) —
  **antes estava montado com `hard`** (desvio que o fstab não refletia, risco de deadlock
  previsto em `mnemocine/AGENTS.md`).
- **AdGuard:** 17 regras de usuário (paridade com os deny do Pi-hole + vazamentos medidos
  + blocklist BR) e 9 listas (novas: WindowsSpyBlocker e fightback-consumer-tv core);
  upstream Cloudflare DoH promovido a 1º (Quad9 dns10 com EOF recorrente) → latência
  110 ms → 66 ms. Detalhes em [`services/adguard-home.md`](../services/adguard-home.md).

### Correção de doc (não mexer)

- **Não existe binário nativo órfão do AdGuard:** o processo que aparecia no `ps aux` do
  host com caminho `/opt/adguardhome/AdGuardHome` é o **processo de dentro do container**
  (pai = `containerd-shim-runc-v2`), e `/opt/adguardhome` não existe no host.
  A doc antiga de `services/adguard-home.md` dizia que "o nativo é a instância ativa" —
  corrigido.

### Pendências

- **`querylog.json.1` (1,6 GB de histórico DNS de ~6 semanas):** decisão 06/10 —
  **manter até 13/10** (a rotação `7d` o sobrescreve sozinha; sem ação manual).
- Containers do ybytu continuam sem compose (`docker run` individual) — config-as-code pendente.
- Clientes do AdGuard aparecem todos como `172.17.0.1` (userland-proxy do Docker) — IP real perdido; candidatos: `userland-proxy: false` ou `network_mode: host` (pesquisar antes).
- Uptime Kuma: monitores de DNS (Pi-hole/AdGuard) **adiados em 06/10** — não há credencial dele no store sops; retomar quando existir.

### DNS: Opção A — AdGuard consumindo o proxy do kavure (06/10/2026)

- **AdGuard passou a `compose`** (`/home/ubuntu/homelab/adguardhome/compose.yml`) — corrige o
  débito de `docker run` órfão — **com healthcheck** (`nslookup example.com 127.0.0.1`),
  ficando coberto pelo `autoheal`.
- **Upstream:** `tcp://100.124.146.77:5053` (o `dnscrypt-proxy` do kavure, via tailnet) —
  assim **os dois resolvedores resolvem anonimizado**. Motivo do **TCP**: o caminho UDP do
  dnsproxy dava timeout intermitente (4/6), enquanto sockets UDP crus passavam 6/6 — é **bug
  conhecido do AdGuard Home com UDP** ([#7628](https://github.com/AdguardTeam/AdGuardHome/issues/7628)),
  e `tcp://` é protocolo oficialmente suportado; com TCP, 8/8.
- **Fallback:** `tls://9.9.9.9` → `tls://1.1.1.1` (DoT cifrado). Se o kavure (ou o proxy)
  cair, o AdGuard degrada para DoT — **sem perda de internet** (medido: 60 ms).

### Tentativa de proxy DNS anônimo local — superada pela Opção A (06/10/2026)

- Foi instalado um `dnscrypt-proxy` no ybytu (`/home/ubuntu/homelab/dnscrypt-proxy/`) para dar
  **anonimato** ao AdGuard no failover: `upstream_dns: ['172.17.0.1:5053']` +
  `fallback_dns: ['9.9.9.9','8.8.8.8']`.
- Chegou a funcionar (relays CryptoStorm, AdGuard a ~134 ms, captura confirmando
  `172.17.0.2 → 172.17.0.1:5053`), **mas** apresentou **instabilidade recorrente** a partir da
  Oracle: `[ERROR] Resolver couldn't be reached anonymously` e consultas diretas ao proxy
  dando timeout.
- **Revertido:** AdGuard voltou aos upstreams DoH/DoT originais (Cloudflare/Quad9/Google),
  **mantendo** as melhorias `fallback_dns` e `cache_optimistic = true`. Container removido;
  a config fica **estagiada** para uma nova tentativa (investigar alcançabilidade de relays
  UDP/443 a partir da Oracle).
- **Achado de firewall (relevante para o futuro):** o `INPUT` do host termina em
  `-A INPUT -j REJECT --reject-with icmp-host-prohibited` (default-deny, gerenciado por
  `netfilter-persistent` → `/etc/iptables/rules.v4`). Para o container do AdGuard alcançar um
  serviço no host foi preciso abrir exceção (`-i docker0 -s 172.17.0.0/16 -p udp --dport 5053`);
  a regra foi **removida e persistida** após o rollback. Backup: `/etc/iptables/rules.v4.bak-20261006`.

## 07/10/2026 — Healthchecks

- Todos os containers **standalone** deste host receberam `healthcheck` (padrão: ver [`guides/docker-healthchecks.md`](../guides/docker-healthchecks.md)), habilitando o `autoheal`. Containers que eram `docker run` ganharam `compose.yml`.

## 08/10/2026 — Gestão via API (OCI CLI)

- A VM passou a ser **gerenciável por API, direto do terminal** (do psicopompo), via **OCI CLI**
  com API key RSA no cofre sops — inventário, boot/block volumes, rede, imagens e a **captura da
  ARM**. Guia: [`guides/oracle-oci-cli.md`](../guides/oracle-oci-cli.md).
- **Disco (50 GB)** está a 17% usado — é o volume de referência para a **redução do boot do
  ybyra** (150 GB → ~50 GB), pré-requisito para a ARM caber na cota *Always Free* (200 GB).
  Método/runbook: [`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md).

## 08/10/2026 — `/srv/backup-gitrepos` estava montado com `hard`

- O mount NFS `/srv/backup-gitrepos` deste host ainda usava as opções **antigas (`hard,timeo=600`)**,
  de antes do ajuste do fstab em 10/09 (o `configs` já havia sido corrigido em 06/10; o `gitrepos`
  passou batido). Corrigido com `umount -l` + restart do automount → `soft,timeo=30,retrans=2`.
- Varredura na frota: **0 mounts NFS `hard`** (ybyra, ybytu, kuaray, kavure). Ver
  [`backups/config-backup.md`](../backups/config-backup.md).
