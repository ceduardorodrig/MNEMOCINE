---
tags: [homelab, server, ybytu, dns, monitoring, changedetection, ntfy]
pending: [HB-013]
---

# ybytu

> OS hostname: `ybytu-vnic` (displayed in Tailscale as `ybytu`)

**Role:** Cloud utility server (Oracle Cloud Infrastructure Always Free) — DNS, dashboard portal, notification gateway, and monitoring  
**Default Shell:** bash (`/bin/bash`)  

## Hardware Specifications

| Component | Specification |
|---|---|
| **OS** | Ubuntu 24.04 LTS |
| **Kernel** | 7.0.0-1012-oracle |
| **CPU** | AMD EPYC 7551 (2 vCPUs — Oracle free tier shape `VM.Standard.E2.1.Micro`) |
| **RAM** | 954 MB (ZRAM: 477 MB) |
| **Disk Storage** | 50 GB virtual block volume |
| **Tailscale IP** | 100.115.253.109 |
| **Tailscale DNS** | ybytu.chimaera-heptatonic.ts.net |
| **Network Interface** | Virtual network (`ens3`: 10.0.0.136/24, MTU 9000) |

## Core Operational Responsibilities

- **Tailnet Exit Node:** Configured exit node providing egress routing for mobile and remote devices.
- **Network-Wide Ad-Blocking DNS:** AdGuard Home container answering DNS requests across the mesh.
- **Central Portal Dashboard:** Homepage dashboard rendering homelab services and live container states.
- **Uptime Monitoring:** Uptime Kuma executing external HTTP and port probes.
- **Change Detection:** Changedetection.io monitoring upstream software repositories and document releases.
- **Push Notification Gateway:** Self-hosted ntfy instance receiving systemd and backup failure webhooks.

## Docker Workloads (Standalone Containers)

All workloads execute as Docker containers managed via Docker Compose:

| Container | Image | Ports | Responsibility |
|---|---|---|---|
| adguardhome | `adguard/adguardhome:latest` | `0.0.0.0:53`, `0.0.0.0:3000` | DNS server & admin panel |
| homepage | `ghcr.io/gethomepage/homepage:latest` | `0.0.0.0:3001` (`host` net) | Homelab portal interface |
| glances | `nicolargo/glances:latest` | `100.115.253.109:61208` | Node telemetry metrics |
| dockerproxy | `tecnativa/docker-socket-proxy:latest` | `100.115.253.109:2375` | Secure socket gateway for Homepage |
| node-exporter | `prom/node-exporter:v1.9.0` | `0.0.0.0:9100` (nft → tailnet) | Host performance metrics for Prometheus |
| promtail | `grafana/promtail:3.2.0` | — | Log shipping agent forwarding to Loki on kavure |
| uptime-kuma | `louislam/uptime-kuma:latest` | `0.0.0.0:3002` (`host` net) | Service availability monitor |
| changedetection | `dgtlmoon/changedetection.io:latest` | `0.0.0.0:8082` | Web page alteration alerts |
| ntfy | `binwiederhier/ntfy:latest` | `0.0.0.0:8083` | Push notification service |
| watchtower | `containrrr/watchtower:latest` | — | Automated container image updater |
| autoheal | `willfarrell/autoheal:latest` | — | Restarts unhealthy containers automatically |

> **Correction (2026-10-13):** `node-exporter` and `promtail` were missing from this table.
> Verified live: both run on ybytu (the node ships host metrics to Prometheus and logs to Loki).
> The `glances`/`dockerproxy` binds were also corrected to their real Tailscale-IP binds
> (they do not listen on `0.0.0.0`/`127.0.0.1` as previously written).

## DNS Architecture & Upstream Resolution

- **Primary Upstream:** `tcp://100.124.146.77:5053` (Native recursive `unbound` resolver on kavure, queried over Tailscale).
  - *Note on TCP Transport:* AdGuard Home uses TCP to avoid known UDP packet drop bugs ([AdguardTeam/AdGuardHome#7628](https://github.com/AdguardTeam/AdGuardHome/issues/7628)).
- **Encrypted Fallback:** `tls://9.9.9.9` and `tls://1.1.1.1` (DNS-over-TLS). If kavure becomes temporarily unreachable, AdGuard seamlessly falls back to encrypted public resolvers with zero service interruption.
- **Log Retention Policy:** `querylog.interval` is bounded to 7 days with memory buffer set to 200 queries, preventing memory exhaustion on this 1 GB instance.

### Tailscale DNS health — HB-013 (2026-10-12)

The host's Tailscale health reported `Tailscale failed to set the DNS configuration of your device: running /usr/sbin/resolvconf … Failed to resolve interface "tailscale": No such device`. Cause: `tailscaled` (started before the DNS backend settled) had fallen back to the broken `resolvconf` path. **Fix:** `sudo systemctl restart tailscaled` made it re-detect the backend — the health error cleared and MagicDNS resolution works. Detected by `homelab_tailscale_health` (see [`../network/observability.md`](../network/observability.md)). ⚠️ Verify it persists across reboot.

## Backup & Storage Mounts

- **NFS Mounts:** Configuration backups export to NAS mirror on psicopompo using soft mounts (`soft,timeo=30,retrans=2` with `nofail`).
- **Local Config Mirroring:** `config-backup` runs daily at 05:00, pushing compose stacks and AdGuard configurations to NAS and Git.

## See Also

- [`services/adguard-home.md`](../services/adguard-home.md) — AdGuard Home configuration and filter rules
- [`services/homepage.md`](../services/homepage.md) — Homelab application portal configuration
- [`guides/oracle-oci-cli.md`](../guides/oracle-oci-cli.md) — OCI CLI remote instance management

## Security Baseline (2026-10-13)

- **SSH (OpenSSH)**: **key-only** — `PasswordAuthentication no` + `KbdInteractiveAuthentication no` (drop-in `/etc/ssh/sshd_config.d/00-homelab.conf`). O `:22` é alcançável da **internet pública**, mas só por **chave** (as ~34.000 tentativas de força bruta em 30 dias falharam todas: `passwordauth no`, `kbdinteractive no`, `permitemptypasswords no`).
- **fail2ban** (1.0.2, ativo): jail `sshd` (`mode = aggressive`, `bantime 1h`, `findtime 10m`, `maxretry 5`). **`ignoreip` inclui a tailnet (`100.64.0.0/10`)** — o acesso normal é por ela e **nunca** deve ser banido.
- **Acesso normal**: **Tailscale SSH** pela tailnet (não usa o OpenSSH). Detalhe: [`../network/tailscale.md`](../network/tailscale.md).
- **Revisão de compromisso (13/10)**: **sem sinais** — todos os logins bem-sucedidos usam a **mesma chave do dono** (do ISP brasileiro), sem usuários/chaves/unidades/cron/conexões de saída fora do padrão.
