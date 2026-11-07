---
tags: [homelab, server, ybytu, dns, monitoring, changedetection, ntfy]
pending: [HB-013, HB-117]
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
| **RAM** | 954 MB (ZRAM swap: **952.3 MB**, `zram0` / `lzo-rle` — measured 2026-11-06: swap is **1:1 of RAM**; the `477 MB` previously written here was stale) |
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
| ntfy | `binwiederhier/ntfy:latest` | `100.115.253.109:8083` (tailnet only) | Push notification service |
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
- **Encrypted Fallback:** `tls://9.9.9.9` and `tls://1.1.1.1` (DNS-over-TLS). Tuned `upstream_timeout: 1s` (2026-10-15) and labeled container `autoheal: "false"` so if residential WAN goes down, lookups failover to DoT in <250 ms without client timeout or autoheal restart loops.
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

## Incident 2026-11-06 — 15 h of thrash, no reboot (HB-117)

Between 06:54Z and 21:53Z the host stayed powered, stayed up on the wire, and became unusable. Nothing was killed and nothing was restarted: the machine lost both cores to its own page reclaim.

| Time (UTC) | Event |
|---|---|
| 06:54:48 | `apt-daily-upgrade.service` starts (`ExecMainStartTimestamp`) |
| 06:55:27 | `Packages that will be upgraded: apt apt-utils ca-certificates libapt-pkg6.0t64 python3-twisted` |
| 06:55:41–06:56:34 | `apt` / `libapt-pkg6.0t64` / `apt-utils` install (`/var/log/apt/history.log`) |
| 06:55 → 07:05 | `node_load1` **1.90 → 12.43** on 2 vCPU |
| 07:02:12 | first `page allocation failure: order:0, mode:0x820(GFP_ATOMIC)` — `swapper/0` |
| 07:25 | peak `node_load1` **17.74**; `SwapFree` 0 MiB of 952 MiB |
| 07:47:27 | `kswapd0` joins the failing allocators; 08:05:37 `containerd` does too |
| 08:43:27–08:46:16 | `ca-certificates` installs — 2 m 49 s for one package |
| 08:50 | last `node_load1` sample (**15.96**) and last promtail line in Loki — scrape target lost |
| 15:00:20 | last tailnet packet; `tailscaled` stops answering |
| 20:58:22 | `global_oom`: the kernel kills the uid-1001 `systemd --user` instance (PID 3854444) |
| 21:14:20 / 21:27:58 | last `page allocation failure`s — the 21:27:58 one is raised by `ntfy` itself |
| 21:29:57 | `global_oom` selects `AdGuardHome` (PID 852692) — it survives, still the container's PID |
| *(gap)* | **no telemetry for 12 h 50 m.** `NodeDown` (`for: 5m`) fired on schedule and was routed to `ntfy` *on this host* — the alert had nowhere to land |
| 21:40 | scrape resumes, `node_load1` **16.47** — still thrashing |
| 21:42:11–21:43:30 | `python3-twisted` installs |
| 21:53:03 | `All upgrades installed`; the unit exits at 21:53:20 |
| 21:50 → 22:00 | load **12.77 → 0.46** |
| 22:06 | `uptime -s` = 2026-10-31 01:21:14 → 6 d 20 h, **no reboot** |

**What it was.** Not memory exhaustion *at the onset*. `MemAvailable` held 294–364 MiB while the box could still be scraped, and the `GFP_ATOMIC` failures are what fragmentation looks like — an atomic allocation cannot sleep to reclaim, so it fails while memory still reads as available. The trigger was a 952 MiB swap (`SwapTotal`, 1:1 of RAM) driven to **zero** free: `node_vmstat_pgmajfault` at **600–1 100/s**, `node_procs_blocked` at **10–15**, and both vCPU **96–100 %** busy on reclaim and refault. `apt-daily-upgrade` itself used **619 s of CPU** across 14 h 58 m of wall time, so it was blocked and the CPU went to the kernel — and the missing dpkg-log lines for 11-06 mean *why* it stalled is not established, only that it did.

