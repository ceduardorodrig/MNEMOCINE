---
tags: [homelab, service, unbound, dns, kavure]
---

# Unbound

Local **recursive caching DNS resolver** with DNSSEC validation — installed as a **native system package (apt) on kavure**, succeeding `dnscrypt-proxy` as the upstream engine for Pi-hole and AdGuard Home on **2026-10-08**.

**Host Node:** kavure  
**Package:** `unbound` **1.19.2-1ubuntu3.10** (Ubuntu Noble with backported security fixes)  
**Socket Bindings:** `127.0.0.1:5053` (Pi-hole) + `100.124.146.77:5053` (Tailnet — AdGuard)  
**Configuration File:** `/etc/unbound/unbound.conf.d/mnemocine.conf`  
**System Services:** `unbound.service` (Systemd) · Watchdog: `hl-dns-watchdog.timer` (2 min) · Status Endpoint: `unbound-status.service` (`:9097` for Homepage tile)  

## Purpose & Architecture Rationale

The previous anonymized chain (dnscrypt-proxy → CryptoStorm US relay → US-East resolver) incurred **353 ms cold latency** per query due to transatlantic roundtrips without South American relays.

Unbound resolves **directly from DNS root servers** (Root → TLD → Authoritative nameservers) without commercial third-party intermediaries:

| Resolution Pipeline | Query Visibility |
|---|---|
| ~~Pi-hole → dnscrypt → relay → server~~ | Relay observes client IP; server observes queries |
| **Pi-hole → unbound → Authoritative Roots** | Only authoritative nameservers for the queried domain see requests; ISP observes generic port 53 traffic without a single destination provider |

## Why Bare-Metal Native Package (apt) Over Containerization

- **Community Docker Images are Stale:** Docker Hub images such as `klutchell/unbound` remain pinned to 1.13.2 (2021) without modern security backports.
- **Native Systemd Integration:** Native apt package provides automatic systemd lifecycle management, journal logging, configuration validation (`unbound-checkconf`), and automated root hint updates (`dns-root-data`).
- **Cluster Stability:** Kavure is the Docker Swarm manager node. Running core DNS as a bare-metal daemon ensures name resolution survives any Docker daemon maintenance or restart.

## Configuration Details (`/etc/unbound/unbound.conf.d/mnemocine.conf`)

| Directive | Configured Value | Architectural Justification |
|---|---|---|
| `interface` / `port` | `127.0.0.1` + `100.124.146.77` / `5053` | Binds to loopback (Pi-hole) and private tailnet (AdGuard). Same port as previous proxy, requiring zero endpoint modifications |
| `do-ip6` | `no` | Prevents stalls on unreachable IPv6 upstream paths |
| `access-control` | `127.0.0.0/8` and `100.64.0.0/10` allow, default refuse | Restricts resolution strictly to loopback and private tailnet |
| `harden-dnssec-stripped` | `yes` | Enforces cryptographic DNSSEC validation |
| `edns-buffer-size` | `1232` | Prevents UDP fragmentation (DNS Flag Day standard) |
| `prefetch` & `prefetch-key` | `yes` | Refreshes expiring cache entries and pre-fetches DNSKEY records before user requests |
| `serve-expired` | `yes` (TTL 86400) | Delivers cached records immediately while refreshing lookups asynchronously |
| `incoming-num-tcp` | `64` | Multi-thread buffer ceiling absorbing concurrent page load bursts from AdGuard |
| `outgoing-num-tcp` | `32` | Outbound recursive TCP pool |
| `tcp-idle-timeout` | `120000` | Extends connection idle timeout to 2 minutes, preventing EOF resets on AdGuard connection pools |
| `msg-cache-size` / `rrset-cache-size` | `128m` / `256m` | Dedicated RAM allocation leveraging kavure's 6 GB available headroom |

## Automated Watchdog (`hl-dns-watchdog` in Rust)

The external watchdog binary monitors Unbound health every 2 minutes:
- Executes live test queries with unique nonces (`watchdog-<epoch>.cloudflare.com`) against `127.0.0.1:5053`.
- After 3 consecutive timeouts, triggers `systemctl reset-failed` and restarts `unbound.service`.
- Logs cache hit rate, query count, and memory RSS directly to systemd journal.

## Status Endpoint for Homepage (`unbound-status`)

Because Unbound runs natively without an embedded web server, a lightweight native Rust HTTP daemon (`unbound-status.service`, listening on port `9097`) provides live health checks for Homepage dashboard monitoring:
- `GET /` → returns HTTP `200 up` when DNS probe succeeds; HTTP `503 down` on lookup failure.

## Operational Commands

```bash
systemctl status unbound
journalctl -u unbound -n 50 --no-pager
unbound-checkconf
systemctl restart unbound
dig @127.0.0.1 -p 5053 google.com
```

## See Also
- [`pihole.md`](pihole.md) — Local caching sinkhole on kavure
- [`adguard-home.md`](adguard-home.md) — Parallel resolving peer on ybytu
- [`dnscrypt-proxy.md`](dnscrypt-proxy.md) — Historical decommissioned proxy documentation
