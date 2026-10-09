---
tags: [homelab, recovery, checklist, todo]
---

# Checklist — Post-Migration kuaray (09/08/2026)

> ✅ **RESOLVED (10/08/2026)** — Post-migration tasks executed (config-as-code, watchtower, Syncthing re-paired, migrations). Details in `recovery/disaster-recovery.md` and `servers/kuaray.md`.

> Context: Data loss in `/DATA/AppData` (CasaOS removed) on kuaray → configurations deleted without backups.  
> Migration: **aiostreams + comet → kavure**; remaining applications retained on kuaray.  
> Tracking checklist preserved for audit history.

## Action Items

- [ ] **Reconfigure AIOStreams** at `https://kavure.chimaera-heptatonic.ts.net:8443/stremio/configure` (debrid credentials, marketplace, filters, custom formatter)
- [ ] **Reconfigure Comet** at `http://kavure.chimaera-heptatonic.ts.net:8000` (debrid, scraping sources)
- [ ] **Reconfigure Home Assistant** (kavure, `kavure.chimaera-heptatonic.ts.net:10000`) — fresh configuration
      - ✅ **HA Funnel Corrected (09/08):** HA 2026.8 ignores `http:` in `configuration.yaml` (managed via UI) → `trusted_proxies`/`use_x_forwarded_for` configured in `.storage/http`. Funnel `:10000` OK.
      - ⚠️ HA serves **HTTP** locally; HTTPS provided strictly via Tailscale Funnel (decision 16/08).
      - ✅ **Container Capabilities (16/08):** `cap_add: [NET_ADMIN, NET_RAW]` enabled.
      - ✅ **HACS 2.0.5 Installed & Configured (16/08)** — GitHub OAuth validated.
      - ⏳ **Tuya (Cloud)** and **automated backups** — configured in UI.
- [ ] **Reconfigure Pi-hole** (kuaray) — default blocklists restored; DNS resolution operational.
- [x] **Mosquitto (kuaray)** — **DECOMMISSIONED 16/08/2026** (container + directories purged). No active MQTT devices. See [`services/mosquitto.md`](../services/mosquitto.md).
- [ ] **arr-stack (kuaray)** — Transmission, Lidarr, Prowlarr, slskd, Soularr, Syncthing: configuration reset (reconfigured + Syncthing paired with new device ID).
- [ ] **Watchtower on kuaray** — paused (`docker update --restart=no` + stopped); kavure Watchtower manages active workloads.
- [ ] **`sae-core_api` crashing on kavure** (Swarm) — investigated and resolved.
- [ ] **Establish structured configuration backup** — `config-backup` deployed across all hosts.

## Sensitive Information

> Credentials removed per security governance policy (08/09/2026) — managed in **sops/age secret store** (`/mnt/NVME_PCI/secrets/`, see `guides/secrets-centralizados.md`).

## Post-Migration Layout

| Host | Data Path |
|---|---|
| kuaray | `/home/kuaray/docker/<app>/` (prowlarr, lidarr, transmission, soularr, slskd, syncthing, mosquitto, homeassistant, pihole) |
| kavure | `/srv/data/aiostreams`, `/srv/data/comet` |

- CasaOS **purged** from kuaray (previously mounted `/DATA/AppData`).
- Funnels: kavure `kavure.chimaera-heptatonic.ts.net:8443` → aiostreams; kuaray `:10000` → Home Assistant.

## References

- [`services/aiostreams.md`](../services/aiostreams.md)
- [`services/comet.md`](../services/comet.md)
- [`services/homepage.md`](../services/homepage.md)
- [`servers/kuaray.md`](../servers/kuaray.md)
- [`servers/kavure.md`](../servers/kavure.md)
- [`network/tailscale.md`](../network/tailscale.md)
