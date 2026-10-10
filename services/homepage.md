---
tags: [homelab, service, homepage, monitoring]
---

# Homepage

Central homelab dashboard — aggregates links, live metrics, and real-time health across all services.

**Server:** ybytu  
**Port:** `3001`  
**URL:** `http://ybytu.chimaera-heptatonic.ts.net:3001`  

## Stack

| Container | Image | Status |
|---|---|---|
| homepage | ghcr.io/gethomepage/homepage:latest | Up |

> **`network_mode: host` + `PORT=3001` (07/10/2026):** Homepage transitioned from `ports: 3001:3000` (bridge) to **host networking** — identical rationale to Uptime Kuma: ybytu's `INPUT` iptables policy is **default-deny** (only loopback is accepted), so inside a bridge network the container **failed to reach** local host services (`EHOSTUNREACH` on `:3002`/`:8082`/`:61208`).  
>  
> Operational impact on `siteMonitor`: Local services on ybytu target **`127.0.0.1`** — with the exception of **glances** (`:61208`), which binds strictly to the Tailscale IP and retains `100.115.253.109`. The healthcheck was updated to `http://127.0.0.1:3001/api/healthcheck`: the compose `${PORT:-3000}` was evaluated **at parse time** to `3000` — which under host networking hit **AdGuard** (returning 401 and flagging Homepage as "unhealthy").

## Configuration

Homepage utilizes YAML files located in `/app/config/` (host: `/home/ubuntu/homelab/homepage/config/`).

Configuration files:
- `docker.yaml` — Connected Docker daemon instances (automatic up/down container status)
- `services.yaml` — Service definitions grouped by category
- `bookmarks.yaml` — Quick access bookmarks
- `settings.yaml` — Visual theme, layout, and header settings
- `widgets.yaml` — Dashboard widgets (Disk, Weather, etc.)

### Status Chips (Convention — 07/10/2026)

Homepage provides **two** distinct status indicators, and homelab governance enforces **strictly one per service**:

| Mechanism | Display | When to Use |
|---|---|---|
| `server:` + `container:` | **Docker chip** — "healthy"/"unhealthy" (container healthcheck state) | **Every containerized service** on a host configured in `docker.yaml` |
| `siteMonitor:` | **Latency in ms** (green/red) | **Non-containerized services** (native systemd) or **external/Swarm/Funnel** endpoints |

- **Current state:** 58 services with Docker chips, 10 with `siteMonitor`, **0 with duplicate chips**.
- Designated for `siteMonitor` (due to lacking a stable, persistent container name): Sumænimá Portal, Sumænimá API/Backup/Umami (**Swarm** services — container names change per task recreation), Minecraft and Valheim (native game protocols), Punktfunk/Syncthing-Psicopompo (bare-metal systemd), and **Wake-on-LAN** relays (`Power on Kavure/Psicopompo`).

> The Docker status chip reflects the container `healthcheck` — present on **all** production containers since 07/10 (see [`guides/docker-healthchecks.md`](../guides/docker-healthchecks.md)). This is the enforced default: it displays true internal operational health rather than mere port responsiveness.

> ⚠️ **Validation of `services.yaml` (07/10/2026):** PyYAML **does not** flag **duplicate mapping keys** (silently preserving the last occurrence) — a standard `yaml.safe_load` passed while Homepage crashed with `YAMLException: duplicated mapping key`. **Always** validate with a strict duplicate key checker (or `yamllint`) before recreating the container.

### Docker Instances (`docker.yaml`)

| Instance | Endpoint | Server |
|---|---|---|
| `ybytu` | `/var/run/docker.sock` | local |
| `psicopompo` | `100.82.51.112:2375` | dockerproxy |
| `kuaray` | `100.94.209.99:2375` | dockerproxy |
| `kavure` | `100.124.146.77:2375` | dockerproxy |

Each service in `services.yaml` with `server:` + `container:` displays live status automatically. Containers in `Exited` states (e.g. on kuaray) appear offline without manual intervention.

### Groups in `services.yaml` (10/09/2026)

Active ordering (cloud infrastructure placed last):
1. **Psicopompo (Workstation)** — **Power on Kavure (WoL)**, Syncthing, Punktfunk, Glances
2. **Kavure (Services)** — **Power on Psicopompo (WoL)**, Project Zomboid, Zomboid Control Panel, Crafty Controller, Minecraft Server, Valheim Server, Sumænimá API, Sumænimá Backup, **AioStreams, Comet**, **WordPress (10/09)**, **Directus (10/09)**, **NPM Admin (10/09)**, **n8n (10/09 — Docker badge)**, **Grafana (28/08)**, **Prometheus (28/08)**, **SearXNG (28/08)**, Pi-hole, Home Assistant, Navidrome, Calibre Web, Glances
3. **Kuaray (Media & Automation)** — Syncthing, Transmission, Prowlarr, Lidarr, slskd, FlareSolverr, Soularr, Vert, Glances
4. **Ybytu (Cloud)** — AdGuard Home, Glances, Uptime Kuma, Changedetection, Ntfy
5. **Ybyra (Cloud)** — Sumænimá (Primary Edge), Glances

