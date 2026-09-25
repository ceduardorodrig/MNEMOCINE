---
tags: [homelab, network, docker, monitoring]
---

# Service Topology

Mapping of dependencies between homelab services.

## Psicopompo

> **State (07/08/2026):** `sumaenimahub` stack (StênioBOT, Umami) **migrated to kavure** — psicopompo is now **role=gpu** (vision/audio/ollama GPU workers via standalone `gpu.yml`, connected to kavure's Swarm overlay) + build-node. Portainer, Crafty, Glances, dockerproxy, watchtower, autoheal **active**.

### Docker Networks

```
sumaenima_sumaenima-net (overlay do Swarm do kavure)  — GPU workers
├── steniobot_vision ────→ valkey (kavure), api (kavure) via overlay
├── steniobot_audio ─────→ valkey (kavure), api (kavure) via overlay
└── steniobot_ollama ────→ porta 11434 (API no kavure alcança via overlay)

minecraftserver_default (172.19.0.0/16)
└── crafty-controller ───→ portas: 8443, 25565, 8123, 25575 (bind host)

rustdesk-server_default (172.20.0.0/16)  — PARADO
├── hbbs (signal server) ──→ porta 21115-21116
└── hbbr (relay server) ───→ porta 21117

glances_default (172.21.0.0/16)
└── glances ────────────→ porta 61208

bridge (172.17.0.0/16)
├── portainer ───────────→ porta 9000
└── autoheal
```

### Dependencies

```mermaid
graph LR
    subgraph psicopompo
        F[crafty] --> G[Docker Socket]
        H[portainer] --> G
        I[autoheal] --> G
        V[steniobot_vision] --> K[(valkey kavure)]
        A[steniobot_audio] --> K
        J[hbbs] <--> K2[hbbr]
    end

    subgraph externo
        L[Docker Socket]
    end
```

### Shared Volumes

| Volume | Mount | Service |
|---|---|---|
| `steniobot_valkey` | `/data` | steniobot_valkey |
| `umami_db` | `/var/lib/postgresql/data` | umami_db |
| `steniobot_db` | `/var/lib/postgresql/data` | steniobot_db |
| `crafty` | `/crafty/` | crafty-controller |

---

## Ybytu

### Docker Networks

```
bridge (172.17.0.0/16)
├── adguardhome ─────────→ portas: 53, 3000
├── glances ────────────→ porta 61208
├── watchtower ──────────→ dockerproxy (Docker API)
├── dockerproxy ─────────→ Docker Socket (protegido)
├── autoheal ───────────→ Docker Socket
├── uptime-kuma ────────→ porta 3002
├── changedetection ────→ porta 8082
└── ntfy ────────────────→ porta 8083

homepage_default (172.18.0.0/16)
└── homepage ───────────→ dockerproxy:DOCKER_HOST → porta 3001
```

### Dependencies

```mermaid
graph LR
    subgraph ybytu
        H[homepage] --> DP[dockerproxy:2375]
        DP --> DS[Docker Socket]
        W[watchtower] --> DP
        A[autoheal] --> DS
    end
```

---

## Ybyra

### Docker Networks

```
bridge (172.17.0.0/16)
├── watchtower ──────────→ Docker API
├── autoheal ───────────→ Docker Socket
├── glances ────────────→ porta 61208
├── filebrowser ────────→ porta 8334
└── syncthing ──────────→ porta 8384, 22000
```

### Native Services
- **nginx**: Port 80. Hosts the frontend SPA (Primary Edge) and acts as a reverse proxy for the API.

### Dependencies

```mermaid
graph LR
    subgraph ybyra
        W[watchtower] --> DS[Docker Socket]
        A[autoheal] --> DS
        N[proxy:80] -->|Proxy reverso via overlay| API[kavure:9090]
    end
```

---

## Kuaray

> **⚠️ DEPRECATED (28/08/2026):** node removed from the active topology. Services on kuaray no longer take part in any operational role; the reference below is historical.

> **State (10/08/2026):** arr-stack + infra run via **docker-compose** (`/home/kuaray/homelab/{serviço}/`, config-as-code). **HA, Pi-hole, Navidrome, Calibre migrated to kavure** (09/08). Watchtower re-enabled (09/08). `calibre-web` removed (library lost 08/08); **Kavita removed 10/08** (no longer used).

### Docker Networks

```
bridge (172.17.0.0/16)
├── prowlarr ───────────→ porta 9696
├── flaresolverr ───────→ porta 8191
├── lidarr ─────────────→ porta 8686 ✅ reativado 06/08
├── transmission ───────→ portas: 9091, 51413 ✅ reativado 06/08
├── soularr ────────────→ porta 8265 ✅ reativado 06/08
├── slskd ──────────────→ porta 5030 ✅ reativado 06/08
├── navidrome ──────────→ porta 4533 ✅ reativado 06/08
├── calibre-web ────────→ porta 8083 ⚠️ EXITED
├── vert ───────────────→ porta 3030
├── dockerproxy ────────→ porta 2375
├── watchtower ─────────→ dockerproxy
└── autoheal ───────────→ Docker Socket

host (rede do host)
├── pihole ─────────────→ porta 53 (migrado p/ kavure 09/08)
├── syncthing ──────────→ porta 22000

Serviços Nativos
└── nginx ──────────────→ porta 8085 (Borda Secundária SPA + proxy reverso)

big-bear-vert_default
└── vert (também na bridge)
```

### *arr Stack Dependencies

```mermaid
graph LR
    subgraph kuaray
        P[prowlarr] --> F[flaresolverr]
        P --> T[transmission]
        L[lidarr] --> P
        L --> T
        L --> S[soularr]
        S --> SK[slskd]
        N[navidrome] --> L

        W2[watchtower] --> DP[dockerproxy]
        DP --> DS[Docker Socket]
        NG[nginx:8085] -->|Proxy reverso| API[kavure:9090]
    end
```

### Detailed Dependencies

| Service | Depends on | Service / Resource |
|---|---|---|
| **lidarr** | → prowlarr | Torrent indexers |
| | → transmission | Downloader |
| | → soularr | Alternate downloader (Soulseek) |
| **prowlarr** | → flaresolverr | Cloudflare resolver |
| **soularr** | → slskd | Soulseek client |
| **navidrome** | → lidarr | Library organization |
| **watchtower** | → dockerproxy | Docker API |
| **homepage (ybytu)** | → dockerproxy (kuaray?) | Container status | |

## Kavure

> **State (16/08/2026):** **Project Zomboid active** + **Zomboid Control Panel** + **dockerproxy** + **`ops` infra** + **Sumænimá sae-core (Swarm manager)**. **Received from kuaray (09/08):** **Home Assistant** (`:10000` funnel), **Pi-hole** (`:53` tailscale, host network), **Navidrome** (`:4533`, music via NFS), **Calibre Web** (`:8083`, books via NFS). **AioStreams** (`:3000`) + **Comet** (`:8000`) migrated 09/08. **HA reconfigured 16/08** (Bluetooth caps + HACS). **Mosquitto removed from kuaray 16/08** (unused). Host on **America/Sao_Paulo**.

### Docker Networks

```
sumaenima_sumaenima-net (overlay — Swarm, manager = kavure)
├── sae-core_db ──────────→ PostgreSQL 16 (pgvector), /srv/data/sumaenimahub/volumes/
├── sae-core_valkey ──────→ cache/broker
├── sae-core_api ─────────→ FastAPI :9090 (publicada no host)
├── sae-core_umami-db ────→ PostgreSQL 15 (umami)
├── sae-core_backup ──────→ sentinel Borg (NFS → psicopompo /mnt/BACKUP/sumaenima-server-kavure/)
├── sae-core_asciline ────→ streaming ASCII :8766
└── sae-edge_* ───────────→ proxy/tunnel/umami (ybyra primary; kavure standby — label `edge_backup=true`; ~~datavis~~ removido 22/09/2026 — legado)

zomboid_default (172.18.0.0/16)
├── pz-server ───────────→ portas: 16261-16262/udp (game), 27015/tcp (RCON)
└── zomboid-panel ───────→ porta 3001 (painel; conecta RCON em `pz-server`)

dockerproxy_default (172.19.0.0/16)
└── dockerproxy ─────────→ porta 2375 (Docker Socket protegido; usado pelo homepage)

ops_default
├── autoheal ────────────→ (monitora containers unhealthy via Docker API)
├── watchtower ──────────→ (auto-update de imagens, schedule 03:00 BRT, cleanup)
└── glances ─────────────→ porta 61208
```

### Dependencies

```mermaid
graph LR
    subgraph kavure
        P[zomboid-panel] -->|RCON| Z[pz-server]
        Z --> V[(/srv/data/zomboid/data)]
        DP[dockerproxy:2375] --> DS[Docker Socket]
        API[sae-core_api] --> DB[sae-core_db]
        API --> VK[sae-core_valkey]
        BAK[sae-core_backup] --> DB
        BAK -->|NFS| NFS[(psicopompo /mnt/BACKUP)]
    end
```

## Cross-Server Dependencies

| Service | Server | Depends on | Server |
|---|---|---|---|
| Syncthing | psicopompo | ↔ Syncthing | kuaray |
| Syncthing | ybyra | ↔ Syncthing | psicopompo |
| Homepage (dashboard) | ybytu | → dockerproxy | psicopompo (via Tailnet) |
| Homepage (dashboard) | ybytu | → dockerproxy | kuaray (via Tailnet) |
| Homepage (dashboard) | ybytu | → dockerproxy | kavure (via Tailnet) |
| Sumænimá (SPA Frontend) | ybyra (primary) / kavure (standby) | → Sumænimá Backend API | **kavure** (port 9090, via Swarm overlay) |
| Sumænimá GPU workers | psicopompo | → valkey/api/ollama | kavure (via overlay `sumaenima_sumaenima-net`) |

## Auto-Start & Health

### Autoheal (4 servers)
| Server | Container | Config | Status |
|---|---|---|---|
| psicopompo | autoheal | Monitors everything, 5s interval | ✅ healthy |
| ybytu | autoheal | Monitors everything, 5s interval | ✅ healthy |
| ybyra | autoheal | Monitors everything, 5s interval | ✅ healthy |
| kuaray | autoheal-autoheal-1 | Monitors everything, 5s interval | ✅ healthy |
| kavure | autoheal | Monitors everything (`AUTOHEAL_CONTAINER_LABEL=all`), 5s interval | ✅ healthy |

### Watchtower
| Server | Container | Config | Status |
|---|---|---|---|
| psicopompo | watchtower | ✅ Active, cleanup=true, API 1.40, polling 24h | ✅ healthy |
| ybytu | watchtower | ✅ Active, no auto-cleanup | ✅ healthy |
| ybyra | watchtower | ✅ Active | ✅ healthy |
| kuaray | watchtower | ✅ Active, cleanup=true, polling 24h | ✅ healthy |
| kavure | watchtower | ✅ Active, cleanup=true, **schedule 03:00 (BRT)**, stop-timeout 30s | ✅ healthy |

### Restart Policies
| Server | Policies |
|---|---|
| psicopompo | All `unless-stopped` or `always` |
| ybytu | All `unless-stopped` or `always` |
| ybyra | All `unless-stopped` |
| kuaray | All `unless-stopped` or `always` |
| kavure | All `unless-stopped` (pz-server, panel, dockerproxy, ops) |

### Systemd (auto-start on boot)
| Service | psicopompo | ybytu | ybyra | kuaray | kavure |
|---|---|---|---|---|---|
| docker | ✅ enabled | ✅ enabled | ✅ enabled | ✅ enabled | ✅ enabled |
| tailscaled | ✅ enabled | ✅ enabled | ✅ enabled | ✅ enabled | ✅ enabled |
| filebrowser | — | ✅ enabled | — | — | — |
