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

> **State (16/08/2026):** **new** config (data lost on 08/08 along with CasaOS; onboarding completed on 16/08).
> Container with `cap_add: [NET_ADMIN, NET_RAW]` (recommended by the official docs; **kavure has no
> Bluetooth hardware** — integration removed). **HACS 2.0.5 installed and configured** (GitHub OAuth OK). **Tuya (cloud)**
> and **automatic backup** still pending setup in the UI. Internal HTTP access + HTTPS via the Tailscale funnel.

## Stack

| Container | Image | Role |
|---|---|---|
| homeassistant | homeassistant/home-assistant:latest | Automation (host network, `cap_add: [NET_ADMIN, NET_RAW]`) |

- **MQTT:** removed (16/08) — no MQTT devices in use; mosquitto pulled from kuaray. If needed in the future, recreate it on **kavure** with credentials (`allow_anonymous false`).

## Ports

| Port | Service | Bind |
|---|---|---|
| `8123` | Home Assistant web UI | host (0.0.0.0) |
| `18554` | go2rtc WebRTC (built-in) | 127.0.0.1 |

## Access

- **Tailscale:** `http://kavure.chimaera-heptatonic.ts.net:8123`
- **Public:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Funnel — HTTPS only here; internal is HTTP, decision 16/08)
- `trusted_proxies` (`127.0.0.1`, `::1`) applied in `.storage/http` (HA 2026.8 ignores the yaml's `http:`).

## Integrations

- **Bluetooth** — **no hardware on kavure** (no USB/PCI adapter, bluez not installed). The scanner data
  (`54:35:30:FE:E7:66`, sensor `TY`) came from kuaray, inherited in the migration. Integration **removed on 16/08**
  (entry deleted from `.storage/core.config_entries`). The `NET_ADMIN`/`NET_RAW` caps stay in the compose
  (harmless) — if you ever plug in a USB BT dongle or an ESP32 proxy, just re-add the integration.
- **go2rtc** (built-in, `source: system`) — internal server `:18554`; cameras not configured yet
- **Tuya** (cloud, **added on 16/08**) — Wi-Fi bulbs + door sensors (via a Tuya Zigbee hub, same Smart Life account)
- **HACS** (installed and **configured on 16/08** — GitHub OAuth OK, `hacs.repositories` downloaded)
- **Material You Utilities** (HACS frontend module, enabled 16/08) — `frontend.extra_module_url` + `panel_custom` in `configuration.yaml` ("Material You Utilities" panel in the sidebar)
- **Adaptive Lighting** (HACS, enabled 16/08) — **Mnemocine** entry (`switch.adaptive_lighting_mnemoncine` + sleep/adapt switches), controls the 4 bulbs (`light.sink_lamp`, `light.fridge_lamp`, `light.door_lamp`, `light.desk_lamp`). Defaults: `take_over_control: true` (yields to manual changes made via HA/app), `detect_non_ha_changes: false` (changes made in the Smart Life app are NOT detected), `only_once: false`, color_temp 2000–5500K. Config via UI: *Settings > Devices & Services > Adaptive Lighting: Mnemocine > Options*
  - **Sleep mode** (`switch.adaptive_lighting_mnemoncine_..._sleep_mode_mnemoncine`) = on-demand "very dim light" mode (1% brightness + 1000K); adjustable in Options (`sleep_brightness`/`sleep_color_temp`). Accidentally enabled on 16/08 (left the lights at 1% during the day).
  - A `adaptive_lighting:` stub is NOT needed in the YAML for UI use (it creates a duplicate "default" entry) — removed on 16/08.
  - The "default" entry was deleted on 16/08; orphan switches removed automatically by HA.
- **Backup** (native, **enabled on 16/08** with encryption — key `HA_BACKUP_ENCRYPTION_KEY` in the sops/age store; daily automatic, 3 copies retained; 1st backup 20 MB at 14:09)

## Data

- `/srv/data/homeassistant/` on kavure (`compose.yml` + `config/`).
- Mirrored daily by `config-backup` → `/mnt/BACKUP/configs-homelab/kavure/data/homeassistant`.
- HA's native backup (`.tar` snapshots in `config/backups`) — enable it in the UI (Settings > System > Backups).
- `secrets.yaml` (`some_password`) **captured in the sops store on 28/08** (`HA_SOME_PASSWORD`; restore via `inject-secrets.sh`) — see `guides/secrets-centralizados.md`. `secrets.yaml` is excluded from the `config-backup` mirror.
