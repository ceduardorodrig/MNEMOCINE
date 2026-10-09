---
tags: [homelab, service, uptime-kuma, monitoring, server, ybytu]
---

# Uptime Kuma

**Role:** Uptime monitoring daemon executing HTTP(S), TCP, and Ping probes across the Tailnet.

## Deployment

- **Server:** ybytu
- **Container:** `uptime-kuma`
- **Image:** `louislam/uptime-kuma:latest`
- **Network:** **`network_mode: host`** (07/10/2026) + `UPTIME_KUMA_PORT: 3002` — Required because ybytu's `INPUT` iptables policy is **default-deny** (only loopback is accepted): In bridge mode, the container **failed to reach** local host services (`EHOSTUNREACH` on 3002/8082/8083/61208; only port 3000 passed via DNAT).
- **Volume:** `./data` → `/app/data`
- **Compose:** `/home/ubuntu/homelab/uptime-kuma/compose.yml` (previous backup: `.bak-20261007-hostnet`)
- **Restart Policy:** `unless-stopped`

> ⚠️ **`kuma.db` is NOT mirrored to NAS:** `config-backup` excludes `*.db` files — which caused the ~38 monitors lost during the 16/09 recreation to become **unrecoverable**. Reconstructed on 07/10/2026 from Homepage configuration (see below). **Action item:** Schedule automated SQLite export dumps (or `kuma.db` snapshots) to backup storage.

## Access

