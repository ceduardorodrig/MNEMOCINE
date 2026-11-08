---
tags: [homelab, service, adguard, dns]
---

# AdGuard Home

DNS filtering server blocking advertisements, tracking domains, and telemetry telemetry — **containerized on ybytu**.

**Host Node:** ybytu  
**DNS Port:** `53` (TCP/UDP) — published on the **tailnet IP (`100.115.253.109:53`) + loopback (`127.0.0.1:53`)** since 2026-10-13; previously `0.0.0.0:53`, which occupied `127.0.0.53` and implicitly disabled the `systemd-resolved` stub (HB-013)  
**Admin Port:** `3000`  
**Web Console:** `http://ybytu.chimaera-heptatonic.ts.net:3000`  

## Container Architecture

Runs **exclusively as a Docker container**. There is no bare-metal host daemon:

| Specification | Parameter |
|---|---|
| Container Name | `adguardhome` (`adguard/adguardhome:latest`, `restart: unless-stopped`) |
| Configuration Volume | `/var/lib/docker/volumes/adguard_conf/_data/AdGuardHome.yaml` |
| Working Data | `/var/lib/docker/volumes/adguard_workdir/_data/` (`querylog.json`, `stats.db`, `filters/`) |
| Compose Manifest | Defined in `/home/ubuntu/homelab/adguardhome/compose.yml` |

## Network Role — Co-Resolver in Tailscale Parallel Race

Serves in **parallel** alongside [`Pi-hole`](pihole.md) (architecture detailed in [`network/dns.md`](../network/dns.md)):
Tailscale MagicDNS forwards incoming queries to both resolvers **concurrently**, consuming whichever response arrives first. AdGuard is an **active resolving peer, not merely a passive failover target**: empirical measurements show AdGuard wins resolution races whenever it holds a cached record that Pi-hole misses.

> **Bind change (2026-10-13).** The container publishes DNS on the **tailnet IP + loopback only**
> (see *DNS Port* above). The race reaches AdGuard at `100.115.253.109:53` (unchanged); the change
> simply stops the host-level `0.0.0.0:53` publish, freeing `127.0.0.53` so `systemd-resolved`'s
> stub listener can run (the HB-013 root fix). The in-container `dns.bind_hosts` stays `0.0.0.0`
> because `docker-proxy` forwards host `IP:53` → container `172.22.0.2:53`. No consumer used the
> old non-tailnet path (query log: only the docker-proxy hop, the tailnet IP and loopback).

| Metric | Pi-hole (kavure) | AdGuard (ybytu) |
|---|---|---|
| Latency (Warm Cache) | ~2 ms (Gigabit LAN, local cache) | ~66 ms (Oracle Cloud transit) |
| Wins when **both** have cache hit | ✅ (2 ms ≪ 66 ms) | — |
| Wins when **only AdGuard** hits cache | — (~290 ms cold recursion) | ✅ (35–92 ms) |
| Query Volume | ~85k queries / 24h | ~79k queries / 24h (receives all dual-dispatched races) |

## Active Blocklists (9 Curated Lists)

| # | Blocklist Name | Purpose |
|---|---|---|
| 1 | AdGuard DNS Filter | Baseline ad-blocking and privacy rules |
| 2 | AdAway (`filter_2`) | Mobile ad protection |
| 3 | HaGeZi Normal (`filter_34`) | Comprehensive privacy filter |
| 4 | Phishing Army (`filter_18`) | Malicious phishing and scam domains |
| 5 | NoCoin (`filter_8`) | In-browser crypto-mining blocker |
| 6 | AdGuard Portuguese (`extension/chromium/filters/2.txt`) | Regional Portuguese ad rules |
| 7 | HaGeZi Windows/Office Tracker (`filter_63`) | Windows and Office telemetry blocking |
| 8 | **WindowsSpyBlocker `spy.txt`** | Windows OS tracking parity with Pi-hole |
| 9 | **fightback-consumer-tv Core** | Smart TV tracking endpoints (118 rules, CC0) |

> **Memory Constraint Decision:** The **OISD big** list is deliberately **omitted from AdGuard**. Parsing ~1.4M rules in memory on a 954 MB RAM cloud instance presents significant OOM risk. Parity with Pi-hole is enforced via custom exact user rules.

## Custom User Filtering Rules (`user_rules`)

Exact mirrors of Pi-hole denylists ensuring consistent filtering across both nodes:

- **Microsoft Telemetry (8 Exact Domains):** `telemetry.microsoft.com`, `telemetry.microsoft.us`, `settings-win.data.microsoft.com`, `vortex.data.microsoft.com`, `v10.events.data.microsoft.com`, `settings-sandbox.data.microsoft.com`, `settings-ios.events.data.microsoft.com`, `diagnostics.support.microsoft.com`
- **Regex Filter:** `/(^|\.)events\.data\.microsoft\.com$/`
- **Telemetry Leak Mitigation:** `firebaselogging.googleapis.com`, `ads.spotify.com`, `browser.events.data.msn.com`
- **Smart TV Tracking:** `us.lgtvsdp.com` (LG WebOS telemetry)
- **Regional Commerce Telemetry:** `ge.globo.com`, `analytics.mercadolivre.com.br`, `log.ifood.com.br`

## Upstream Forwarding Configuration

```text
tcp://100.124.146.77:5053    (kavure local recursive unbound instance)
```

**Encrypted Upstream Fallback:** `fallback_dns = ['tls://9.9.9.9', 'tls://1.1.1.1']` (Quad9 and Cloudflare DNS-over-TLS).
**Optimistic Caching:** `cache_optimistic: true` — serves expired cache records immediately while refreshing lookups asynchronously.