> **08/08/2026:** **CasaOS removed** (uninstalled from kuaray); **Crafty/Minecraft migrated** to kavure (Kavure group); groups reordered (cloud at the bottom).  
>  
> **28/08/2026:** **Infrastructure across all groups** — Each host received `Watchtower`, `Autoheal`, `Node Exporter`, and `Promtail` badges (`server:` + `container:`, Docker badge standard) to monitor core runtime infra. Container names per host: `autoheal-autoheal-1` (kuaray), `monitoring-promtail` (kavure), `promtail` (remaining nodes).  
>  
> **09/08/2026:** **aiostreams and comet migrated from kuaray → kavure** (Kavure group, `100.124.146.77:3000` and `:8000`); purged from Kuaray group. Internal tailnet URLs aligned with group standards.  
> **Crafty Controller** web moved to port **`8444`** (port `8443` was temporarily assigned to aiostreams funnel — later moved to `:10000` on 18/09/2026, see note below) + Docker badge; **Minecraft Server** uses `siteMonitor` pointing to the `minecraft-status` endpoint (kavure `:9095`, SLP probe → compact badge showing true game availability).  
>  
> **Pi-hole and Home Assistant migrated from kuaray → kavure** (Kavure group); **Home Assistant** restricted to **tailnet-only access** (`http://100.124.146.77:8123`, no public Funnel — 18/09/2026); **AioStreams** moved to Funnel port **`:10000`** (`kavure.chimaera-heptatonic.ts.net:10000` → `localhost:3000`) — port `:8443` is unsupported for public Tailscale Funnels (valid ports: 443, 8080, 10000); removed from Kuaray group.  
>  
> **Navidrome and Calibre Web** configured in Kavure group; **Kavita removed (10/08)** — entry removed from Kavure group and container purged from kavure.  
> **Minecraft Server** `description` updated to **`Docker`** — Dominium server executes as a **Java child process inside the `crafty-controller` container** (bind mount `MINECRAFT SERVER` → `/crafty/servers/dominium`); not an isolated container or bare-metal binary. Only the `minecraft-status.service` probe daemon (systemd, `:9095`) runs natively on the host.  
> **Pi-hole** `icon` updated to **`pi-hole`** (vibrant Dashboard Icons asset; the local `pihole.svg` was monochrome).  
>  
> **26/08/2026:** **Mosquitto removed from dashboard** (container uninstalled from kuaray on 16/08 — orphaned entry) and **Rclone GUI removed** (webgui disabled/deleted on psicopompo — port `46295` released; Homepage siteMonitor was the sole open connection). Configuration backup: `services.yaml.bak-20260826`.  
>  
> **01/09/2026:** **Wake-on-LAN integrated** — Entries "Power on Kavure" (Psicopompo group) and "Power on Psicopompo" (Kavure group) with `href` pointing to the WoL relay (Rust binary `wol-relay`/`kururu-wake`, port `9096` — legacy `wol-relay.py` archived in `scripts/archive/`) + `siteMonitor` for health metrics. See [`wol-relay`](wol-relay.md).  
> **02/10/2026:** ✅ **WoL resolved and verified** — Physical testing: kavure **29s** / psicopompo **54s** from soft-off, fully hands-off; root cause of earlier failures was BIOS `Deep Sleep Control`. See [`wol-relay.md`](wol-relay.md) §End-to-End Validation.  
>  
> **03/10/2026:** ⚡ **WoL Smart Dispatcher deployed on Ybytu (`100.115.253.109:9096`)**: Buttons aligned to their respective target cards ("Power on Psicopompo" on Psicopompo card, "Power on Kavure" on Kavure card). Endpoint points to the central dispatcher with automatic failover (attempts Kururu first; if offline, dispatches via x86 peer fallback). Backup: `services.yaml.bak-20261003`.  
>  
> **29/08/2026:** **`Sumænimá (Secondary Edge)` removed from Kuaray group** — kuaray deprecated from Sumænimá topology (secondary edge no longer targets `kuaray:8085`); hot standby now resides on **kavure** (see `network/service-topology.md`). Kuaray group solely hosts homelab media/automation. **`Sumænimá Backup`** (Kavure group) restored to ✅ — health server `:9092` now handles **HEAD** requests (resolved widget bug: `BaseHTTPRequestHandler` lacked `do_HEAD` → 501 on Homepage HEAD probes; fixed 29/08). Monitor points to `http://100.124.146.77:9092/health`.  
>  
> **09/09/2026:** **Valheim Server added** to Kavure group — `valheim-server` (Docker, `mbround18/valheim:3`, port `2456`/udp). Docker badge (container `valheim-server`). Icon `valheim.png` (walkxcode/dashboard-icons). See [`valheim-server`](valheim/valheim-server.md).  
>  
> **10/09/2026:** **Miracena Stack added** to Kavure group — **WordPress** (`miracena-wordpress`, `:8085`), **Directus** (`miracena-directus`, `:8055`), **NPM Admin** (`miracena-nginx-proxy-manager`, `:81`). **n8n updated** to Docker badge (`miracena-n8n`). All Miracena stack services appear on the dashboard with up/down health and label `Docker · Miracena`. See [`miracena-stack`](miracena-stack.md).  
>  
> **27/09/2026:** **Glances on Ybytu normalized + Restart Always Policy** — Glances on Ybytu transitioned from `siteMonitor` to Docker socket (`server: ybytu`, `container: glances`), eliminating HTTP 500 errors from `EHOSTUNREACH` (bridge loopback → tailscale0 blocked by iptables). Core infrastructure containers (`dockerproxy`, `glances`, `node-exporter`, `promtail`, `autoheal`, `watchtower`) updated with `restart: always` across all nodes (`psicopompo`, `ybyra`, `ybytu`) preventing persistent `exited` states following reboots.  
>  
> **09/10/2026:** **`n8n Homelab` tile added** to the **Kavure (Services)** group — the standalone Homelab n8n (`server: kavure`, `container: n8n`, `http://kavure:5678`) was reactivated and is **distinct** from the Miracena n8n (`container: miracena-n8n`, Kuaray group). Both now render live Docker chips. See [`n8n`](n8n.md).