- **URL:** `http://ybytu.chimaera-heptatonic.ts.net:3002`
- **Login:** `admin` — Credentials managed in **sops store** (`UPTIME_KUMA_ADMIN_USER` / `UPTIME_KUMA_ADMIN_PASSWORD`, added 06/10/2026). In SQLite, passwords are stored as **bcrypt hashes** and cannot be read in plaintext.
- **Password Reset CLI (28/08/2026):**
  ```bash
  docker exec -it uptime-kuma npm run reset-password
  ```
  (interactive prompt; or `npm run reset-password -- --new_password='<new_password>'`). Remove 2FA: `npm run remove-2fa`. See [Reset-Password-via-CLI](https://github.com/louislam/uptime-kuma/wiki/Reset-Password-via-CLI).

## Operational Motivation

Oracle Cloud reclaims idle ARM and AMD Always-Free VMs if average 7-day CPU utilization drops below 20% and network utilization drops below 20%. Uptime Kuma was deployed to generate genuine telemetry traffic (HTTP, TCP, Ping) over Tailscale to all homelab nodes, keeping the cloud instances marked active.

## Monitors

> **Reconstructed on 07/10/2026 — 51 active monitors, all UP.** The historical table below (41 monitors) is kept for reference. Current state was rebuilt using **Homepage** (`services.yaml`) as the source of truth for URLs + **3 dedicated DNS monitors** (Pi-hole, AdGuard, and local home route):
> - **48 HTTP probes** (services with web endpoints) + **6 ICMP pings** (psicopompo, kavure, kuaray, ybytu, ybyra, kururu)… total 54 definitions, of which **51 remained active** after tuning accepted status codes (registry 400/401, transmission 401/409).
> - Local services on ybytu monitored via **`127.0.0.1`** (host networking); `glances` via Tailscale IP (binds strictly there).
> - Automation: Executed via Socket.IO API (`login` → `deleteMonitor` → `add`) using an ephemeral Node.js script inside the container.

### Historical List (41 Monitors, Pre-16/09)

41 monitors previously provisioned in SQLite (`/app/data/kuma.db`), categorized across 4 groups:

| Group | Count | Targets |
|---|---|---|
| Kavure | ~12 | Swarm sae-core (API, backup, Valkey), Game servers (Minecraft/Crafty, Zomboid, Valheim), Home Assistant, Pi-hole, Glances |
| Psicopompo | 4 | StênioREC, Glances, Ping, Syncthing |
| Ybytu | 7 | AdGuard, Homepage, Uptime Kuma, Filebrowser, Syncthing, Glances, Changedetection, Ntfy |
| Ybyra | 6 | API Proxy (external), SPA, Funnel, Umami, Datavis, Glances, Ping |
| Kuaray | ~5 | Standby mirror, Glances, Ping |

### DNS Resolution Monitors (Rebuilt 06/10/2026)

Created via **Socket.IO** (native application API, avoiding direct SQLite schema mutation):

| ID | Name | Type | Target |
|---|---|---|---|
| 1 | DNS · Pi-hole (kavure) | DNS (A) | `100.124.146.77` |
| 2 | DNS · AdGuard (ybytu) | DNS (A) | `100.115.253.109` |
| 3 | DNS · Home Primary Route | DNS (A) | `100.100.100.100` (Tailscale magic IP) |

> These three monitors cover the entire resolution pipeline: If `unbound` (or previously `dnscrypt-proxy`) on kavure fails, Monitor 1 trips; Monitor 3 validates the end-to-end lookup path utilized by client devices. See [`unbound`](unbound.md).

> **Migration Context:** Previously, Crafty/Minecraft and the core API resided on Psicopompo, and *arr/HA on Kuaray. Following consolidation onto Kavure (08-09/2026), probes were remapped to their active hosts.

### Edge vs Physical Infrastructure Separation

Every service probe routing through Ybyra's Nginx reverse proxy carries the `Proxy` prefix to distinguish public ingress from the physical backing node:

| ID | Name | URL | Monitored Target |
|---|---|---|---|
| 4 | Ybyra - Proxy API Sumænimá (External) | `http://100.66.224.34/api/health` | Nginx reverse proxy → API on kavure |
| 5 | Ybyra - Proxy Umami | `http://100.66.224.34/` | Nginx proxy → Umami on Ybyra |
| 15 | Ybyra - Proxy SPA Sumænimá | `http://100.66.224.34/` | Nginx proxy → Frontend SPA |
| 48 | ~~Ybyra - Proxy Datavis Sumænimá~~ | ~~`http://100.66.224.34/api/datavis/health`~~ | ~~Nginx proxy → Datavis on Ybyra~~ **removed 22/09/2026 (legacy)** |
| 46 | Ybyra - Funnel Sumænimá | `https://sumaenima.chimaera-heptatonic.ts.net` | Public Tailscale Funnel (HTTPS) |
| 50 | Psicopompo - Sumænimá API (Internal) | `http://100.124.146.77:9090/api/health` | Direct API on kavure via Tailscale |

> ⚠️ **Finding (22/09/2026):** Container `uptime-kuma` was **recreated on 16/09** and the database (`~/homelab/uptime-kuma/data/kuma.db`) was left **without monitors and without an admin user** (`monitor` table empty, `user` table empty, `/setup` screen exposed). All previous monitors (including #48 datavis) **were lost during that recreation**.  
>  
> **Resolved on 06/10/2026 & 07/10/2026:** Admin account recreated and all 51 monitors restored via Socket.IO automation. See [`services/monitoring.md`](monitoring.md) for Prometheus/Alertmanager coverage.

### Notifications — ntfy (Rebuilt 07/10/2026)

Recreation also wiped **notification channels**. Reconstructed via Socket.IO `addNotification(notification, notificationID, callback)`:

| Field | Value |
|---|---|
| Type | `ntfy` |
| Server | `http://127.0.0.1:8083` (Uptime Kuma runs on the same host under `network_mode: host`) |
| Topic | **`alerts`** (shared with Alertmanager — `http://ybytu…:8083/alerts`) |
| Authentication | None (ntfy runs unauthenticated on tailnet) |
| Priority | 3 |
| `isDefault` / `applyExisting` | `true` / `true` → **51 bindings** (all monitors attached) |

**Validated End-to-End:** `testNotification` sent real test payload arriving at the `alerts` topic (`alerts [Uptime-Kuma]`).

> The companion topic utilized in homelab is **`backup`** (dedicated to `config-backup` reports).

### Kernel Guard

The `pm_tailscale_funnel` kernel driver periodically validates:
- `edge.yml` contains correct `configs:` and `ports: 80`
- `serve.json` mounted via Docker Configs
- Funnel responds with HTTPS 200
- Fails closed if configurations drift — preventing accidental loss of ingress routes

## Notes

- Configured without Docker Compose (`docker run` invocation).
- Monitors provisioned programmatically via Socket.IO rather than manual SQLite table edits.
- The bcrypt password hash was previously corrupted by bash variable expansion (`$`); generate password hashes inside the container environment using `node -e "bcrypt.hashSync(...)"`.
