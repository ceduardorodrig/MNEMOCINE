---
tags: [homelab, server, ybyra, docker, monitoring, tailscale]
---

# ybyra

**Papel:** Servidor cloud (Oracle Cloud) — Borda primária Sumaenima (proxy, tunnel, umami)
**Shell padrão:** bash (`/bin/bash`)
**Swarm role:** `primary` — nó worker do Docker Swarm (stack `sae-edge`)

> **Atualizado 28/08/2026:** `apt dist-upgrade` completo (41 pacotes, incl. Docker engine → 29.7.2) + reboot. Kernel **6.17.0-1016 → 6.17.0-1020-oracle**. Swarm services e borda primária OK pós-reboot.

## Hardware

| Item | Especificação |
|---|---|
| **SO** | Ubuntu 24.04.4 LTS (KVM — QEMU Standard PC) |
| **Kernel** | 6.17.0-1020-oracle |
| **CPU** | AMD EPYC 7551 32-Core (2 vCPUs — 1 core/2 threads, Oracle free tier) |
| **RAM** | 954 MB (nenhum swap configurado) |
| **Disco Sistema** | 150 GB — Boot Volume (Oracle Block Storage) — `sda1` ext4 — 2% usado (3 GB) |
| **Swap** | Nenhum |
| **Tailscale IP** | 100.66.224.34 |
| **Tailscale DNS** | ybyra.chimaera-heptatonic.ts.net |
| **Rede** | Oracle internal network (`ens3`: 10.0.0.40/24) |

## Papéis

- Novo servidor cloud (Oracle free tier)
- Futuro host de Single Page Application (Docker)

## Tailscale Funnels

| URL | Destino | Status |
|---|---|---|
| `https://sumaenima.chimaera-heptatonic.ts.net` | `http://proxy:80` | Ativo — proxy para o nginx Swarm |

## Containers Docker — Utilitários (Standalone)

| Container | Imagem | Portas | Função |
|---|---|---|---|
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoramento |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |

## Swarm Services (Gerenciados pelo Docker Swarm no psicopompo)

| Service | Imagem | Portas | Função |
|---|---|---|---|
| proxy | nginx-sumaenima:latest | `0.0.0.0:80` | Proxy reverso (SPA, API, Umami) |
| tunnel | tailscale/tailscale:latest | — | Tailscale Funnel (sumaenima.chimaera-heptatonic.ts.net) |
| umami | sumaenima-umami:latest | 3000 | Analytics (acessível via nginx `/umami/`) |
| ~~datavis~~ | ~~datavis-server:latest~~ | ~~9091~~ | **removido 22/09/2026** — legado, nada consumia; CVE-2025-67221 (orjson) fechado por eliminação |

## Programas Nativos

| Programa | Função |
|---|---|
| tailscaled | Agente Tailscale |
| Docker Engine | Container runtime (v29.7.2) |
| nginx | Borda Primária (Roteamento de tráfego, virtual DNS, SPA Frontend) |

## Portas Importantes

| Porta | Serviço | Bind |
|---|---|---|
| 22 | SSH | Tailscale |
| 80 | Nginx (Borda Primária — SPA, API, Umami) | `0.0.0.0` |
| 61208 | Glances | `0.0.0.0` |

## Observações

- Servidor Oracle free tier (Junho 2026): 2 vCPUs, 1 GB RAM, 150 GB disco.
- Servidor **exclusivamente como borda primária** do Sumænimá Hub.
- Todo o tráfego público entra via Tailscale Funnel (`sumaenima.chimaera-heptatonic.ts.net` → proxy:80).
- Nginx roteia:
  - `/` → SPA (React + Vite)
  - `/api/` → FastAPI (steniobot-api no psicopompo, overlay network)
  - `/umami/` → Umami (no próprio ybyra, overlay network)
- ~~`/api/datavis/`~~ → removido 22/09/2026 (legado) — 404 agora, era 502
- **Não** roda filebrowser, syncthing nem outros utilitários — estes ficam no ybytu.
- Containers utilitários (glances, autoheal, watchtower) rodam standalone fora do Swarm.
- Nenhum serviço do Kuaray roda aqui — kuaray é o servidor multimídia separado.
- Ver `network/topology.md` para topologia de rede completa.
- **Fix NFS (10/09/2026):** Entries `hard` → `soft` no fstab (`configs-homelab`, `repos/git`). Backup: `/etc/fstab.bak.20260910`. Drop-in Docker: `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). Ver [`network/nfs.md`](../network/nfs.md).
