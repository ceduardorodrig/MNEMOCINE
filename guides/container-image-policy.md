---
tags: [homelab, docker, compose, config, tutorial]
---

# Canonical Container Image and Versioning Policy (Mnemocine)

> **Standard Established on 29/10/2026:** Defines tag governance, the update cycle and the Docker image pinning rules on every node of the fleet (`psicopompo`, `kavure`, `ybytu`, `ybyra`, `kuaray`).

---

## 1. Engineering Philosophy: The 4-Layer Hybrid Policy

In high-reliability professional infrastructures (SRE and CNCF standards and corporate production environments), Docker image management is guided by two fundamental principles:

1. **The "Everything `:latest`" Anti-pattern (*Rolling Drift Trap*):**
   - `:latest` images in databases or stateful applications introduce silent breakage in the middle of the night (automatic schema migrations, table corruption, broken legacy plugins).
   - It invalidates reproducibility: it prevents deterministic disaster recovery and vulnerability (CVE) auditing.
2. **The "Total and Unrealistic Freeze" Anti-pattern (*Dependency Rot*):**
   - Pinning strict patches on everything without exception (e.g. `glances:4.3.0.1`, `steamcmd:2024-01`) makes the infrastructure rot. Utilities miss security patches, and game wrapper containers (SteamCMD) break as soon as Valve changes Steam API protocols.

The **4-Layer Hybrid Policy** balances maximum safety where there is data and convenience/agility where the service is ephemeral or driven by external APIs.

