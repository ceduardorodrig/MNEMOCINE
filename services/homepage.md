---
tags: [homelab, service, homepage, monitoring]
---

# Homepage

Central homelab dashboard — aggregates links and status for all services.

**Server:** ybytu
**Port:** `3001`
**URL:** `http://ybytu.chimaera-heptatonic.ts.net:3001`

## Stack

| Container | Image | Status |
|---|---|---|
| homepage | ghcr.io/gethomepage/homepage:latest | Up |

## Configuration

Homepage uses YAML files in `/app/config/` (host: `/home/ubuntu/homelab/homepage/config/`).

Configuration files:
- `docker.yaml` — connected Docker instances (automatic up/down status)
- `services.yaml` — services by group
- `bookmarks.yaml` — bookmarks
- `settings.yaml` — theme and layout
- `widgets.yaml` — widgets (Disk, Weather, etc.)

### Docker instances (`docker.yaml`)

| Instance | Endpoint | Server |
|---|---|---|
| `ybytu` | `/var/run/docker.sock` | local |
| `psicopompo` | `100.82.51.112:2375` | dockerproxy |
| `kuaray` | `100.94.209.99:2375` | dockerproxy |
| `kavure` | `100.124.146.77:2375` | dockerproxy |

Every service in `services.yaml` with `server:` + `container:` shows up/down status automatically. Exited containers (e.g. kuaray) show as down with no manual config.

### `services.yaml` groups (10/09/2026)

Current order (cloud at the end):
1. **Psicopompo (Workstation)** — **Ligar Kavure (WoL)**, Syncthing, Punktfunk, Glances
2. **Kavure (Services)** — **Ligar Psicopompo (WoL)**, Project Zomboid, Zomboid Control Panel, Crafty Controller, Minecraft Server, Valheim Server, Sumænimá API, Sumænimá Backup, **AioStreams, Comet**, **WordPress (10/09)**, **Directus (10/09)**, **NPM Admin (10/09)**, **n8n (10/09 — Docker badge)**, **Grafana (28/08)**, **Prometheus (28/08)**, **SearXNG (28/08)**, Pi-hole, Home Assistant, Navidrome, Calibre Web, Glances
3. **Kuaray (Media and Automation)** — Syncthing, Transmission, Prowlarr, Lidarr, slskd, FlareSolverr, Soularr, Vert, Glances
4. **Ybytu (Cloud)** — AdGuard Home, Glances, Uptime Kuma, Changedetection, Ntfy
5. **Ybyra (Cloud)** — Sumænimá (Primary Edge), Glances

