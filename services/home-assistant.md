---
tags: [homelab, service, home-assistant, automation]
---

# Home Assistant

Home automation platform.

**Server:** kavure (migrated 09/08/2026, previously kuaray)  
**Port:** `8123` (host network)  
**Funnel:** `kavure.chimaera-heptatonic.ts.net:10000`  
**Internal URL:** `http://kavure.chimaera-heptatonic.ts.net:8123`  
**Public URL:** `https://kavure.chimaera-heptatonic.ts.net:10000`  
**Version:** 2026.8.2  

> **Status (16/08/2026):** **Fresh** configuration (data lost on 08/08 alongside CasaOS; onboarding completed 16/08).  
> Container running with `cap_add: [NET_ADMIN, NET_RAW]` (recommended by official docs; **kavure lacks Bluetooth hardware** — integration removed). **HACS 2.0.5 installed and configured** (GitHub OAuth OK). **Tuya (cloud)** and **automatic backup** pending UI setup. Internal HTTP access + HTTPS via Tailscale Funnel.

## Stack

| Container | Image | Function |
|---|---|---|
| homeassistant | homeassistant/home-assistant:latest | Automation platform (host network, `cap_add: [NET_ADMIN, NET_RAW]`) |

- **MQTT:** Removed (16/08) — no active MQTT devices; mosquitto retired from kuaray. If needed in the future, recreate on **kavure** with authentication (`allow_anonymous false`).

## Ports

| Port | Service | Bind |
|---|---|---|
| `8123` | Home Assistant web UI | host (0.0.0.0) |
| `18554` | go2rtc WebRTC (embedded) | 127.0.0.1 |

## Access

- **Tailscale:** `http://kavure.chimaera-heptatonic.ts.net:8123`
- **Public:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Funnel — HTTPS only here; internal access is plain HTTP, design decision 16/08)
- `trusted_proxies` (`127.0.0.1`, `::1`) applied in `.storage/http` (HA 2026.8 ignores `http:` in YAML).

## Integrations

- **Bluetooth** — **No hardware on kavure** (no USB/PCI adapter, bluez not installed). Scanner data (`54:35:30:FE:E7:66`, `TY` sensor) belonged to kuaray, inherited during migration. Integration **removed on 16/08** (entry deleted from `.storage/core.config_entries`). The `NET_ADMIN`/`NET_RAW` capabilities remain in Compose (harmless) — if a USB BT dongle or ESP32 proxy is connected in the future, simply re-add the integration.
- **go2rtc** (embedded, `source: system`) — Internal server `:18554`; cameras not yet configured.
- **Tuya** (cloud, **added 16/08**) — Wi-Fi bulbs + door sensors (via Tuya Zigbee hub, shared Smart Life account).
- **HACS** (installed and **configured 16/08** — GitHub OAuth OK, `hacs.repositories` fetched).
- **Material You Utilities** (HACS frontend module, activated 16/08) — `frontend.extra_module_url` + `panel_custom` in `configuration.yaml` ("Material You Utilities" panel in sidebar).
- **Adaptive Lighting** (HACS, activated 16/08) — **Mnemocine** entry (`switch.adaptive_lighting_mnemoncine` + sleep/adapt switches), controls 4 bulbs (`light.sink_lamp`, `light.fridge_lamp`, `light.door_lamp`, `light.desk_lamp`). Defaults: `take_over_control: true` (yields to manual adjustments via HA/app), `detect_non_ha_changes: false` (changes via Smart Life app are NOT detected), `only_once: false`, color_temp 2000–5500K. Config via UI: *Settings > Devices & Services > Adaptive Lighting: Mnemocine > Options*.
  - **Sleep mode** (`switch.adaptive_lighting_mnemoncine_..._sleep_mode_mnemoncine`) = On-demand dim nightlight mode (1% brightness + 1000K); adjustable in Options (`sleep_brightness`/`sleep_color_temp`). Accidental activation on 16/08 caused 1% light during daytime.
  - `adaptive_lighting:` YAML stub is NOT needed for UI-based usage (creates duplicate "default" entry) — removed on 16/08.
  - "Default" entry deleted on 16/08; orphaned switches cleaned up automatically by HA.
- **Tuya Local** (HACS/manual, installed 05/10/2026 — `make-all/tuya-local` v2026.9.2-rel) — Local control via Tuya v3.5 protocol (TCP port 6668) with direct LAN AES encryption, bypassing cloud roundtrips. 4 mapped Pera NEO 10W bulbs (`xtsnfp5zitrmrvcm`):
  - `light.fridge_lamp`: `192.168.3.36` (`ebad09d02f9a032599orxw`)
  - `light.door_lamp`: `192.168.3.37` (`eb1449c7f8e24b42c9tlul`)
  - `light.sink_lamp`: `192.168.3.38` (`eb265a47aa07addb92og5y`)
  - `light.desk_lamp`: `192.168.3.39` (`eb3e1d8d3093726ddb5anv`)
- **Backup** (native, **activated 16/08** with encryption — key `HA_BACKUP_ENCRYPTION_KEY` in sops/age store; automated daily, 3-snapshot retention; initial 20 MB backup at 14:09).

## Data

- `/srv/data/homeassistant/` on kavure (`compose.yml` + `config/`).
- Mirrored daily by `config-backup` → `/mnt/BACKUP/configs-homelab/kavure/data/homeassistant`.
- Native HA backup (`.tar` snapshots in `config/backups`) — configured in UI (Settings > System > Backups).
- `secrets.yaml` (`some_password`) **captured in sops store on 28/08** (`HA_SOME_PASSWORD`; restore via `inject-secrets.sh`) — see `guides/secrets-centralizados.md`. `secrets.yaml` is excluded from the `config-backup` mirror.
