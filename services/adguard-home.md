---
tags: [homelab, service, adguard, dns]
---

# AdGuard Home

DNS filtering server blocking advertisements, tracking domains, and telemetry telemetry — **containerized on ybytu**.

**Host Node:** ybytu  
**DNS Port:** `53` (TCP/UDP, bound to `0.0.0.0` within Docker)  
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
```
