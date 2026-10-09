---
tags: [homelab, service, pihole, dns]
---

# Pi-hole

Network-wide ad-blocking DNS server — **Docker container hosted on kavure** (migrated from kuaray on 2026-08-09).

**Host Node:** kavure  
**DNS Port:** `53` (TCP/UDP, bound to tailnet) · **Admin:** `http://100.124.146.77/admin`  
**Web Console:** `http://kavure.chimaera-heptatonic.ts.net/admin`  
**Admin Password:** `PI_HOLE_ADMIN_PASSWORD` stored in SOPS secret vault.  

> **Client IP Preservation Configuration:**  
> Deployed with `network_mode: host` + `FTLCONF_dns_listeningMode: BIND` + `FTLCONF_dns_interface: tailscale0`. Listens strictly on the Tailscale interface, accurately identifying individual tailnet client IPs without conflicting with kavure's local systemd-resolved stub (`127.0.0.53`).
>
> **Global Tailnet Resolver:** Operates as one of the two active resolvers in the Tailscale parallel dispatch race (see [`network/dns.md`](../network/dns.md)).  
> **Upstream Target:** `127.0.0.1#5053` — **local recursive unbound daemon** with DNSSEC validation. No unencrypted plain DNS egress on normal query paths.

## Blocklists (445k+ Unique Domains)

Pi-hole v6 manages active adlists via SQLite database at `/srv/data/pihole/etc-pihole/gravity.db`.

1. **StevenBlack hosts** — Baseline ad/malware protection
2. **AdAway** (`filter_2.txt`) — Mobile ad tracking
3. **Phishing Army** (`filter_18.txt`) — Malicious phishing domains
4. **NoCoin** (`filter_8.txt`) — In-browser crypto miners
5. **WindowsSpyBlocker** (`data/hosts/spy.txt`) — Windows telemetry endpoints
6. **OISD big** (`https://big.oisd.nl`) — Comprehensive ad and tracker coverage with a strict low false-positive standard ("Block. Don't break.")
7. **fightback-consumer-tv Core** (`fightback-tv-core.txt`, CC0) — 118 Smart TV tracking endpoints across Roku, Samsung, LG, Amazon, Apple, and Sony
8. **HaGeZi Windows/Office Tracker** (`filter_63.txt`) — 381 ABP tracking rules (parity with AdGuard Home)

## Exact Denylist Rules (Telemetry & Tracking)

Exact deny entries configured directly in FTL:

- `telemetry.microsoft.com`, `telemetry.microsoft.us`
- `settings-win.data.microsoft.com`, `vortex.data.microsoft.com`
- `v10.events.data.microsoft.com`, `settings-sandbox.data.microsoft.com`
- `settings-ios.events.data.microsoft.com`, `diagnostics.support.microsoft.com`
- Wildcard regex: `/(^|\.)events\.data\.microsoft\.com$/`
- `browser.events.data.msn.com`, `us.lgtvsdp.com` (LG TV telemetry)
- Regional commerce telemetry: `ge.globo.com`, `analytics.mercadolivre.com.br`, `log.ifood.com.br`

## Local Recursive Egress (Unbound on Kavure)

Pi-hole's exclusive upstream is configured as **`127.0.0.1#5053`** — the native **recursive unbound daemon** running locally on kavure (Root → TLD → Authoritative lookup, DNSSEC validated). Detailed configuration in [`unbound.md`](unbound.md).

- **Single Upstream Standard (`127.0.0.1#5053`):** Under normal operations, 100% of forwarded queries resolve through unbound. Pi-hole's failover mechanism is provided by the **Tailscale parallel race**, falling back to AdGuard Home (which maintains encrypted DoT upstreams to Quad9).
- **Caching Telemetry:** Warm cache lookups respond in **19–22 ms**; cold lookups average ~280 ms. Across measured 24h windows, Pi-hole resolves **45.7% from cache, 43.2% blocked, and only 8.8% forwarded** to unbound.

## Service Management

- Docker Compose manifest: `/srv/data/pihole/compose.yml` (`network_mode: host`).
- Config directory: `/srv/data/pihole/etc-pihole/` (mirrored to NAS via `config-backup`).
- Gravity update: `docker exec pihole pihole -g`.

## See Also
- [`unbound.md`](unbound.md) — Local recursive DNS engine
- [`adguard-home.md`](adguard-home.md) — Secondary parallel resolver on ybytu
- [`../network/dns.md`](../network/dns.md) — Full homelab DNS architecture
