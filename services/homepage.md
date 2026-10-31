---
tags: [homelab, service, homepage, monitoring]
pending: [HB-069]
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
>  
> ⚠️ **Troubleshooting Tailnet Reachability (`No route to host`):** Se o Homepage responder localmente (`curl http://127.0.0.1:3001` → 200) mas falhar remotamente via Tailscale com `No route to host`, inspecione imediatamente a tabela `nat` do host (`sudo iptables -t nat -S DOCKER`). Regras zumbis de DNAT residuais da antiga configuração bridge sequestram pacotes da porta 3001 antes do listener de host. Procedimento de expurgo e persistência: [`../guides/homelab-traps-2026-10.md`](../guides/homelab-traps-2026-10.md#11-a-zombie-dnat-rule-steals-a-host-port-that-a-host-networked-container-is-listening-on).


## Configuration

Homepage utilizes YAML files located in `/app/config/` (host: `/home/ubuntu/homelab/homepage/config/`).

> ⚠️ **Governance gap (13/10/2026) — the config has no repository copy.** `services.yaml`,
> `docker.yaml`, `settings.yaml`, `bookmarks.yaml` and `widgets.yaml` live **only on ybytu** under
> `/home/ubuntu/homelab/homepage/`: there is **no** copy in `MNEMOCINE-OPS`, `sumaenimahub` or
> `/mnt/NVME_PCI/homelab`, and the compose is **not** mirrored by `config-backup` to the NAS. Every
> backup is the local `services.yaml.bak-YYYYMMDD-<slug>` the operator takes before editing — the vault
> then documents the change, but the machine-readable source is single-homed. The house rule
> (`mnemocine/AGENTS.md` *Config-as-Code*) expects a versioned source; a change here is applied on the
> host and then **documented** in this note. Mitigate it as tracked in **[HB-069](../backlog.md)**.

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

- **Current state:** 60 services with Docker chips, 14 with `siteMonitor`, **0 with duplicate chips** (13/10/2026, when the **Ybytu Syncthing** `siteMonitor` was added — the Project Zomboid Docker chip was removed and replaced by the `zomboid-health` `siteMonitor` — see changelog).
- Designated for `siteMonitor` (due to lacking a stable, persistent container name): Sumænimá Portal, Sumænimá API/Backup/Umami (**Swarm** services — container names change per task recreation), Minecraft, Valheim and Project Zomboid (native game protocols), Punktfunk/Syncthing-Psicopompo (**bare-metal systemd**), **hl-infer** (native systemd, 12/10), and **Wake-on-LAN** relays (`Power on Kavure/Psicopompo`).

> The Docker status chip reflects the container `healthcheck` — present on **all** production containers since 07/10 (see [`guides/docker-healthchecks.md`](../guides/docker-healthchecks.md)). This is the enforced default: it displays true internal operational health rather than mere port responsiveness.

> ⚠️ **Validation of `services.yaml` (07/10/2026):** PyYAML **does not** flag **duplicate mapping keys** (silently preserving the last occurrence) — a standard `yaml.safe_load` passed while Homepage crashed with `YAMLException: duplicated mapping key`. **Always** validate with a strict duplicate key checker (or `yamllint`) before recreating the container.

### Tile Descriptions (Convention — 13/10/2026)

Every tile carries a **short, consistent** `description` — long text is truncated on the tile, so it adds
noise without adding information. The rule:

> **`description: <What it is> · <Host>`** — one short functional phrase, then the node it runs on.
> **Sentence case**, ASCII, **no parentheticals and no "how"** (`Docker` / `native (systemd)` / `Swarm`).
> Target length **≤ ~40 chars**. Ports, container names and the deployment mechanism live in the
> per-service docs under `mnemocine/services/`, **not** on the tile.

- **Applied (13/10/2026):** all **73** tiles normalized; **69** descriptions rewritten. The 4 already
  compliant were `PaperMC · Kavure`, `Dashboards · Kavure`, `Headless CMS · Kuaray` and `Frontend SSR · Kuaray`.
  The longest description dropped from **82 → 34** chars (`GPU inference gateway · Psicopompo`).
- The "how" moved off the tile (kept in the per-service docs), e.g.
  `hl-infer`: `GPU inference gateway (VRAM leases) · Psicopompo · native (systemd)` → `GPU inference gateway · Psicopompo`;
  `ComfyUI`: `Diffusion image generation — on demand (GPU lease) · Psicopompo` → `Image generation · Psicopompo`.
- The former `Docker · <host>` placeholder on runtime-infra tiles was replaced by the tile's actual
  function: `Auto-update` (Watchtower), `Auto-heal` (Autoheal), `Host metrics` (Node Exporter),
  `Log shipping` (Promtail), `System monitor` (Glances).

### Docker Instances (`docker.yaml`)

| Instance | Endpoint | Server |
|---|---|---|
| `ybytu` | `/var/run/docker.sock` | local |
| `psicopompo` | `100.82.51.112:2375` | dockerproxy |
| `kuaray` | `100.94.209.99:2375` | dockerproxy |
| `kavure` | `100.124.146.77:2375` | dockerproxy |
| `ybyra` | `100.66.224.34:2375` | dockerproxy |

Each service in `services.yaml` with `server:` + `container:` displays live status automatically. Containers in `Exited` states (e.g. on kuaray) appear offline without manual intervention.

### Groups in `services.yaml` (13/10/2026)

Active ordering (cloud infrastructure placed last); **7 groups / 74 tiles**:
1. **Psicopompo (Workstation & NAS)** — Power on Kavure (WoL), Syncthing, Punktfunk, **hl-infer (12/10)**, **ComfyUI (12/10)**, Glances + runtime infra (Watchtower, Autoheal, Node Exporter, Promtail)
2. **Sumænimá (ΣÆ Produção)** — Portal, API, Backup, Umami Analytics, **StênioREC (13/10)**, Docker Registry
3. **Kavure (Serviços & Games)** — Power on Psicopompo (WoL), Project Zomboid, Zomboid Control Panel, Crafty Controller, Minecraft Server, Valheim Server, AioStreams, Comet, n8n Homelab, Grafana, Prometheus, **Loki (12/10)**, **Alertmanager (12/10)**, SearXNG, Pi-hole, Unbound, Home Assistant, Navidrome, Calibre Web + runtime infra
4. **Miracena (Kuaray)** — Portal Miracena, WordPress, **Plataforma Miracena (31/10; link to the tailnet HTTPS address, siteMonitor on `/api/method/ping`, brand icon `/icons/miracena.svg`; Directus tile removed)**, Nuxt 3, n8n, NPM Admin, **StênioSentinel (30/10)**
5. **Kuaray (Mídia & Staging)** — Syncthing, Transmission, Prowlarr, Lidarr, slskd, FlareSolverr, Soularr, Vert + runtime infra
6. **Ybytu (Cloud Borda)** — AdGuard Home, Glances, Uptime Kuma, Changedetection, Ntfy + runtime infra
7. **Ybyra (Cloud Borda)** — Glances + runtime infra

> **13/10/2026 — `StênioREC` moved back to the Sumænimá column:** the tile had been moved to **Psicopompo**
> on 12/10, but StênioREC is a **Sumænimá product GPU worker**, so it belongs under **Sumænimá (ΣÆ Produção)**.
> Its `server: psicopompo` + `container: steniorec` chip is **truthful and unchanged** (verified live: the
> standalone `steniorec` container, image `sumaenima-server:cuda`, up/healthy on psicopompo). Only the column moved.

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
> **Applied on the host (13/10/2026):** the tile now reads `description: REST/WS API · Kavure`
> (normalized in the tile-standardization pass; see the convention above). The `href`/`siteMonitor`
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

> ⚠️ **Correction to the entry above (13/10/2026, same day):** the claim that the PZ dedicated server runs as a
> "native child process of `zomboid-panel`" was **wrong**. Evidence: `zomboid-start` is `docker compose up -d`
> (it starts the **`pz-server` container**), `zomboid-stop` is `docker compose down` (it removes it), and the
> `zomboid-stop` log shows `Container pz-server Stopping/Removed` with the pre-stop RCON `save` answered at
> **`127.0.0.1:27015`** — a host-published port that only the container owns. The `zomboid-panel` `isRemote:false`
> flag is a **panel-side artifact**: the panel has no docker socket, does not start the container, and only
> **RCONs** to `pz-server` over the shared `zomboid_default` network. The `pz-server` container exists **whenever
> the game runs**; it was absent on 13/10 only because the game had been `docker compose down`'d on **26/08**.
> See [`zomboid/project-zomboid.md`](zomboid/project-zomboid.md).

> **13/10/2026 — Tile descriptions standardized + `StênioREC` back to the Sumænimá column + `Project Zomboid` gets a real chip (`zomboid-health`):**
> **1. `StênioREC` group corrected** — moved back to the **Sumænimá (ΣÆ Produção)** column (verified live on
> psicopompo: standalone container `steniorec`, `sumaenima-server:cuda`, up/healthy; `server`/`container` chip
> target truthful and unchanged — only the column moved).
> **2. All 73 tile descriptions normalized** to `<What it is> · <Host>` (see the convention above; 69 rewritten,
> longest 82 → 34 chars).
> **3. `Project Zomboid` now has a truthful chip.** A native Rust **`zomboid-health`** endpoint was deployed on
> **kavure `:9098`** (mirroring `minecraft-status`: TCP probe of the game's RCON `27015` → `200 up` / `503 down`,
> HEAD without body) and the tile uses **`siteMonitor: http://kavure:9098`** (no Docker chip). The game has been
> **stopped since 26/08/2026**, so the chip correctly reports **down** today — the whole point is that it cannot
> lie. Source: `MNEMOCINE-OPS/provisioning/zomboid-health/` + `provisioning/systemd/hl-zomboid-health.service`.
> Backup: `services.yaml.bak-20261013-std`; strict duplicate-key check + Homepage `js-yaml` pass; reloaded via
> `GET /api/revalidate` (`{"revalidated":true}`).


> **09/10/2026 — Tile descriptions standardized to English (Tier A):** all `description:` values translated from PT-BR to EN (e.g. `Automação Homelab` → `Homelab Automation`, `Automação & Workflows` → `Automation & Workflows`, `Monitoramento Uptime` → `Uptime Monitoring`, `Servidor Push` → `Push Server`). Backup: `services.yaml.bak-20261009-en`; reloaded via `GET /api/revalidate`.

> **13/10/2026 — `Syncthing · Ybytu` tile added (keeps the edge honest):** ybytu was **re-commissioned** as a Syncthing peer for one purpose — an off-site (datacenter) copy of the KeePass DB, so losing `psicopompo` does not lose the secret store — but it receives **only** `AlgoAqui.kdbx` (`.stignore` = `!/AlgoAqui.kdbx` + `*`; the unencrypted identity documents in that folder never reach the host; see [`syncthing.md`](syncthing.md)). Added to the **Ybytu (Cloud Borda)** group: `icon: syncthing`, `description: File sync · Ybytu`, `siteMonitor: http://127.0.0.1:8384` — loopback on purpose, because the container runs in `network_mode: host` and the probe reaches the local GUI (verified `200` from inside the container). **No `href`**, per Rule 7 as corrected above (the chip renders without one in the current image). **Tiles 73 → 74**, `siteMonitor` 13 → 14. Backup: `services.yaml.bak-20261013-syncthing-ybytu`; strict duplicate-key + Homepage `js-yaml` pass; verified in the served HTML (icon, description, `service-site-monitor` element) and via `GET /api/services`. Deployment notes recorded: **the `services.yaml` and the compose live only on ybytu** (`/home/ubuntu/homelab/homepage/`) — **not** in a repo and **not** mirrored to the NAS, which is a Config-as-Code gap (see the governance note below).

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
   - **⚠️ The Docker chip must point at the container that actually runs the game.** A chip on the *manager* is a false-uptime signal (it stays up while the game is down). The **Project Zomboid** tile's `pz-server` chip was **removed (13/10)** in favour of a **`siteMonitor`**: the game runs in the `pz-server` container, which is **removed** (`docker compose down`) whenever the game is stopped, so a chip would read "not found" rather than a red "down". The **`zomboid-health`** endpoint (`kavure:9098`, RCON `27015` probe) reports the true state — see changelog and [`zomboid/project-zomboid.md`](zomboid/project-zomboid.md).
3. **⚠️ Avoid `customapi` widget** — Renders an oversized card panel rather than a compact status chip and fails easily on API schema changes. Only use when no standard alternative exists and visually validated.
4. **Environment variables**: For credentials/tokens in gethomepage, define them in the config directory `.env` with the **`HOMEPAGE_VAR_` prefix** (e.g. `HOMEPAGE_VAR_CRAFTY_API_KEY=...`) and reference via `{{HOMEPAGE_VAR_CRAFTY_API_KEY}}`. Without the prefix, variables remain unset.
5. **Swarm services** (sae-core/sae-edge): Badge mapped via service name + `swarm: true` on the `docker.yaml` instance (dockerproxy with `SERVICES=1`).
6. **⚠️ Local services on Ybytu (same host as Homepage):** NEVER use the Tailscale IP (`100.115.253.109`) in `siteMonitor` for containers running in `network_mode: host` or lacking DNAT port forwarding. When Homepage ran in bridge mode, it could not reach the host's Tailscale IP (`EHOSTUNREACH` via iptables `icmp-host-prohibited`, throwing 500 errors). Monitor local ybytu containers via Docker Socket (`server: ybytu`, `container: <name>`), retaining the public/tailnet URL in `href` for browser navigation. **(Update 08/10/2026:** The bridge `EHOSTUNREACH` constraint was superseded: Homepage now runs in **`network_mode: host`** and internal probes reach both `127.0.0.1:9096` and `ybytu:9096` cleanly. Docker Socket monitoring remains the recommended default; MagicDNS `siteMonitor` references also function correctly.**)**
7. **⚠️ `siteMonitor` and `href` — version-dependent, do not trust the old "silently dropped" rule.** On 08/10/2026 (Homepage v?) the chip was dropped without an `href`. **Re-verified 13/10/2026 on the running image `ghcr.io/gethomepage/homepage:latest` (Next.js 16.3.8, on ybytu): the `service-site-monitor` element DOES render with `siteMonitor` alone and no `href`** — proven in the served HTML for the new **Syncthing · Ybytu** tile. So an entry that lacks a UI may legitimately carry a `siteMonitor` with no `href`. Keep adding a valid `href` whenever one exists (browser navigation); do **not** invent a dead `href` just to make a chip appear.

> **08/10/2026 — `href` Corrections:** 6 service links for **ybytu** had `http://127.0.0.1:PORT`, opening on the **client machine** rather than ybytu. Migrated to `http://ybytu:PORT` (MagicDNS hostname). Impacted: AdGuard admin (`:3000`), Uptime Kuma (`:3002`), ChangeDetection (`:8082`), Ntfy (`:8083`), and WoL relays (`:9096`). Backup: `services.yaml.bak-20261008-href`.  
>  
> **08/10/2026 — MagicDNS Standard:** **All** remote `href` and `siteMonitor` entries migrated from raw Tailscale IPs to **MagicDNS hostnames** (`100.82.51.112`→`psicopompo`, `100.124.146.77`→`kavure`, `100.94.209.99`→`kuaray`, `100.115.253.109`→`ybytu`, `100.66.224.34`→`ybyra`). Verified: The container resolves all hostnames via Node DNS lookup. **Local services on ybytu maintain `127.0.0.1` in `siteMonitor`** (see Rule 6). Backup: `services.yaml.bak-20261008-nomes`.  
>  
> **08/10/2026 — Cleanup Pass:** Corrected 3 non-standard items: (1) **Crafty** `href` from FQDN to short MagicDNS name (`https://kavure:8444`); (2)+(3) Both `siteMonitor` entries for **wol-relay** updated to `http://ybytu:9096/health`. Final state: Zero hardcoded raw Tailscale IPs in `services.yaml`; FQDNs preserved strictly for public Funnels (`sumaenima.*` and `miracena.*`). Backup: `services.yaml.bak-20261008-magicdns`.  
>  
> **08/10/2026 — `minecraft-status` (HEAD Support):** Minecraft `siteMonitor` raised `<httpProxy> Error` because the native endpoint returned **HEAD responses with bodies** (violating RFC 7231 §4.3.2). Resolved in Rust source (`SUMAENIMA-HUB/provisioning/minecraft-status`): HEAD returns empty body. Validated with zero log errors. See [`minecraft-status.md`](minecraft-status.md).  
>  
> **08/10/2026 — Unbound Tile (Invalid Docker Chip → Mini Endpoint):** The tile used `server: kavure` + `container: unbound`, but unbound is **native systemd** — showing "not found". In accordance with conventions (**native service without HTTP → lightweight HTTP status endpoint + `siteMonitor`**), created **`unbound-status`** (`:9097`, Rust, in `SUMAENIMA-HUB/provisioning/unbound-status/`) with `siteMonitor: http://kavure:9097`. Backup: `services.yaml.bak-20261008-unbound-status`.
>  
> **30/10/2026 — StênioSentinel added to Miracena (Kuaray):** Added tile for **StênioSentinel** (`miracena-stenio`, `:9099`) with Docker badge (`server: kuaray` + `container: miracena-stenio`) and `href: http://kuaray:9099/health`. Icon `/icons/sumaenima.svg`. Monitored live via `dockerproxy` on Kuaray (`100.94.209.99:2375`). Backup: `services.yaml.bak-20261030-stenio`.

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

> **31/10/2026 — Miracena identity:** the group `Miracena (Kuaray)` carries the client's icon (`config/icons/miracena.svg`, set through `layout:` in `settings.yaml`, which now lists all seven groups in their existing order with `style: column`). New static icons are only served after `docker restart homepage`. Ybyra has no separate Homepage: it is the `Ybyra (Cloud Borda)` group of this instance.
