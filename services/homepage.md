---
tags: [homelab, service, homepage, monitoring]
pending: []
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

- **Current state:** 60 services with Docker chips, 12 with `siteMonitor`, **0 with duplicate chips** (13/10/2026; the Project Zomboid Docker chip was removed — see changelog).
- Designated for `siteMonitor` (due to lacking a stable, persistent container name): Sumænimá Portal, Sumænimá API/Backup/Umami (**Swarm** services — container names change per task recreation), Minecraft and Valheim (native game protocols), Punktfunk/Syncthing-Psicopompo (**bare-metal systemd**), **hl-infer** (native systemd, 12/10), **Project Zomboid** (native game protocol; **awaiting a `zomboid-health` endpoint** — 13/10), and **Wake-on-LAN** relays (`Power on Kavure/Psicopompo`).

> The Docker status chip reflects the container `healthcheck` — present on **all** production containers since 07/10 (see [`guides/docker-healthchecks.md`](../guides/docker-healthchecks.md)). This is the enforced default: it displays true internal operational health rather than mere port responsiveness.

> ⚠️ **Validation of `services.yaml` (07/10/2026):** PyYAML **does not** flag **duplicate mapping keys** (silently preserving the last occurrence) — a standard `yaml.safe_load` passed while Homepage crashed with `YAMLException: duplicated mapping key`. **Always** validate with a strict duplicate key checker (or `yamllint`) before recreating the container.

### Docker Instances (`docker.yaml`)

| Instance | Endpoint | Server |
|---|---|---|
| `ybytu` | `/var/run/docker.sock` | local |
| `psicopompo` | `100.82.51.112:2375` | dockerproxy |
| `kuaray` | `100.94.209.99:2375` | dockerproxy |
| `kavure` | `100.124.146.77:2375` | dockerproxy |
| `ybyra` | `100.66.224.34:2375` | dockerproxy |

Each service in `services.yaml` with `server:` + `container:` displays live status automatically. Containers in `Exited` states (e.g. on kuaray) appear offline without manual intervention.

### Groups in `services.yaml` (12/10/2026)

Active ordering (cloud infrastructure placed last); **7 groups / 73 tiles**:
1. **Psicopompo (Workstation & NAS)** — Power on Kavure (WoL), Syncthing, Punktfunk, **hl-infer (12/10)**, **StênioREC (12/10)**, **ComfyUI (12/10)**, Glances + runtime infra (Watchtower, Autoheal, Node Exporter, Promtail)
2. **Sumænimá (ΣÆ Produção)** — Portal, API, Backup, Umami Analytics, Docker Registry
3. **Kavure (Serviços & Games)** — Power on Psicopompo (WoL), Project Zomboid, Zomboid Control Panel, Crafty Controller, Minecraft Server, Valheim Server, AioStreams, Comet, n8n Homelab, Grafana, Prometheus, **Loki (12/10)**, **Alertmanager (12/10)**, SearXNG, Pi-hole, Unbound, Home Assistant, Navidrome, Calibre Web + runtime infra
4. **Miracena (Kuaray)** — Portal Miracena, WordPress, Directus, Nuxt 3, n8n, NPM Admin
5. **Kuaray (Mídia & Staging)** — Syncthing, Transmission, Prowlarr, Lidarr, slskd, FlareSolverr, Soularr, Vert + runtime infra
6. **Ybytu (Cloud Borda)** — AdGuard Home, Glances, Uptime Kuma, Changedetection, Ntfy + runtime infra
7. **Ybyra (Cloud Borda)** — Glances + runtime infra

> **12/10/2026 — Groups corrected against the live config:** the list above was stale (it documented **5 groups** and placed the Miracena stack — WordPress/Directus/NPM/n8n — under **Kavure**, and a non-existent `Sumænimá (Primary Edge)` tile under Ybyra). The config actually has **7 groups**: the Miracena stack has its own group (**Miracena (Kuaray)**) and Ybyra carries only Glances + runtime infra. See the changelog entry below for the GPU/observability additions.

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
> **Minecraft Server** `description` updated to **`Docker`** — Dominium server executes as a **Java child process inside the `crafty-controller` container** (bind mount `MINECRAFT SERVER` → `/crafty/servers/dominium`); not an isolated container or bare-metal binary. Only the `hl-minecraft-status.service` probe daemon (systemd, `:9095`) runs natively on the host.  
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

> **12/10/2026 — GPU stack + observability tiles (audit pass):** **`hl-infer`** (native systemd, `:9095`; `siteMonitor` + `href` → `http://psicopompo:9095/v1/health`) and **`ComfyUI`** (Docker chip `comfyui`, description "on demand (GPU lease)") added to the **Psicopompo** group; **`StênioREC`** moved from the Sumænimá group to **Psicopompo** (Docker chip retained — it is the `steniorec` container with a healthy healthcheck, so a `siteMonitor` was **rejected** per the status-chip convention); **`Loki`** (`monitoring-loki`, `:3100`) and **`Alertmanager`** (`monitoring-alertmanager`, `:9093`) added to the **Kavure** group (running and in `ports.md` but absent from the dashboard). Audit also flagged, **not changed**: **`Project Zomboid` tile points at a non-existent container `pz-server`** (the PZ dedicated server runs as a child process of `zomboid-panel` — no docker socket mount), **`Minecraft Server` `description`** drifted from the documented `Docker`, and `ports.md` §2.2 still listed the Miracena stack under **kavure** though it runs on **kuaray** (corrected). Backup: `services.yaml.bak-20261012-gpu-tiles`; strict duplicate-key check + Homepage `js-yaml` pass; reloaded via `GET /api/revalidate` (`{"revalidated":true}`).

