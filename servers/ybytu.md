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
| adguardhome | `adguard/adguardhome:latest` | `100.115.253.109:53`, `127.0.0.1:53`, `0.0.0.0:3000` | DNS server & admin panel |
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

- **Host resolver (2026-10-13):** `systemd-resolved` in **stub mode** — `/etc/resolv.conf` is a
  symlink to `/run/systemd/resolve/stub-resolv.conf` (`127.0.0.53`), and Tailscale runs on the
  **`systemd-resolved`** backend, injecting `100.100.100.100` (`~.`) into `tailscale0`. Global
  fallback `9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com` with `DNSOverTLS=opportunistic`.
  This is the **fleet standard** (see [`../guides/dns-consistency-map.md`](../guides/dns-consistency-map.md)).
- **AdGuard bind (2026-10-13):** the container publishes DNS on the **tailnet IP**
  (`100.115.253.109:53`) + **loopback** (`127.0.0.1:53`) only — **not** `0.0.0.0:53`. This frees
  `127.0.0.53:53` for the stub listener (the root fix for HB-013 below). Admin console stays on
  `0.0.0.0:3000` (reachable via the tailnet). In-container `bind_hosts` stays `0.0.0.0` because
  `docker-proxy` forwards host `IP:53` → container `172.22.0.2:53`.
- **Primary Upstream:** `tcp://100.124.146.77:5053` (Native recursive `unbound` resolver on kavure, queried over Tailscale).
  - *Note on TCP Transport:* AdGuard Home uses TCP to avoid known UDP packet drop bugs ([AdguardTeam/AdGuardHome#7628](https://github.com/AdguardTeam/AdGuardHome/issues/7628)).
- **Encrypted Fallback:** `tls://9.9.9.9` and `tls://1.1.1.1` (DNS-over-TLS). If kavure becomes temporarily unreachable, AdGuard seamlessly falls back to encrypted public resolvers with zero service interruption.
- **Log Retention Policy:** `querylog.interval` is bounded to 7 days with memory buffer set to 200 queries, preventing memory exhaustion on this 1 GB instance.

### Tailscale DNS health — HB-013 (2026-10-12, root-caused and fixed 2026-10-13)

**Symptom.** Tailscale reported `Tailscale failed to set the DNS configuration of your device: running /usr/sbin/resolvconf -m 0 -x -a tailscale: Failed to resolve interface "tailscale": No such device`, so `homelab_tailscale_health` dropped to `0` (see [`../network/observability.md`](../network/observability.md)).

**Root cause (verified against the Tailscale source and the upstream bug [`tailscale/tailscale#19062`](https://github.com/tailscale/tailscale/issues/19062)).** AdGuard Home binds `0.0.0.0:53`, so `systemd-resolved` runs with `DNSStubListener=no` and cannot be the actual resolver; Tailscale therefore (correctly) uses its **`direct`** DNS mode and writes its own `/etc/resolv.conf`. That file's header contains the literal `resolvconf-overwrite` (`https://tailscale.com/s/resolvconf-overwrite`), and on the **next** `tailscaled` start `resolvOwner()` substring-matches `resolvconf` inside Tailscale's own comment and returns `resolvconf`. `resolvconfStyle()` then sees `/usr/sbin/resolvconf` — a `resolvectl` shim shipped by the `systemd-resolved` package (`dpkg -S`) — and returns `openresolv`, so the openresolv manager calls `resolvconf -a tailscale`, which the shim rejects. **This reproduces on every boot / unclean shutdown.**

**Fix (2026-10-13, durable — applied and verified live).** The port conflict is removed at the source: AdGuard now publishes DNS only on the **tailnet IP + loopback** (freeing `0.0.0.0:53`, hence `127.0.0.53`); `DNSStubListener=no` was removed from `/etc/systemd/resolved.conf`; `/etc/resolv.conf` was re-pointed to `/run/systemd/resolve/stub-resolv.conf`; and the inert `adguardhome.conf.bak*` residue was deleted. After `systemctl restart systemd-resolved` and a **`tailscaled` restart**, Tailscale re-detected the backend and logged `dns: [resolved-ping=yes rc=resolved resolved=file nm=no resolv-conf-mode=stub ret=systemd-resolved]` — it now runs the fleet-standard **`systemd-resolved`** mode, exactly like [`kuaray.md`](kuaray.md), and the `#19062` trample loop is gone.

> The earlier **`tailscaled` drop-in** workaround (`10-resolvconf-misdetect.conf`, an `ExecStartPre`
> re-linking `/etc/resolv.conf` to the resolved **uplink** file) is **obsolete and not installed** —
> with the stub symlink, `resolvOwner()` returns `systemd-resolved` on its own.
> `/etc/systemd/system/tailscaled.service.d/` is intentionally empty.

**Verification (live, 2026-10-13).** `tailscale dns status` → both race resolvers (`100.115.253.109` + `100.124.146.77`) + MagicDNS; `/etc/resolv.conf` → stub; **both** paths filter (`getent hosts doubleclick.net` → `::` **and** `resolvectl query --cache=no doubleclick.net` → `0.0.0.0` + `::` — the old divergence is gone); `resolvectl query kavure.chimaera-heptatonic.ts.net` → `100.124.146.77` (not public IPs); `tailscale status --json` → `Health: []`. Pre-change copies of every edited file are kept in `/root/dns-unification-backup-2026-10-13/`.

**HB-013 status.** Root cause fixed and verified; the item stays **open** only for the **reboot-persistence** confirmation (the symlink survives reboot by design — Tailscale no longer writes `resolv.conf`) and for backlog archival, both the owner's step. Detected by `homelab_tailscale_health` (see [`../network/observability.md`](../network/observability.md)).

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