> **09/10/2026 — Tile descriptions standardized to English (Tier A):** all `description:` values translated from PT-BR to EN (e.g. `Automação Homelab` → `Homelab Automation`, `Automação & Workflows` → `Automation & Workflows`, `Monitoramento Uptime` → `Uptime Monitoring`, `Servidor Push` → `Push Server`). Backup: `services.yaml.bak-20261009-en`; reloaded via `GET /api/revalidate`.

### Status Standard (CONVENTION — Enforced for all additions)

| Service Type | Status Source | Config in `services.yaml` |
|---|---|---|
| **HTTP Service** | Chip `siteMonitor` — latency in **ms** | `siteMonitor: <url>` |
| **Docker service without HTTP** (games, MQTT) | Docker badge (running/stopped dot) | `server:` + `container:` |
| **Native service** (systemd daemon without container) | Chip `siteMonitor` | `siteMonitor: <url>` |

**Rules:**
1. **HTTP → `siteMonitor`** (latency chip in ms). This is the preferred default.
2. **Non-HTTP → Docker badge** (`server` + `container`). E.g.: Project Zomboid (`pz-server`).
   - **Game servers with custom binary protocols (e.g. Minecraft)** → To maintain a **compact chip + true in-game state**, deploy a **lightweight HTTP status endpoint** on the host and configure `siteMonitor: <url>`. On kavure: `minecraft-status` service (port `9095`, Minecraft SLP probe on `25565` → 200 up / 503 down). Avoid the `crafty-controller` badge (the manager stays up even when the server crashes) and avoid the `minecraft` widget (renders an oversized 3-field card outside UI conventions).
3. **⚠️ Avoid `customapi` widget** — Renders an oversized card panel rather than a compact status chip and fails easily on API schema changes. Only use when no standard alternative exists and visually validated.
4. **Environment variables**: For credentials/tokens in gethomepage, define them in the config directory `.env` with the **`HOMEPAGE_VAR_` prefix** (e.g. `HOMEPAGE_VAR_CRAFTY_API_KEY=...`) and reference via `{{HOMEPAGE_VAR_CRAFTY_API_KEY}}`. Without the prefix, variables remain unset.
5. **Swarm services** (sae-core/sae-edge): Badge mapped via service name + `swarm: true` on the `docker.yaml` instance (dockerproxy with `SERVICES=1`).
6. **⚠️ Local services on Ybytu (same host as Homepage):** NEVER use the Tailscale IP (`100.115.253.109`) in `siteMonitor` for containers running in `network_mode: host` or lacking DNAT port forwarding. When Homepage ran in bridge mode, it could not reach the host's Tailscale IP (`EHOSTUNREACH` via iptables `icmp-host-prohibited`, throwing 500 errors). Monitor local ybytu containers via Docker Socket (`server: ybytu`, `container: <name>`), retaining the public/tailnet URL in `href` for browser navigation. **(Update 08/10/2026:** The bridge `EHOSTUNREACH` constraint was superseded: Homepage now runs in **`network_mode: host`** and internal probes reach both `127.0.0.1:9096` and `ybytu:9096` cleanly. Docker Socket monitoring remains the recommended default; MagicDNS `siteMonitor` references also function correctly.**)**
7. **⚠️ `siteMonitor` requires an `href` to render:** Homepage **silently drops** `siteMonitor` if an entry lacks an `href` (verified 08/10/2026 in rendered HTML — the `service-site-monitor` element only appears when `href` is present). Every entry requiring a status chip must provide a valid `href`; if the service lacks a dedicated UI, point `href` to the health endpoint itself (e.g. *Unbound* tile: `href` and `siteMonitor` both target `http://kavure:9097`).

