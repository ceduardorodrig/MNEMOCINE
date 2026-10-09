---
tags: [homelab, service, dnscrypt, dns, kavure]
---

# dnscrypt-proxy

> ## ⛔ DECOMMISSIONED on 2026-10-08 — Succeeded by [`unbound`](unbound.md) · **COLD STORAGE**
>
> The anonymized DNSCrypt egress pipeline incurred **353 ms cold query latency** due to transatlantic routing without South American relays. Native recursive **unbound** assumed port `5053` on kavure — upstream targets on Pi-hole and AdGuard Home did not change their listening endpoints, only the underlying backend daemon.
> Full cold storage methodology documented in [`../guides/cold-storage-servicos.md`](../guides/cold-storage-servicos.md).
>
> **Applied Cold Storage State (2026-10-08):**
> - Profile `cold` and restart policy `no` configured in compose manifest.
> - Verified fail-closed status: intentional startup fails cleanly with port collision on 5053 without crash-looping.
> - Preserved configuration snapshots mirrored to NAS storage via `hl-config-backup`.
>
> This document is preserved for architectural history and contingency rollback instructions.

Historical encrypted and anonymized DNS egress daemon on kavure, operating behind Pi-hole.

**Host Node:** kavure  
**Container Image:** `klutchell/dnscrypt-proxy@sha256:8911f7478837d42fa2c54504058b843415294c19233d424c5730987b05d987d7` (dnscrypt-proxy **2.1.18**)  
**Listening Address:** `127.0.0.1:5053` (UDP/TCP)  
**Configuration File:** `/srv/data/dnscrypt-proxy/config/dnscrypt-proxy.toml`  

## Architectural Principle: Anonymized DNSCrypt

The pipeline utilized two-hop anonymization:
**kavure → Anonymized Relay → DNSCrypt Resolver → Authoritative Lookups**

- The relay observed client source IP, but could not decrypt the query.
- The destination resolver decrypted the query, but only saw the relay IP.
- Enforced strict operator diversity: relays operated by CryptoStorm (US) routing to destination resolvers operated by `dnscry.pt`.

## Core Configuration Parameters

| Directive | Configured Value | Purpose |
|---|---|---|
| `listen_addresses` | `['127.0.0.1:5053']` | Loopback binding |
| `server_names` | `dnscry.pt` US-East instances | High-speed cryptographic resolvers |
| `cache` / `cache_size` | `true` / `16384` | Local proxy caching layer |
| `cache_min_ttl` | `2400` | Caches records for at least 40 minutes, minimizing cold lookups |
| `block_ipv6` | `true` | Answers AAAA immediately with empty responses to avoid dead IPv6 queries |
| `lb_strategy` | `wp2` | Dynamic latency-based server selection |

## Rollback Procedure (Reactivating dnscrypt-proxy)

If required for operational testing:
```bash
# 1. Stop native unbound to release port 5053:
sudo systemctl stop unbound

# 2. Revert watchdog service target:
# Edit hl-dns-watchdog.service from --service unbound to --container dnscrypt-proxy

# 3. Launch cold storage container:
cd /srv/data/dnscrypt-proxy
docker compose --profile cold up -d
```

## See Also
- [`unbound.md`](unbound.md) — Active recursive DNS resolver
- [`pihole.md`](pihole.md) — Local filtering sinkhole
- [`../guides/cold-storage-servicos.md`](../guides/cold-storage-servicos.md) — Homelab service freezing standard
