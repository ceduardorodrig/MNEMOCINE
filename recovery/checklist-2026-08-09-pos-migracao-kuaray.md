---
tags: [homelab, recovery, checklist, todo]
---

# Checklist — Post-migration kuaray (09/08/2026)

> ✅ **RESOLVED (10/08/2026)** — outstanding items executed (config-as-code, watchtower, syncthing re-paired, migrations). Details in `recovery/disaster-recovery.md` and `servers/kuaray.md`.

> Context: loss of `/DATA/AppData` (CasaOS removed) on kuaray → configs deleted with no backup.
> Migration: **aiostreams + comet → kavure**; the remaining apps stayed on kuaray.
> Checklist of outstanding items to pick up later.

## Outstanding items

- [ ] **Reconfigure AIOStreams** at `https://kavure.chimaera-heptatonic.ts.net:8443/stremio/configure`
      (debrid keys, marketplace, filters, custom formatter)
- [ ] **Reconfigure Comet** at `http://kavure.chimaera-heptatonic.ts.net:8000` (debrid, scrape sources)
- [ ] **Reconfigure Home Assistant** (kavure, `kavure.chimaera-heptatonic.ts.net:10000`) — config new/empty
      - ✅ **HA Funnel fixed (09/08):** HA 2026.8 ignores `http:` in `configuration.yaml` (migrated to the UI) → `trusted_proxies`/`use_x_forwarded_for` applied straight to `.storage/http`. Funnel `:10000` OK.
      - ⚠️ HA now serves **HTTP** (SSL cert lost with the config); HTTPS only via the Tailscale funnel (16/08 decision).
      - ✅ **Container fixed (16/08):** `cap_add: [NET_ADMIN, NET_RAW]` → Bluetooth working.
      - ✅ **HACS 2.0.5 installed and configured (16/08)** — GitHub OAuth OK, repos downloaded.
      - ⏳ **Tuya (cloud)** and **automatic backup** — pending config in the UI.
- [ ] **Reconfigure Pi-hole** (kuaray) — adlists/blocklists went back to default; DNS ok
- [x] **Mosquitto (kuaray)** — **REMOVED 16/08/2026** (container + folders). No MQTT devices in use; if needed, recreate on kavure with credentials. See [`services/mosquitto.md`](../services/mosquitto.md)
- [ ] **arr-stack (kuaray)** — Transmission, Lidarr, Prowlarr, slskd, Soularr, Syncthing: configs were reset (reconfigure + re-pair Syncthing, new device ID)
- [ ] **Watchtower kuaray** — paused (`docker update --restart=no` + stop); decide whether to bring it back. Watchtower on **kavure** (03:00 BRT) already manages aiostreams/comet
- [ ] **`sae-core_api` crashing on kavure** (swarm) — investigate (untouched by the migration)
- [ ] **Define a structured backup of configs** — duplicati removed (06/08); today there is no config backup

## Sensitive information

> Values removed by policy (08/09/2026) — secrets live in the **sops/age store** (`/mnt/NVME_PCI/secrets/`, see `guides/secrets-centralizados.md`). aiostreams' SECRET_KEY and the sudo passwords were moved there.

## Post-migration layout

| Host | Data path |
|---|---|
| kuaray | `/home/kuaray/docker/<app>/` (prowlarr, lidarr, transmission, soularr, slskd, syncthing, mosquitto, homeassistant, pihole) |
| kavure | `/srv/data/aiostreams`, `/srv/data/comet` |

- CasaOS **removed** from kuaray (it was what mounted `/DATA/AppData`)
- Funnels: kavure `kavure.chimaera-heptatonic.ts.net:8443` → aiostreams; kuaray `:10000` → Home Assistant

## References

- [`services/aiostreams.md`](../services/aiostreams.md)
- [`services/comet.md`](../services/comet.md)
- [`services/homepage.md`](../services/homepage.md)
- [`servers/kuaray.md`](../servers/kuaray.md)
- [`servers/kavure.md`](../servers/kavure.md)
- [`network/tailscale.md`](../network/tailscale.md)