> **Why TCP Transport is Enforced:** The UDP upstream path in dnsproxy exhibited intermittent timeouts over cross-cloud links due to a known AdGuard Home UDP bug (issues #7628, #7346). Forwarding over `tcp://` provides consistent 100% resolution success.

### WAN Outage Resilience Hardening (2026-10-15)

Investigated and resolved a cascade failure where a residential link drop (01:40 BRT) took down mobile clients via Tailscale:
1. **`upstream_timeout: 1s` (Tuned down from default `10s`):** When Kavure goes offline, TCP SYN packets blackhole rather than RST. A 10s wait causes smartphone resolvers (2-3s timeout) to abort with "no internet". Lowering timeout to 1s ensures AdGuard seamlessly hands queries to encrypted DoT fallbacks in ~1.1s total, staying within mobile OS thresholds.
2. **Autoheal Suppression (`autoheal: "false"`):** The container is excluded from blind `autoheal` loops (`AUTOHEAL_CONTAINER_LABEL=all`). When upstream fails, transient healthcheck timeouts no longer cause autoheal to reboot AdGuard every 3 minutes.
3. **Outbound Docker Routing & Persistent IPTables:** Purged stale `172.17.0.2` DNAT rules left over from earlier container recreation. Added generic outbound rules (`DOCKER-USER` acceptance + `POSTROUTING` MASQUERADE for `172.16.0.0/12`) in `/etc/iptables/rules.v4` on ybytu, preventing Oracle Cloud host firewall from dropping dynamic container bridge packets.
4. **Verified Live:** Simulated Kavure packet drop (`OUTPUT -d 100.124.146.77 -p tcp --dport 5053 -j DROP`) confirmed resolution smoothly degrades to DoT in ~95–245 ms without service interruption or container crashes.

### Immortality Hardening (2026-11-08)

A 952 MiB host plus an unbounded daily `apt` run cost this service **32 h 46 m of silence** without a single alert. On 2026-11-06 21:29:57Z the kernel's global OOM killer took `AdGuardHome` (PID 852692); Docker never recorded the exit, so the container reported `Up 4 days (unhealthy)`, `RestartCount=0`, `Running=true` over a dead PID, while `:53` answered `connection refused` — the sockets belonged to orphaned `docker-proxy` processes pointing at a `172.22.0.2` that no longer existed. Full forensics: [`../servers/ybytu.md`](../servers/ybytu.md); fleet item: **HB-118**.

Three consequences, now applied:

1. **OOM priority, not luck.** `oom_score_adj: -500` in the host compose (`/home/ubuntu/homelab/adguardhome/compose.yml`, backup `.bak-20261108-oomadj`). It **cannot** be set on a live container: `docker update` rejects it (`unknown flag: --oom-score-adj`, verified 2026-11-08), so the key lives in the compose file and requires a recreate. AdGuard now loses the OOM race last instead of tying with everything else at `0`.
2. **A probe that lives outside the host it watches.** `hl-adguard-probe.timer` on **kavure** runs `/usr/local/bin/adguard-probe.sh` every 2 min and asks `doubleclick.net` of `100.115.253.109:53`, expecting `0.0.0.0`. A port that answers is not proof — a filtered answer is. It classifies `OK` / `FILTER_OFF` / `DOWN`, exports `homelab_adguard_*` textfile metrics to Prometheus, and posts to ntfy `/alerts` on `OK→DOWN` (after 3 consecutive failures) and on recovery. Delivery failure is logged, never swallowed. **Alert-only on purpose:** the repair is a privileged cross-host action (`docker rm -f` + recreate) and is waiting on the owner's decision in HB-118.
3. **A corpse is not repairable by `docker start`.** See *Operational Commands* below — `stop`/`start`/`restart` address a state Docker no longer has.
4. **Healthcheck caveat (pending).** The image stopped shipping a `HEALTHCHECK` in v0.107.34, and AdGuard's own docs recommend probing the reserved name `healthcheck.adguardhome.test` (expect `NODATA`). This compose still runs `nslookup example.com 127.0.0.1`, which needs a working upstream and therefore reports `unhealthy` during a WAN outage — a false alarm, and one more reason `unhealthy` was not trusted. Switching it is part of HB-118.

## Query Logging & Retention Tuning

- Configuration: `querylog.interval: 7d`, `size_memory: 200` entries.
- Stored on disk at `/var/lib/docker/volumes/adguard_workdir/_data/data/querylog.json`. Rotating logs at 7-day intervals reclaimed 2.4 GB of disk space on the constrained Oracle boot volume.

## Backup & Disaster Recovery

- Backed up nightly via `config-backup` mirroring `/var/lib/docker/volumes/adguard_conf` → NAS `/mnt/BACKUP/configs-homelab/ybytu/adguard_conf/`.
- Pre-change backups retained in volume directory as `AdGuardHome.yaml.bak-20261006-parity`.

## Operational Commands

```bash
docker ps --filter name=adguardhome
docker logs --tail 100 adguardhome
docker stop adguardhome && docker start adguardhome
# ...but a CORPSE (Running=true over a dead PID, `docker exec` -> "cannot exec in a
# stopped state") is not repairable by stop/start/restart. Recreate it; the volumes
# are external, so config and query history survive:
docker rm -f adguardhome && docker compose -f /home/ubuntu/homelab/adguardhome/compose.yml up -d
dig +short @100.115.253.109 doubleclick.net   # the acceptance test: 0.0.0.0
```
