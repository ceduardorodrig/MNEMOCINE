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