> **08/08/2026:** **CasaOS removed** (uninstalled from kuaray); **Crafty/Minecraft migrated** to kavure (Kavure group); groups reordered (cloud at the end).
>
> **28/08/2026:** **Infra in all groups** — each host gained `Watchtower`, `Autoheal`, `Node Exporter`, `Promtail` badges (`server:` + `container:`, docker badge pattern) to show the status of the infra/monitoring containers. Container names per host: `autoheal-autoheal-1` (kuaray), `monitoring-promtail` (kavure), `promtail` (the others).
>
> **09/08/2026:** **aiostreams and comet migrated from kuaray → kavure** (Kavure group, `100.124.146.77:3000` and `:8000`); removed from the Kuaray group. Internal URLs (tailnet) kept following the group's pattern.
> **Crafty Controller** web moved to port **`8444`** (`8443` became the aiostreams funnel — later migrated to `:10000` on 18/09/2026, see note below) + docker badge; **Minecraft Server** uses `siteMonitor` on the `minecraft-status` endpoint (kavure `:9095`, SLP probe → small chip with the real game status).
>
> **Pi-hole and Home Assistant migrated from kuaray → kavure** (Kavure group); **Home Assistant** switched to **tailnet-only access** (`http://100.124.146.77:8123`, no public Funnel — 18/09/2026); **AioStreams** moved to Funnel port **`:10000`** (`kavure.chimaera-heptatonic.ts.net:10000` → `localhost:3000`) — port `:8443` was invalid for Tailscale public Funnel (supported: 443, 8080, 10000); removed from the Kuaray group.
>
> **Navidrome and Calibre Web** in the Kavure group; **Kavita removed (10/08)** — entry pulled from the Kavure group and the container uninstalled from kavure.
> **Minecraft Server** `description` fixed to **`Docker`** — the Dominium server runs as a **Java subprocess inside the `crafty-controller` container** (bind-mount `MINECRAFT SERVER` → `/crafty/servers/dominium`); it is neither a separate container nor native. Only the `minecraft-status.service` probe (systemd, `:9095`) is native.
> **Pi-hole** `icon` swapped to **`pi-hole`** (colored Dashboard Icons; the local `pihole.svg` was monochrome).
>
> **26/08/2026:** **Mosquitto removed from the dashboard** (the container had already been removed from kuaray on 16/08 — orphan entry) and **Rclone GUI removed** (webgui disabled/deleted on psicopompo — port `46295` freed; the homepage siteMonitor was the only connection to that port). Config backup: `services.yaml.bak-20260826`.
>
> **01/09/2026:** **Wake-on-LAN added** — the "Ligar Kavure" entry (Psicopompo group) and the "Ligar Psicopompo" entry (Kavure group) with an `href` to the WoL relay (`wol-relay.py`, port `9096`) + `siteMonitor` for the health chip. See [`wol-relay`](wol-relay.md).
>
> **29/08/2026:** **`Sumænimá (Borda Secundária)` removed from the Kuaray group** — kuaray deprecated in Sumænimá (the secondary edge stops using `kuaray:8085`); the standby now lives on **kavure** (see `network/service-topology.md`). The Kuaray group keeps only the Homelab media/automation services. **`Sumænimá Backup`** (Kavure group) is ✅ again — the `:9092` health server started answering **HEAD** (widget bug: `BaseHTTPRequestHandler` without `do_HEAD` → 501 on Homepage's HEAD probe; fixed on 29/08). The monitor points to `http://100.124.146.77:9092/health`.
>
> **09/09/2026:** **Valheim Server added** to the Kavure group — `valheim-server` (Docker, `mbround18/valheim:3`, port `2456`/udp). Docker badge (container `valheim-server`). Icon `valheim.png` (walkxcode/dashboard-icons). See [`valheim-server`](valheim/valheim-server.md).
>
> **10/09/2026:** **Miracena Stack added** to the Kavure group — **WordPress** (`miracena-wordpress`, `:8085`), **Directus** (`miracena-directus`, `:8055`), **NPM Admin** (`miracena-nginx-proxy-manager`, `:81`). **n8n updated** to the Docker badge (`miracena-n8n`). All Miracena stack services now show on the dashboard with up/down status and a `Docker · Miracena` label for differentiation. See [`miracena-stack`](miracena-stack.md).

### Status pattern (CONVENTION — ALWAYS follow on new additions)

| Service type | Status source | Config in `services.yaml` |
|---|---|---|
| **HTTP service** | `siteMonitor` chip — ping in **ms** | `siteMonitor: <url>` |
| **Docker service without HTTP** (games, MQTT) | Docker badge (running/stopped dot) | `server:` + `container:` |
| **Native service** (systemd/process, no container) | `siteMonitor` chip | `siteMonitor: <url>` |

**Rules:**
1. **HTTP → `siteMonitor`** (chip with ms). This is the preferred default.
2. **No HTTP → docker badge** (`server` + `container`). E.g.: Project Zomboid (`pz-server`).
   - **Games with their own protocol (e.g. Minecraft)** → for the **small (default) chip + the real game status**, use a **mini HTTP status endpoint** on the host and `siteMonitor: <url>`. On kavure: the `minecraft-status` service (port `9095`, Minecraft SLP probe on `25565` → 200 up / 503 down). Do not use the `crafty-controller` badge (the container is always up and misleading) nor the `minecraft` widget (it renders a 3-field panel, off-pattern).
3. **⚠️ Avoid the `customapi` widget** — it renders a **panel** (not the default chip) and breaks easily (e.g. API error). Only use it if there is no alternative, and validate the look.
4. **Env vars**: for secrets/configs in gethomepage, define them in the config dir's `.env` with the **`HOMEPAGE_VAR_` prefix** (e.g. `HOMEPAGE_VAR_CRAFTY_API_KEY=...`) and reference `{{HOMEPAGE_VAR_CRAFTY_API_KEY}}`. Without the prefix the var stays undefined.
5. **Swarm services** (sae-core/sae-edge): badge via the service name + `swarm: true` on the `docker.yaml` instance (dockerproxy with `SERVICES=1`).

### Custom icons (config/icons/)

| Icon | Source |
|---|---|
| `sumaenima.svg` | Sumænimá logo (`logo-8.svg`) |
| `zomboid.png` | Project Zomboid's Spiffo mascot (`spiffo.png` from the `fpsacha/zomboid-control-panel` repo) |
| `zombie.svg` | panel asset (`zombie.svg` from the same repo) |

> **uptime-kuma monitors (07/08/2026):** fixed psicopompo's old IP (`100.76.19.118` → `100.82.51.112`)
> on Crafty, Syncthing and Sumænimá API; **Sumænimá Backup disabled** (migration); **AdGuard** goes back to using the
> bridge IP (`172.17.0.5:3000`) — containers on ybytu cannot reach the tailnet's own IP (`EHOSTUNREACH`).
> Sumænimá icon: `config/icons/sumaenima.svg` (source `logo-8.svg`).

## Maintenance

```bash
docker restart homepage
```

> **Applying config changes:** Homepage is **static** — after editing `services.yaml`/`settings.yaml` etc., regenerate the HTML with the **refresh button** (bottom-right corner) or:
> ```bash
> curl http://127.0.0.1:3001/api/revalidate   # takes ~1 min; returns when finished
> ```
> No rebuild or container recreation needed. `docker restart homepage` also works (reloads on the first request).

> **⚠️ Healthcheck:** the image uses `wget 127.0.0.1:3000` (IPv4) but Next.js 16 listens on IPv6 — the default healthcheck fails and autoheal restarts in a loop. Fixed in `docker-compose.yml` with a custom healthcheck using `[::1]` (06/08/2026). Backup of the original in `docker-compose.yml.bak`.

Container logs are handled by Docker, and watchtower does the auto-update.