> **08/10/2026 — `href` Corrections:** 6 service links for **ybytu** had `http://127.0.0.1:PORT`, opening on the **client machine** rather than ybytu. Migrated to `http://ybytu:PORT` (MagicDNS hostname). Impacted: AdGuard admin (`:3000`), Uptime Kuma (`:3002`), ChangeDetection (`:8082`), Ntfy (`:8083`), and WoL relays (`:9096`). Backup: `services.yaml.bak-20261008-href`.  
>  
> **08/10/2026 — MagicDNS Standard:** **All** remote `href` and `siteMonitor` entries migrated from raw Tailscale IPs to **MagicDNS hostnames** (`100.82.51.112`→`psicopompo`, `100.124.146.77`→`kavure`, `100.94.209.99`→`kuaray`, `100.115.253.109`→`ybytu`, `100.66.224.34`→`ybyra`). Verified: The container resolves all hostnames via Node DNS lookup. **Local services on ybytu maintain `127.0.0.1` in `siteMonitor`** (see Rule 6). Backup: `services.yaml.bak-20261008-nomes`.  
>  
> **08/10/2026 — Cleanup Pass:** Corrected 3 non-standard items: (1) **Crafty** `href` from FQDN to short MagicDNS name (`https://kavure:8444`); (2)+(3) Both `siteMonitor` entries for **wol-relay** updated to `http://ybytu:9096/health`. Final state: Zero hardcoded raw Tailscale IPs in `services.yaml`; FQDNs preserved strictly for public Funnels (`sumaenima.*` and `miracena.*`). Backup: `services.yaml.bak-20261008-magicdns`.  
>  
> **08/10/2026 — `minecraft-status` (HEAD Support):** Minecraft `siteMonitor` raised `<httpProxy> Error` because the native endpoint returned **HEAD responses with bodies** (violating RFC 7231 §4.3.2). Resolved in Rust source (`SUMAENIMA-HUB/provisioning/minecraft-status`): HEAD returns empty body. Validated with zero log errors. See [`minecraft-status.md`](minecraft-status.md).  
>  
> **08/10/2026 — Unbound Tile (Invalid Docker Chip → Mini Endpoint):** The tile used `server: kavure` + `container: unbound`, but unbound is **native systemd** — showing "not found". In accordance with conventions (**native service without HTTP → lightweight HTTP status endpoint + `siteMonitor`**), created **`unbound-status`** (`:9097`, Rust, in `SUMAENIMA-HUB/provisioning/unbound-status/`) with `siteMonitor: http://kavure:9097`. Backup: `services.yaml.bak-20261008-unbound-status`.

### Custom Icons (`config/icons/`)

| Icon | Origin |
|---|---|
| `sumaenima.svg` | Sumænimá branding logo (`logo-8.svg`) |
| `zomboid.png` | Spiffo mascot from Project Zomboid (`spiffo.png` from `fpsacha/zomboid-control-panel`) |
| `zombie.svg` | Panel visual asset (`zombie.svg` from same repository) |

## Maintenance

```bash
docker restart homepage
```

> **Applying Configuration Changes:** Homepage is **statically generated** — after modifying `services.yaml`/`settings.yaml`, regenerate the dashboard via the **refresh button** (bottom right corner) or:  
> ```bash
> curl http://127.0.0.1:3001/api/revalidate   # takes ~1 min; returns on completion
> ```  
> No container rebuild required. `docker restart homepage` also refreshes on initial request.

> **⚠️ Healthcheck:** Upstream container image executes `wget 127.0.0.1:3000` (IPv4) but Next.js 16 binds to IPv6 — causing default healthchecks to fail and triggering autoheal loops. Resolved in `compose.yml` with custom healthcheck using `[::1]`.

Container logs are managed by Docker and Watchtower handles automatic image updates.