**The tail was OOM, and the earlier verdict missed it.** The kernel invoked the global OOM killer twice — 20:58:22Z (`Out of memory: Killed process 3854444 (systemd)`, UID 1001) and 21:29:57Z (`AdGuardHome`, PID 852692). So "thrash, not OOM" describes the onset and not the whole 15 h. What never happened is a *successful* kill: PID 852692 is still the `adguardhome` container's `Pid` with `RestartCount=0` (and that container is the one now reading `unhealthy`). The killer ran and made no progress — which is a stronger warning than either failure alone.

**What did not happen.** No container died, and none restarted. At 22:06Z `ntfy` was `Up 45 hours`, `uptime-kuma Up 19 hours`, `homepage Up 4 days`, `node-exporter Up 6 days`, `promtail Up 29 hours` — every one predates 06:54Z, so neither Docker nor `containerd` restarted anything, and the missing logs are **starvation, not death** (this corrects the first reading, which had promtail and node_exporter dying). The host was never rebooted either: `uptime -s` is 2026-10-31 01:21:14.

**The outcome — and why this section exists.** The host did not come back from a rescue; it came back when the upgrade finally finished. `unattended-upgrade` logged `All upgrades installed` at 21:53:03Z and load was 0.46 nine minutes later. The remedy proposed at 08:50 was a reboot. A reboot would have looked like a fix and would have destroyed the only evidence that explains the cause, while leaving `apt-daily-upgrade` armed for the next window (next firing: 2026-11-07 06:54:07Z). The absence of a reboot is the reason the cause is known.

**Why nobody was told.** `NodeDown` exists in the `homelab` rule group with `for: 5m`, so it fired within five minutes of 08:50Z — and its single receiver is `ntfy`, on this host. For the next twelve hours and fifty minutes the fleet alarm was pointing at the machine that was mute, and nothing recorded that the alert had been dropped. `ntfy` never died; it simply was not scheduled, which is the worst version of this failure: the container looks `healthy` to anyone who checks.

**The margin was already thin.** On 11-04 and 11-05 the box ran with only **~250 MiB** of zram free at rest, against a 952 MiB swap. One package unpack of incompressible `.deb` payloads was enough to reach zero, so the next scheduled upgrade is a repeat, not a rare coincidence.

**Prevention.** → **HB-117**: move `ntfy` (and preferably `uptime-kuma`) off this host; bound the upgrade (`RandomizedDelaySec=0`, `MemoryMax`/`CPUQuota`, `vm.swappiness` below 60, alert on `node_load1 > 8` for 10 min); and add an external dead-man's switch on `/alerts` that fires when nothing arrives for 30 min.

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

### Firewall & Docker NAT Persistence (`netfilter-persistent`)

Diferente dos nós gerenciados por UFW (`kavure`, `kuaray`), o `ybytu` utiliza `iptables` nativo gerenciado por `netfilter-persistent` (`/etc/iptables/rules.v4`).

**Protocolo obrigatório ao alterar regras de firewall no `ybytu`:**
1. **Serviços em Host-Mode:** Containers com `network_mode: host` (`homepage:3001`, `uptime-kuma:3002`, `glances:61208`) **não podem ter regras DNAT** na chain `nat/DOCKER`. Se existirem, sequestram o tráfego da Tailnet para IPs mortos de bridge (`No route to host`).
2. **Auditoria mandatória antes de salvar:** Nunca rodar `sudo netfilter-persistent save` cegamente. Execute antes:
   ```bash
   sudo iptables -t nat -S DOCKER
   ```
   Valide se todos os IPs de destino batem com containers ativos (`docker inspect`). Remova qualquer resíduo com `sudo iptables -t nat -D DOCKER <regra>`.
3. **Persistência segura:**
   ```bash
   sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak-$(date +%Y%m%d)
   sudo netfilter-persistent save
   ```
Ver detalhes e histórico de recuperação em [`../guides/homelab-traps-2026-10.md`](../guides/homelab-traps-2026-10.md#11-a-zombie-dnat-rule-steals-a-host-port-that-a-host-networked-container-is-listening-on).