> **13/10/2026 — "Sumænimá API" tile description corrected (doc-side):** the live tile still reads
> `description: Fastify Core Swarm · Kavure`, but the API is **not Fastify** — `sae-core_api` is a
> **Rust Axum** service (`sumaenima-server:cpu`, overlay-only on `sae-net:9090`). Verified against
> [`services/steniobot.md`](steniobot.md) (`Rust Axum 0.8 backend`) and the deployed image.
> The description in `homepage/config/services.yaml` on ybytu must be changed to
> `Rust Axum Core Swarm · Kavure` at the next config edit (no host write was made here — this
> vault is the record, the host is read-only to the doc pass). The `href`/`siteMonitor`
> (`https://sumaenima.chimaera-heptatonic.ts.net/api/health`) are correct and unchanged.

> **13/10/2026 — `Project Zomboid` tile: invalid Docker chip removed (HB-038):** The tile carried
> `server: kavure` + `container: pz-server`, but **no `pz-server` container exists** (Docker API →
> 404), so the chip rendered **"not found"**. Confirmed live on kavure: `zomboid-panel` is the only
> Zomboid container (running/healthy), `docker inspect pz-server` → *no such object*, and the served
> HTML carries no chip for `pz-server` because Homepage 2.5 hydrates Docker status client-side via
> `/api/docker/statuses?server=kavure` — the container is absent from that map, and the UI falls back
> to `{status:"not found"}`. The PZ dedicated server runs as a **native child process of
> `zomboid-panel`** (the panel's active server `VaiMorreSim` has `isRemote:false` → provider
> `native`; the panel has **no docker socket mount**), and the game is currently **down** (no UDP
> `16261/16262` listener; the server has been stopped since **2026-08-26** and `hl-zomboid-restart.timer`
> is gone — only `hl-zomboid-backup.timer` remains). Per the status-chip convention, a game server with
> a custom binary protocol gets a **`minecraft-status`-style HTTP probe + `siteMonitor`** — but **no
> Zomboid status endpoint exists yet** (`zomboid-panel`'s API is auth-gated: `/api/servers/status` →
> `401`; `/api/health` reflects only the panel, and the panel's own healthcheck is `wget :3001/` →
> panel UI). A chip on `zomboid-panel` was **rejected** (the manager stays up while the game is down →
> false uptime). **Applied:** the misleading `server`/`container` keys were **removed** from the tile
> (now `icon` + `href` + `description` only). **Proposed, not yet deployed (kavure is read-only for
> this pass):** a native **`zomboid-health`** endpoint (Rust, mirroring `minecraft-status`: RCON TCP
> `27015` probe → `200` up / `503` down; candidate port `:9098`) + `siteMonitor: http://kavure:9098`.
> Backup: `services.yaml.bak-20261013-zomboid`; strict duplicate-key check + Homepage `js-yaml` pass;
> reloaded via `GET /api/revalidate` (`{"revalidated":true}`).


> **09/10/2026 — Tile descriptions standardized to English (Tier A):** all `description:` values translated from PT-BR to EN (e.g. `Automação Homelab` → `Homelab Automation`, `Automação & Workflows` → `Automation & Workflows`, `Monitoramento Uptime` → `Uptime Monitoring`, `Servidor Push` → `Push Server`). Backup: `services.yaml.bak-20261009-en`; reloaded via `GET /api/revalidate`.

### Status Standard (CONVENTION — Enforced for all additions)

| Service Type | Status Source | Config in `services.yaml` |
|---|---|---|
| **HTTP Service** | Chip `siteMonitor` — latency in **ms** | `siteMonitor: <url>` |
| **Docker service without HTTP** (games, MQTT) | Docker badge (running/stopped dot) | `server:` + `container:` |
| **Native service** (systemd daemon without container) | Chip `siteMonitor` | `siteMonitor: <url>` |

**Rules:**
1. **HTTP → `siteMonitor`** (latency chip in ms). This is the preferred default.
2. **Non-HTTP → Docker badge** (`server` + `container`). E.g.: Valheim Server (`valheim-server`).
   - **Game servers with custom binary protocols (e.g. Minecraft)** → To maintain a **compact chip + true in-game state**, deploy a **lightweight HTTP status endpoint** on the host and configure `siteMonitor: <url>`. On kavure: `minecraft-status` service (port `9095`, Minecraft SLP probe on `25565` → 200 up / 503 down). Avoid the `crafty-controller` badge (the manager stays up even when the server crashes) and avoid the `minecraft` widget (renders an oversized 3-field card outside UI conventions).
   - **⚠️ The Docker chip must point at the container that actually runs the game.** A chip on the *manager* is a false-uptime signal (it stays up while the game is down). The **Project Zomboid** tile's `pz-server` chip was **removed (13/10)** — that container does not exist (the game runs as a native child of `zomboid-panel`); the tile awaits a `zomboid-health` endpoint + `siteMonitor` (see changelog).
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