```
┌────────────────────────────────────────────────────────────────────────┐
│ CAMADA 1: Pinagem Estrita SemVer (Major.Minor)                         │
│ Bancos de Dados, CMS, Auth, Gateways de Borda (NUNCA auto-update)       │
├────────────────────────────────────────────────────────────────────────┤
│ CAMADA 2: Game Servers & Wrappers de Jogo                              │
│ Wrapper estável / latest + Engine atualizada via SteamCMD no boot      │
├────────────────────────────────────────────────────────────────────────┤
│ CAMADA 3: SemVer Flutuante por Major (:1, :v2, :YYYY.MM)               │
│ Dashboards, automações e indexadores (recebe patches, bloqueia breaks) │
├────────────────────────────────────────────────────────────────────────┤
│ CAMADA 4: Utilitários Stateless de Infraestrutura                      │
│ Telemetria e manutenção contínua (:latest monitorado por Watchtower)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Four Layers of the Homelab

### Layer 1: Strict Pinning (SemVer Patch/Minor) — Critical & Stateful
- **Criterion:** Services that persist relational schemas, customer data, edge TLS certificates or sensitive configuration files.
- **Versioning Rule:** Always pin `major.minor` or `major.minor.patch` (e.g. `mariadb:11`, `postgres:16-alpine`, `wordpress:6.6.2-php8.3-apache`).
- **Watchtower Behavior:** **MANDATORILY DISABLED** via the label `com.centurylinklabs.watchtower.enable: "false"`.
- **Update Procedure:** Exclusively manual, preceded by a full backup (`config-backup`, SQL dump) and a reading of the official changelog.

### Layer 2: Game Servers (SteamCMD / Runtimes)
- **Criterion:** Dedicated game servers where the Docker container acts only as a Linux/GLIBC/Wine environment and Steam download orchestrator.
- **Versioning Rule:**
  - **Project Zomboid:** The container (`zomboid-panel:latest` / `danixu86/project-zomboid-dedicated-server:latest`) MUST stay `:latest` to keep compatibility with Valve libraries. The game server executable is updated via SteamCMD at startup (`app_update 380870 validate`).
  - **Valheim:** Wrapper pinned to the major (`mbround18/valheim:3`) for BepInEx script stability, with a daily game update at 03:00 via the internal SteamCMD.
  - **Minecraft (Dominium / Crafty 4):** The Crafty panel runs on `:latest` or the stable `:4` tag. The game server version (Java Fabric 1.21.1) is 100% static and controlled by the mod ecosystem and `.jar` files in `/srv/data/minecraft/`.

### Layer 3: Floating SemVer by Major (`:1`, `:v2`, `:YYYY.MM`)
- **Criterion:** Auxiliary applications, dashboards, media indexers and automations.
- **Versioning Rule:** Use the most recent Major Version tag (e.g. `uptime-kuma:1`, `adguardhome:v0.107`, `binwiederhier/ntfy:v2`, `grafana/grafana:11`).
- **Benefit:** The container receives bug fixes and security patches automatically, but is shielded from major architecture overhauls that break backward compatibility.
- **`:latest` exceptions in this layer:**
  - **SearXNG (`searxng/searxng:latest`):** It is a rolling-release project that depends on constant adaptations to search engine scrapers. It runs isolated with its own Valkey.
  - **Media Addons and Scrapers (`aiostreams:latest`, `flaresolverr:latest`, `comet:latest`):** Must run the most recent version to keep up with external provider API changes.

### Layer 4: Stateless Infrastructure Utilities
- **Criterion:** Monitoring daemons, socket proxies and cleanup tools that keep no state on disk.
- **Versioning Rule:** `:latest` with continuous updates via Watchtower.
- **Services:** `containrrr/watchtower`, `willfarrell/autoheal`, `nicolargo/glances`, `tecnativa/docker-socket-proxy`.

---

## 3. Full Fleet Mapping (5 Nodes)

### 3.1. Node `psicopompo` (Workstation / AI / Registry)

| Service / Container | Current Image | Layer | Recommended Policy | Watchtower |
|---|---|---|---|---|
| `registry` | `registry:3` | Layer 1 | `registry:3` (Pinned) | Blocked |
| `steniorec` | `sumaenima-server:cuda` | Internal | Local build / CI | Manual |
| `glances` | `nicolargo/glances:ubuntu-latest-full` | Layer 4 | `:ubuntu-latest-full` | Enabled |
| `watchtower` | `containrrr/watchtower:latest` | Layer 4 | `:latest` | Self-managed |
| `autoheal` | `willfarrell/autoheal:latest` | Layer 4 | `:latest` | Enabled |
| `dockerproxy` | `tecnativa/docker-socket-proxy:latest` | Layer 4 | `:latest` | Enabled |
| `node-exporter` | `prom/node-exporter:v1.9.0` | Layer 4 | `prom/node-exporter:v1` | Enabled |
| `promtail` | `grafana/promtail:3.2.0` | Layer 4 | `grafana/promtail:3` | Enabled |

### 3.2. Node `kavure` (Dedicated Server / Swarm Manager)

| Service / Container | Current Image | Layer | Recommended Policy | Watchtower |
|---|---|---|---|---|
| `sae-core_db` | `pgvector/pgvector:pg16` | Layer 1 | `pgvector/pgvector:pg16` | Blocked |
| `sae-core_umami-db` | `postgres:15-alpine` | Layer 1 | `postgres:15-alpine` | Blocked |
| `sae-core_valkey` | `valkey/valkey:8-alpine` | Layer 1 | `valkey/valkey:8-alpine` | Blocked |
| `n8n-postgres` | `postgres:16-alpine` | Layer 1 | `postgres:16-alpine` | Blocked |
| `searxng-valkey` | `valkey/valkey:9-alpine` | Layer 1 | `valkey/valkey:9-alpine` | Blocked |
| `n8n` | `docker.n8n.io/n8nio/n8n:stable` | Layer 3 | `:stable` or `:1` | Blocked (manual) |
| `homeassistant` | `homeassistant/home-assistant:latest` | Layer 3 | `:2024.10` (monthly SemVer) | Blocked |
| `pihole` | `pihole/pihole:latest` | Layer 3 | `pihole/pihole:2024` or `:latest` | Enabled |
| `calibre` | `crocodilestick/calibre-web-automated:latest`| Layer 3 | `:latest` | Enabled |
| `navidrome` | `deluan/navidrome:latest` | Layer 3 | `:latest` (or `:0.53`) | Enabled |
| `searxng-core` | `searxng/searxng:latest` | Layer 3 | `:latest` | Enabled |
| `aiostreams` | `viren070/aiostreams:latest` | Layer 3 | `:latest` | Enabled |
| `comet` | `ghcr.io/g0ldyy/comet:latest` | Layer 3 | `:latest` | Enabled |
| `valheim-server` | `mbround18/valheim:3` | Layer 2 | `mbround18/valheim:3` (SteamCMD) | Blocked |
| `zomboid-panel` | `ghcr.io/fpsacha/zomboid-panel:latest` | Layer 2 | `:latest` (SteamCMD) | Blocked |
| `crafty-controller` | `registry.gitlab.com/.../crafty-4:latest`| Layer 2 | `:latest` (static Java engine)| Blocked |
| `monitoring-prometheus` | `prom/prometheus:v2.55.1` | Layer 1 | `prom/prometheus:v2` | Blocked |
| `monitoring-grafana` | `grafana/grafana:11.3.0` | Layer 1 | `grafana/grafana:11` | Blocked |
| `monitoring-loki` | `grafana/loki:3.2.0` | Layer 1 | `grafana/loki:3` | Blocked |
| `monitoring-alertmanager` | `prom/alertmanager:v0.27.0` | Layer 1 | `prom/alertmanager:v0.27` | Blocked |

### 3.3. Node `kuaray` (Standby / Miracena / Media Stack)

| Service / Container | Current Image | Layer | Recommended Policy | Watchtower |
|---|---|---|---|---|
| `miracena-wordpress` | `wordpress:6.6.2-php8.3-apache` | Layer 1 | `wordpress:6.6.2-php8.3-apache` | Blocked |
| `miracena-mariadb` | `mariadb:11` | Layer 1 | `mariadb:11` | Blocked |
| `miracena-postgres` | `postgres:16-alpine` | Layer 1 | `postgres:16-alpine` | Blocked |

| `miracena-nginx-proxy-manager` | `jc21/nginx-proxy-manager:latest` | Layer 1 | `jc21/nginx-proxy-manager:2.11` | Blocked |
| `miracena-tunnel` | `tailscale/tailscale:latest` | Layer 4 | `:latest` | Deliberately disabled since 2026-10-29 (HB-099) |
| `prowlarr` | `lscr.io/linuxserver/prowlarr:latest` | Layer 3 | `:latest` | Enabled |
| `transmission` | `lscr.io/linuxserver/transmission:latest` | Layer 3 | `:latest` | Enabled |
| `lidarr` | `lscr.io/linuxserver/lidarr:latest` | Layer 3 | `:latest` | Enabled |
| `slskd` | `slskd/slskd:latest` | Layer 3 | `:latest` | Enabled |
| `soularr` | `mrusse08/soularr:latest` | Layer 3 | `:latest` | Enabled |
| `flaresolverr` | `ghcr.io/flaresolverr/flaresolverr:latest` | Layer 3 | `:latest` | Enabled |
| `syncthing` | `linuxserver/syncthing:1.29.7` | Layer 1 | `linuxserver/syncthing:1` | Blocked |

### 3.4. Node `ybytu` (Cloud Edge / DNS)

| Service / Container | Current Image | Layer | Recommended Policy | Watchtower |
|---|---|---|---|---|
| `adguardhome` | `adguard/adguardhome:latest` | Layer 3 | `adguard/adguardhome:v0.107` | Blocked (DNS core) |
| `uptime-kuma` | `louislam/uptime-kuma:latest` | Layer 3 | `louislam/uptime-kuma:1` | Enabled |
| `ntfy` | `binwiederhier/ntfy:latest` | Layer 3 | `binwiederhier/ntfy:v2` | Enabled |
| `homepage` | `ghcr.io/gethomepage/homepage:latest` | Layer 3 | `ghcr.io/gethomepage/homepage:v0` | Enabled |
| `changedetection` | `dgtlmoon/changedetection.io:latest` | Layer 3 | `:latest` | Enabled |

### 3.5. Node `ybyra` (Cloud Edge / Ingress)

| Service / Container | Current Image | Layer | Recommended Policy | Watchtower |
|---|---|---|---|---|
| `sae-edge_proxy` | `.../nginx-sumaenima:latest` | Layer 1 | Built from the SUMAENIMA-HUB repo | CI Deploy |
| `sae-edge_umami` | `.../sumaenima-umami:latest` | Layer 1 | Built from the SUMAENIMA-HUB repo | CI Deploy |
| `sae-edge_tunnel`| `tailscale/tailscale:latest` | Layer 4 | `:latest` | Enabled |

---

## 4. Operations Runbook: How to Update Safely

### 4.1. Updating Layer 1 Services (Databases, CMS, Auth)
1. **Change Audit:** Read the official release notes of the target version (check for breaking changes or irreversible migrations).
2. **Preventive Snapshot / Backup:**
   ```bash
   config-backup
   # Para bancos de dados (ex: MariaDB na Miracena):
   sudo miracena-backup
   ```
3. **Compose Edit:** Change the semantic tag in the compose file (e.g. `wordpress:6.6.2-php8.3-apache` → `wordpress:6.6.3-php8.3-apache`).
4. **Controlled Deploy:**
   ```bash
   docker compose pull <servico>
   docker compose up -d <servico>
   ```
5. **Health Check:** Follow the logs (`docker compose logs -f <servico>`) and check the status with `docker ps`.

### 4.2. Updating Game Servers (Layer 2)
- **Project Zomboid:**
  ```bash
  zomboid-restart # Executa RCON save prévio e reinicia; o SteamCMD atualiza a build 42
  ```
- **Valheim:**
  - The container's internal script checks for updates via SteamCMD every day at 03:00.
  - To force an immediate manual update: restart the container (`docker restart valheim-server`).
- **Minecraft:**
  - Mod/loader updates follow the Prism Launcher / Server parity runbook via `sync_mods.py` (see `mnemocine/services/crafty.md`).

### 4.3. How to Block Watchtower on Critical Services
To make sure Watchtower ignores stateful containers, declare the label explicitly in `docker-compose.yml`:

```yaml
services:
  meu-banco-ou-cms:
    image: postgres:16-alpine
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
```

---

## 5. Integration with StênioSentinel

The Rust governance engine (`governance/stenio/src/infra.rs`) proactively validates the image rules through the code **`SEC-COMPOSE-PINNED-IMAGE`**:

- Emits a **CRITICAL WARNING** if database or CMS engines (service names containing `wordpress`, `mariadb` or `postgres`) use `:latest` or floating tags without SemVer.
- Accepts `:latest` for telemetry utilities and game server wrappers recognized in the homelab taxonomy.
