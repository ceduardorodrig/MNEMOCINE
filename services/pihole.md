---
tags: [homelab, service, pihole, dns]
---

# Pi-hole

DNS with ad blocking — **Docker container on kavure** (migrated 09/08/2026, previously on kuaray).

**Server:** kavure
**Port:** `53` (TCP/UDP, tailnet) · **Admin:** `http://100.124.146.77/admin`
**URL:** `http://kavure.chimaera-heptatonic.ts.net/admin`
**Admin password:** `PI_HOLE_ADMIN_PASSWORD` in the sops store (`/mnt/NVME_PCI/secrets/secrets.env`).

> **Config "see the real device IPs"** (recreated 09/08): `network_mode: host` + `FTLCONF_dns_listeningMode: BIND` + `FTLCONF_dns_interface: tailscale0` — listens only on the tailscale interface and sees each device's IP (does not conflict with kavure's systemd-resolved on `127.0.0.53`).
> **Tailnet global resolver:** points to `100.124.146.77` (kavure). Upstream: Google `8.8.8.8/8.8.4.4`.

## Blocklists (18/08/2026 — revised)

> **Important note:** Pi-hole v6 **does** parse ABP-style lists (`||domínio^`)? — the OISD big is distributed in ABP and was correctly consumed as "ABP-style domains". It also works for lists in hosts/domain format.
> **Management:** v6 stores the adlists in **gravity.db** (not in `adlists.list`). Insert via:
> `sqlite3 /srv/data/pihole/etc-pihole/gravity.db "INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('<url>',1,'');"` + `docker exec pihole pihole -g`.
> ⚠️ gravity.db is **excluded** from the config-backup (`*.db`) — THIS DOC is the source of truth for the lists.

**6 lists (gravity ~512,000 domains):**

1. StevenBlack hosts — base ads/malware
2. AdAway (registry `filter_2.txt`) — ads
3. Phishing Army (registry `filter_18.txt`) — phishing
4. NoCoin (registry `filter_8.txt`) — crypto-mining
5. WindowsSpyBlocker (`data/hosts/spy.txt`) — Windows telemetry (partial)
6. **OISD big** (`https://big.oisd.nl`) — **replaced 1Hosts Xtra on 18/08**: large coverage (~1.4M equivalent hosts) with **a focus on functionality and low false positives** ("Block. Don't break.")

> **History — why 1Hosts Xtra was dropped:** on 18/08 Xtra (~1.1M hosts) caused a cascade of false positives that broke working sites (pzwiki.net, turbo.cr CDNs, the Darktide backend `fatsharkgames.com`/`atoma.cloud`). It was replaced by OISD big, which blocks a similar volume without taking down legitimate services. **All the manual whitelists created to work around Xtra were removed** — with OISD the domains resolved again without an allow.

## Microsoft Telemetry (exact denylist — priority)

Added as **exact deny** (they do not depend on a list):

- `telemetry.microsoft.com`, `telemetry.microsoft.us`
- `settings-win.data.microsoft.com`, `vortex.data.microsoft.com`
- `v10.events.data.microsoft.com`, `settings-sandbox.data.microsoft.com`
- `settings-ios.events.data.microsoft.com`, `diagnostics.support.microsoft.com`
- Wildcard: `events.data.microsoft.com` (`*.events.data.microsoft.com`)

Validated 09/08: all → `0.0.0.0` (blocked) across the whole tailnet.

## Manual whitelist (history — REMOVED on 18/08/2026)

The table below documents what **was already** whitelisted and **removed** on 18/08 along with the Xtra → OISD swap. Without 1Hosts Xtra, none of these domains needs an allow — they all resolve normally via OISD:

- `static.licdn.com`, `static.es.lnkdns.net`, `platform.linkedin.com` (LinkedIn)
- `log.tailscale.com` (Tailscale admin console)
- `pzwiki.net` (Project Zomboid wiki)
- `static.scdn.st` (turbo.cr CDN)
- `bunnyfonts.b-cdn.net` (Bunny fonts)
- `fatsharkgames.com`, `telemetry-global.fatsharkgames.com` (Darktide backend)
- `atoma-discovery.com`, `bsp-sup-sd.atoma-discovery.com` (Darktide discovery)
- `atoma.cloud`, `bsp-auth-prod.atoma.cloud`, `bsp-td-prod.atoma.cloud`, `bsp-cdn-prod.atoma.cloud` (Atoma Darktide services)

> If a working domain starts breaking with OISD, only then create a targeted allow and document it here — with OISD that should be rare.
> Applying an allow (if ever needed in the future): `docker exec pihole pihole allow <domínio>` (reloads DNS automatically).

## Instance

- Compose: `/srv/data/pihole/compose.yml` (`network_mode: host`).
- Config: `/srv/data/pihole/etc-pihole/` (mirrored to the NAS via kavure's `config-backup`).
- Update gravity: `docker exec pihole pihole -g`.
