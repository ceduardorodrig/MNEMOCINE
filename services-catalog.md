---
tags: [homelab, service, meta]
---

# Mnemocine Service Catalogue

**What runs where, why it exists, who depends on it, and who owns it** — one table per host.

This is the missing *intent* layer of the homelab. [`network/ports.md`](network/ports.md) answers
*"which socket is open, on which interface, and is it an attack surface?"*; this catalogue answers
*"what is this service for, what breaks if it stops, and who is accountable?"*. The two are meant to
be read together: a port row without a catalogue row is an unexplained socket, and a catalogue row
without a port row is a service that binds nothing (or binds undocumented).

> **How to read this doc.** It is a **reconciliation target, not a memory dump** — the values were
> captured live (2026-10-13) and are expected to be re-derived from the hosts, never edited from
> memory. See [§ How to keep this current](#how-to-keep-this-current).

## Legend

| Column | Meaning |
|---|---|
| **service** | Runtime identity (container name, Swarm service name, systemd unit, or process). |
| **how** | `container` (standalone Compose/`docker run`) · `swarm` (replicated service on `sae-net`) · `native` (systemd/binary, no container) · `embedded` (a child process **inside** another container — not a standalone unit) · `nfs mount` (a filesystem mount, no daemon). A `how` the reconciler cannot classify is left unchecked for staleness. |
| **port(s) + bind** | Observed listening bind. Loopback/tailnet-only is the homelab default; `0.0.0.0` is called out (and audited in [`ports.md`](network/ports.md)). |
| **why it exists** | Owner-facing purpose — what it is *for*, not how it is built. |
| **who depends on it** | Consumers that break or degrade if the service is down. |
| **owner** | Accountable operator. `edu` = Carlos Eduardo Rodrigues, sole homelab owner/operator (SUMÆNIMÁ MEI). `edu · SUMÆNIMÁ` = production Sumænimá Hub path; `edu · Miracena` = incubated client project. |

The hosts are `psicopompo` (workstation, GPU, NAS), `kavure` (services + Swarm manager),
`kuaray` (media + Miracena, standalone), `ybytu` (cloud DNS/dashboard), `ybyra` (cloud edge) and
`kururu` (Alpine ARM probe/WoL).

---

## psicopompo — `100.82.51.112`

Primary workstation, sole GPU host (RTX 5050), NFSv4 NAS, Swarm **worker**.

| service | what it does (1 line) | how | port(s) + bind | why it exists | who depends on it | owner |
|---|---|---|---|---|---|---|
| steniorec | Whisper speech-to-text daemon (Rust Axum + CUDA) | container | `127.0.0.1:9090` + `100.82.51.112:9090` | local GPU transcription for meeting reporting / real-time STT | edge nginx `/api/ws/transcribe`; `hl-infer` (resident lease) | edu · SUMÆNIMÁ |
| comfyui | Diffusion image generation (batch GPU consumer) | container | `127.0.0.1:8188` + `100.82.51.112:8188` | on-demand AI image generation | `hl-infer` (`image_gen` lease) | edu |
| registry | Private Docker image registry (`registry:3`, TLS + htpasswd) | container | `127.0.0.1:5000` + `100.82.51.112:5000` | single source of truth for Swarm images (`--with-registry-auth`) | kavure + ybyra Swarm deploys | edu |
| glances | Host telemetry agent (CPU/RAM/GPU/thermal) | container | `127.0.0.1:61208` + `100.82.51.112:61208` | quick at-a-glance host health | Homepage tile | edu |
| dockerproxy | Read-only Docker socket proxy | container | `127.0.0.1:2375` + `100.82.51.112:2375` | gives Homepage live container status without the raw socket | Homepage (ybytu) | edu |
| node-exporter | Prometheus host metrics exporter | container | `100.82.51.112:9100` | host telemetry into Prometheus | Prometheus (kavure) | edu |
| promtail | Loki log shipper | container (host net) | `127.0.0.1:9080` (health) | central log aggregation | Loki (kavure) | edu |
| watchtower | Automated container image updater | container | — | keeps images current | — | edu |
| autoheal | Restarts unhealthy containers | container | — | self-healing of healthchecked containers | all local containers | edu |
| hl-infer | GPU inference gateway (VRAM ledger, leases, fixed windows) | native (systemd) | `127.0.0.1:9095` + `100.82.51.112:9095` | **one** arbiter for the single GPU (ADR-020, no CPU fallback) | steniorec, comfyui, ollama, autopilot | edu |
| ollama | Local LLM runtime | native (systemd) | `127.0.0.1:11434` | local model inference | steniobot/autopilot (leases via `hl-infer`) | edu |
| libvirtd + dnsmasq | KVM hypervisor + NAT DNS/DHCP for guest VMs | native | `192.168.122.1:53` (`virbr0`) | isolated VM lab (`kali-linux`) | local VMs | edu |
| waydroid | Android-in-container runtime | native | — | run Android apps on the workstation | owner | edu |
| nfsd / rpcbind / rpc.mountd | NFSv4 server (NAS) | native | `100.82.51.112:2049`, `111`, `20048` | shared storage for the fleet | kavure + kuaray NFS mounts | edu |
| hl-wol-relay | Wake-on-LAN relay (wakes kavure) | native (systemd) | `127.0.0.1:9096` + `tailscale serve` | remote power-on of the peer | Homepage WoL / ybytu dispatcher | edu |
| sumaenima-gpu | GPU worker supervisor (Rust, event-driven) | native (systemd) | — | boot-order + revive `steniorec` (overlay lazy attach) | steniorec | edu · SUMÆNIMÁ |
| syncthing | Vault P2P synchronization | native (**user** systemd, `edu`) | `127.0.0.1:8384` + tailnet `8384` + `22000` | sync the Obsidian vault to phones/kuaray | kuaray Syncthing; mobile devices | edu |
| hl-sftp-mount | Mounts the kuaray/kavure SFTP shares into the desktop file managers (`gio mount sftp://…`) | native (**user** systemd + timer) | — | remote shares reappear as Network Drives at login and recover every 5 min | owner desktop (Nautilus/Dolphin) | edu |
| hl-rclone-mount | FUSE mount of `gdrive:` at `~/Google_Drive` | native (**user** systemd) | — | cloud storage present locally for the off-site backup/sync | `hl-rclone-gdrive-backup.timer` | edu |
| punktfunk-host | Low-latency game/desktop streaming host | native (**user** systemd) | `0.0.0.0:47990` (ufw-scoped) + `9777/udp` | Moonlight/Punktfunk streaming | streaming clients | edu |
| punktfunk-web | Punktfunk management web console | native (**user** systemd) | `0.0.0.0:47992` (ufw-scoped) | auth-gated admin console | owner | edu |
| punktfunk-scripting | Punktfunk plugin/script runner | native (**user** systemd) | `0.0.0.0:47993` (ufw-scoped) | plugin interface bindings | punktfunk-host | edu |

## kavure — `100.124.146.77`

Dedicated services node and **Swarm manager** (`sae-core` + `sae-edge` standby).

| service | what it does (1 line) | how | port(s) + bind | why it exists | who depends on it | owner |
|---|---|---|---|---|---|---|
| sae-core_api | Sumænimá Hub REST/WS API (**Rust Axum**) | swarm | `sae-net` overlay `9090` (not host-published) | core business logic of the Hub | edge `sae-edge_proxy`; steniorec/GPU workers | edu · SUMÆNIMÁ |
| sae-core_db | PostgreSQL 16 (pgvector) | swarm | `sae-net` overlay `5432` | Hub relational state | sae-core_api | edu · SUMÆNIMÁ |
| sae-core_valkey | Valkey cache / Pub-Sub broker | swarm | `sae-net` overlay `6379` | cache + message broker | sae-core_api; GPU workers | edu · SUMÆNIMÁ |
| sae-core_umami-db | PostgreSQL 15 (Umami analytics) | swarm | `sae-net` overlay `5432` | analytics storage | sae-edge_umami | edu · SUMÆNIMÁ |
| sae-core_backup | Backup sentinel + health endpoint | swarm | `9092` (ingress/health) | proves backups are fresh (Borg → NAS) | Homepage "Sumænimá Backup" tile | edu · SUMÆNIMÁ |
| sae-edge_{proxy,tunnel,umami}-standby | Dormant edge failover replicas (`replicas: 0`) | swarm | — | take over public ingress during ybyra failover | edge continuity | edu · SUMÆNIMÁ |
| aiostreams | Audio/video stream aggregator | container | `127.0.0.1` + `100.124.146.77:3000` (+ Funnel `10000`) | Stremio-style streaming for the owner | Stremio clients | edu |
| comet | Usenet/torrent indexer addon | container | `100.124.146.77:8000` | metadata/indexing for streaming | aiostreams / Stremio | edu |
| n8n | Homelab workflow automation engine | container | `100.124.146.77:5678` | self-hosted automation (distinct from Miracena n8n) | owner workflows | edu |
| n8n-postgres | PostgreSQL for Homelab n8n | container | internal `5432` | n8n state | n8n | edu |
| zomboid-panel | Project Zomboid web admin (RCON-only manager; the game runs in the separate `pz-server` container) | container | `100.124.146.77:3001` | manage the PZ dedicated server | owner / players | edu |
| crafty-controller | Crafty Controller 4 (Minecraft manager; runs Dominium Fabric) | container | `100.124.146.77:8444`, `0.0.0.0:25565`, `24454/udp` | Minecraft server management | Minecraft players | edu |
| valheim-server | Valheim dedicated server | container | `0.0.0.0:2456-2458/udp` | multiplayer Valheim | players | edu |
| homeassistant | Home automation hub (host net) | container | `0.0.0.0:8123` | IoT orchestration + mDNS/SSDP discovery | owner automations | edu |
| go2rtc | Embedded WebRTC camera server | `embedded` — child process **inside `homeassistant`**, not a standalone unit (`docker ps` shows no `go2rtc`; `/bin/go2rtc` runs inside the HA unit, PID owning `18554`/`18555`) | `127.0.0.1:18554`, `0.0.0.0:18555` | camera streaming for HA | homeassistant | edu |
| pihole | Filtering DNS (host net) | container | `127.0.0.1` + `100.124.146.77:53`, `0.0.0.0:80`/`443` | primary DNS sinkhole | all DNS clients; Homepage tile | edu |
| searxng-core | Privacy-respecting metasearch engine | container | `100.124.146.77:8080` | ad-free private search | owner | edu |
| searxng-valkey | Valkey cache for SearXNG | container | internal `6379` | search result cache | searxng-core | edu |
| calibre | Calibre-Web eBook library | container | `100.124.146.77:8083` | personal eBook catalog + reader | owner | edu |
| navidrome | Subsonic-compatible music streaming | container | `100.124.146.77:4533` | stream the music library | owner / clients | edu |
| glances | Host telemetry agent | container | `100.124.146.77:61208` | at-a-glance host health | Homepage tile | edu |
| monitoring-prometheus | Time-series metrics engine + alert rules | container | `100.124.146.77:9091` | central metrics store | Grafana, Alertmanager | edu |
| monitoring-grafana | Observability dashboards | container | `100.124.146.77:3002` | visualize fleet telemetry | owner | edu |
| monitoring-loki | Log aggregation store | container | `100.124.146.77:3100` | central logs | Grafana; all promtails | edu |
| monitoring-alertmanager | Alert routing engine | container | `100.124.146.77:9093` | route firing alerts | monitoring-alertmanager-ntfy | edu |
| monitoring-cadvisor | Container resource metrics | container | internal | per-container metrics | Prometheus | edu |
| monitoring-promtail | Loki log shipper (kavure) | container | — | ship kavure logs | Loki | edu |
| monitoring-alertmanager-ntfy | Alertmanager → ntfy bridge | container | internal `8000` | push alerts to phones | Alertmanager → ntfy (ybytu) | edu |
| node-exporter | Prometheus host metrics | container | `0.0.0.0:9100` | host telemetry | Prometheus | edu |
| dockerproxy | Read-only Docker socket proxy | container | `127.0.0.1` + `100.124.146.77:2375` | Homepage live status | Homepage | edu |
| watchtower | Image auto-updater | container | — | keep images current | — | edu |
| autoheal | Restart unhealthy containers | container | — | self-healing | all local containers | edu |
| dnscrypt-proxy | Anonymized DNS egress (**COLD — exited**) | container | — | decommissioned 2026-10-08 (superseded by native unbound) | none | edu |
| unbound | Native recursive DNSSEC resolver | native (systemd) | `127.0.0.1` + `100.124.146.77:5053` | upstream resolver for Pi-hole + AdGuard | pihole (kavure); adguardhome (ybytu) | edu |
| hl-unbound-status | Rust HTTP health endpoint for the Unbound tile | native (systemd) | `0.0.0.0:9097` | lets Homepage show native-unbound health | Homepage "Unbound" tile | edu |
| hl-minecraft-status | Rust Minecraft SLP status probe | native (systemd) | `0.0.0.0:9095` | true in-game availability for the Minecraft tile | Homepage "Minecraft Server" tile | edu |
| hl-zomboid-health | Rust Project Zomboid status probe (game RCON `27015`) | native (systemd) | `0.0.0.0:9098` | true game availability for the Zomboid tile | Homepage "Project Zomboid" tile | edu |
| hl-wol-relay | Wake-on-LAN relay (wakes psicopompo) | native (systemd) | `127.0.0.1:9096` + `tailscale serve` | remote power-on of the peer | Homepage WoL / ybytu dispatcher | edu |
| hl-nic-power-tuning | Disables NIC power saving (EEE off) at boot | native (systemd oneshot) | — | LAN stability mitigation (2026-10-10) — Realtek `enp1s0` (`ethtool --set-eee enp1s0 eee off`) | kavure LAN/tailnet links | edu |
| scryfall-mirror | Scryfall bulk-data + art cache — **not a daemon**: the export lives on **psicopompo** (`/mnt/SSD_SATA/scryfall-mirror`); kavure only mounts it and drives the daily sync | `nfs mount` (+ `hl-scryfall-*` timers) | — (NFSv4 mount of psicopompo) | feeds Arandu TCG data offline | Arandu / arandu-sync | edu |
| hl-* timers | Host automation (config/zomboid/n8n/valheim/sumaenima backups, metrics, DNS watchdog) | native (systemd timers) | — | scheduled backups + telemetry | NAS; Prometheus | edu |

## kuaray — `100.94.209.99`

Standby mirror / media + **Miracena** client stack. **Standalone Docker — not a Swarm node**
(`docker info` → `Swarm: pending`).

| service | what it does (1 line) | how | port(s) + bind | why it exists | who depends on it | owner |
|---|---|---|---|---|---|---|
| miracena-directus | Headless CMS backend | container | `100.94.209.99:8055` | Miracena client data layer | miracena-nuxt, WordPress | edu · Miracena |
| miracena-wordpress | WordPress content engine | container | `100.94.209.99:8085` | Miracena public site | miracena-tunnel (Funnel) | edu · Miracena |
| miracena-nuxt | Nuxt 3 frontend (SSR) | container | `100.94.209.99:3003` | Miracena web frontend | owner | edu · Miracena |
| miracena-n8n | Workflow automation (Miracena) | container | `100.94.209.99:5678` | Miracena automations | owner | edu · Miracena |
| miracena-nginx-proxy-manager | Reverse proxy + SSL manager | container | `100.94.209.99:81`, `8180`, `8445` | ingress for the Miracena stack | Miracena services | edu · Miracena |
| miracena-tunnel | Tailscale Funnel ingress | container | HTTPS 443 (Funnel) | public URL for Miracena | external visitors | edu · Miracena |
| miracena-postgres / -mariadb / -redis | Databases + cache for the stack | container | internal `5432` / `3306` / `6379` | state + caching | Directus, WordPress, n8n | edu · Miracena |
| transmission | BitTorrent client | container | `0.0.0.0:9091`, `51413` | download engine | prowlarr/lidarr pipelines | edu |
| prowlarr | Indexer proxy manager | container | `0.0.0.0:9696` | central indexer hub | lidarr | edu |
| lidarr | Music collection manager | container | `0.0.0.0:8686` | automate music library | owner | edu |
| slskd | Headless Soulseek client | container | `0.0.0.0:5030` | Soulseek downloads | soularr | edu |
| soularr | Soulseek ↔ Lidarr bridge | container | `0.0.0.0:8265` | bridge Soulseek to Lidarr | lidarr | edu |
| flaresolverr | Cloudflare challenge bypass proxy | container | `0.0.0.0:8191` | unblock indexer scrapes | prowlarr | edu |
| big-bear-vert | Vert media converter (microblogging/media) | container | `0.0.0.0:3030` | media conversion web UI | owner | edu |
| syncthing | Vault/media synchronization (host net) | container | `127.0.0.1:8384` + tailnet `8384` + `22000` | mirror of the vault/NAS | psicopompo Syncthing; phones | edu |
| glances | Host telemetry agent (host net) | container | `100.94.209.99:61208` | at-a-glance host health | Homepage tile | edu |
| node-exporter | Prometheus host metrics | container | `0.0.0.0:9100` | host telemetry | Prometheus | edu |
| promtail | Loki log shipper | container | — | ship kuaray logs | Loki | edu |
| watchtower | Image auto-updater | container | — | keep images current | — | edu |
| autoheal-autoheal-1 | Restart unhealthy containers | container | — | self-healing | all local containers | edu |
| dockerproxy | Read-only Docker socket proxy | container | `127.0.0.1` + `100.94.209.99:2375` | Homepage live status | Homepage | edu |
| ~~smbd / nmbd~~ | ~~SMB file sharing~~ | native | ~~`139`, `445`~~ | **Deactivated 2026-10-15** (no fleet dependencies; UFW rules purged) | — | edu |
| ~~xrdp~~ | ~~Remote desktop (RDP) server~~ | native | ~~`0.0.0.0:3389`~~ | **Deactivated 2026-10-15** (remote access unified via Tailscale SSH/SFTP) | — | edu |
| cups (+ cups-browsed) | Print server | native | — | printing from the node | owner | edu |
| avahi-daemon | mDNS/DNS-SD discovery | native | `5353/udp` | LAN service discovery | LAN clients | edu |
| rpcbind | RPC port mapper (NFS client) | native | `0.0.0.0:111` | mount NAS shares | local NFS mounts | edu |
| hl-nic-power-tuning | Disables NIC power saving (EEE off) at boot | native (systemd oneshot) | — | LAN stability mitigation (2026-10-10) — Realtek `enp7s0` (`ethtool --set-eee enp7s0 eee off`) | kuaray LAN/tailnet links | edu |

## ybytu — `100.115.253.109`

Cloud utility node (OCI Always Free): exit node, DNS failover, dashboard, notifications.

| service | what it does (1 line) | how | port(s) + bind | why it exists | who depends on it | owner |
|---|---|---|---|---|---|---|
| homepage | Central homelab dashboard (host net) | container | `0.0.0.0:3001` (nft → tailnet) | single pane of glass over every host | owner | edu |
| adguardhome | Filtering DNS + admin console | container | `100.115.253.109:53` + `127.0.0.1:53`, `0.0.0.0:3000` | network-wide ad-blocking DNS | all DNS clients; Homepage tile | edu |
| uptime-kuma | Uptime monitoring + status pages (host net) | container | `0.0.0.0:3002` (nft → tailnet) | external HTTP/port probes + incident alerts | owner | edu |
| changedetection | Web page change monitor | container (Compose) | `0.0.0.0:8082` | watch portals/notices/job boards | owner | edu |
| ntfy | Self-hosted push notification gateway | container | `0.0.0.0:8083` | deliver systemd/backup/alert push to phones | Alertmanager (kavure); host webhooks | edu |
| glances | Host telemetry agent | container | `100.115.253.109:61208` | at-a-glance host health | Homepage tile | edu |
| watchtower | Image auto-updater | container | — | keep images current | — | edu |
| autoheal | Restart unhealthy containers | container | — | self-healing | all local containers | edu |
| node-exporter | Prometheus host metrics | container | `0.0.0.0:9100` (nft → tailnet) | host telemetry | Prometheus | edu |
| promtail | Loki log shipper | container | — | ship ybytu logs | Loki | edu |
| dockerproxy | Read-only Docker socket proxy | container | `100.115.253.109:2375` | Homepage live status | Homepage | edu |
| hl-wol-dispatcher | Smart WoL dispatcher with auto-failover | native (systemd) | `0.0.0.0:9096` | **the target of both Homepage "Ligar" tiles** (routes to kururu, falls back to x86 peers) | Homepage WoL tiles | edu |
| vnstat | Network traffic accounting | native (systemd) | — | bandwidth history per interface | owner | edu |
| hl-tailscale-gro | Tailscale UDP GRO optimization on the cloud NIC | native (systemd oneshot) | — | higher Tailscale throughput (`ethtool -K ens3 rx-udp-gro-forwarding on rx-gro-list off`) | ybytu tailnet traffic | edu |

## ybyra — `100.66.224.34`

Cloud **primary edge** (OCI Always Free), Swarm **worker** running `sae-edge`. TLS terminates at
Tailscale Funnel — there is **no native nginx and no `443` listener on the host**.

| service | what it does (1 line) | how | port(s) + bind | why it exists | who depends on it | owner |
|---|---|---|---|---|---|---|
| sae-edge_proxy | Nginx reverse proxy (SPA + `/api/` + `/umami/`) | swarm (mode host) | `0.0.0.0:80` | public edge ingress for Sumænimá | external visitors | edu · SUMÆNIMÁ |
| sae-edge_tunnel | Tailscale Funnel gateway (node `sumaenima`) | swarm | — (Funnel 443) | terminate public TLS without exposing a host listener | sae-edge_proxy | edu · SUMÆNIMÁ |
| sae-edge_umami | Web analytics engine | swarm | internal `3000` | privacy-preserving site analytics | sae-edge_proxy | edu · SUMÆNIMÁ |
| glances | Edge node telemetry agent | container | `100.66.224.34:61208` | at-a-glance host health | Homepage tile | edu |
| watchtower | Image auto-updater | container | — | keep images current | — | edu |
| autoheal | Restart unhealthy containers | container | — | self-healing | all local containers | edu |
| node-exporter | Prometheus host metrics | container | `0.0.0.0:9100` (nft → tailnet) | host telemetry | Prometheus | edu |
| promtail | Loki log shipper | container | — | ship ybyra logs | Loki | edu |
| dockerproxy | Read-only Docker socket proxy | container | `100.66.224.34:2375` | Homepage live status | Homepage | edu |
| rpcbind | RPC port mapper (NFS client) | native | `0.0.0.0:111` (nft → tailnet) | mount NAS shares | local NFS mounts | edu |

## kururu — `100.127.188.45`

Headless Alpine ARM probe (Samsung SM-T110). **Native only — no Docker.** Absent from the Homepage
entirely.

| service | what it does (1 line) | how | port(s) + bind | why it exists | who depends on it | owner |
|---|---|---|---|---|---|---|
| kururu-wake | 24/7 Wake-on-LAN sender (`--daemon 9096`) | native (binary) | `0.0.0.0:9096` | always-on power-on of psicopompo + kavure | ybytu dispatcher; Homepage WoL tiles | edu |
| kururu-sentinel | Power guardian: heartbeat + coordinated shutdown | native (binary) | — | protect hosts during power outages | psicopompo + kavure | edu |
| kururu-display | Framebuffer telemetry / touch UI | native (binary) | — | on-device status, WoL controls, clock | owner (on-device) | edu |
| kururu-host | Utility/shell wrapper (`kururu-su` symlink); **not a daemon** | native (binary) | — | local admin/privilege helper on the tablet | owner | edu |
| dropbear | SSH server (Ed25519 key-only) | native | `0.0.0.0:22` | remote access to the probe node | owner | edu |
| tailscaled | Tailnet membership (`--netfilter-mode=off`) | native | `100.127.188.45` | put the ARM node on the mesh | fleet access | edu |

---

## (a) Services present on a host but ABSENT from the Homepage

The Homepage (`ybytu:3001`) is the dashboard, not the inventory — these run but have no tile.
Grouping them here is deliberate: an untracked service is the one nobody notices is down.

| Host | Not on the Homepage | Why it is (still) untracked |
|---|---|---|
| psicopompo | `ollama`, `libvirtd`+`dnsmasq`, `waydroid`, `nfsd`/`rpcbind`, `sumaenima-gpu`, `punktfunk-web`/`-scripting`, `dockerproxy`, `hl-sftp-mount`, `hl-rclone-mount`, `hl-docker-prune` | internal infrastructure / no owner-facing UI (Punktfunk tile covers the host only; the SFTP/rclone mounts are desktop-local) |
| kavure | `go2rtc`, `searxng-valkey`, `monitoring-cadvisor`, `monitoring-alertmanager-ntfy`, `dockerproxy`, `sae-edge_*-standby`, `n8n-postgres`, `scryfall-mirror`, `hl-nic-power-tuning`, `hl-*` timers, `dnscrypt-proxy` (cold) | internal dependencies, dormant failover, or deliberately frozen |
| kuaray | `dockerproxy`, `cups`, `avahi`, `rpcbind`, `hl-nic-power-tuning`, `miracena-postgres`/`-mariadb`/`-redis`/`-tunnel` | native LAN services or internal stack members (Samba and xrdp deactivated 2026-10-15) |
| ybytu | `dockerproxy`, `hl-wol-dispatcher`, `vnstat`, `hl-tailscale-gro`, **`homepage` itself** | infrastructure/tooling without a dedicated UI |
| ybyra | `dockerproxy`, `sae-edge_proxy`/`tunnel`/`umami`, `rpcbind` | the edge is represented by the "Portal Sumænimá" tile, not per-service |
| kururu | **everything** (`kururu-wake`, `kururu-sentinel`, `kururu-display`, `kururu-host`, `dropbear`, `tailscaled`) | the node is not in the dashboard at all |

## (b) Homepage tiles pointing at something that does not exist

| Tile | Points at | Reality |
|---|---|---|
| **Project Zomboid** (Kavure group) | ~~`server: kavure` + `container: pz-server`~~ → `siteMonitor: http://kavure:9098` | **Resolved 2026-10-13.** The tile used a Docker chip on `pz-server`, which rendered "not found" because the game was stopped: `zomboid-stop` (`docker compose down`) **removes** the `pz-server` container. The game **does** run in that container when up (it publishes RCON `27015` + UDP `16261-16262`) — the earlier "child process of `zomboid-panel`" reading was wrong. The chip was replaced by a `siteMonitor` on the native **`zomboid-health`** endpoint (`kavure:9098`, RCON `27015` probe → 200/503). See [`services/zomboid-health.md`](services/zomboid-health.md). |

> **Description drift (resolved 2026-10-13):** the **"Sumænimá API"** tile read
> `Fastify Core Swarm · Kavure`, but `sae-core_api` is a **Rust Axum** service. The host description was
> normalized to `REST/WS API · Kavure` in the 13/10 tile-standardization pass (see
> [`services/homepage.md`](services/homepage.md)).

## How to keep this current

This document is meant to be **reconciled against the hosts**, not maintained from memory. When
anything in the fleet changes, re-derive the affected rows with the read-only probes below, then
edit only what differs. If a row disagrees with a host, the host wins.

| Layer | Command (per host, read-only) | Feeds |
|---|---|---|
| Containers | `docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'` | service, how, port+bind |
| Swarm services | `docker service ls` (manager only) | swarm rows |
| Native listeners | `ss -tlnp` (and `-ulnp` for UDP) | port+bind, native rows |
| Native units | `systemctl list-units --type=service --state=running` | native rows |
| User units | `systemctl --user list-units --type=service --state=running` (psicopompo) | punktfunk/syncthing rows |
| Dashboard truth | `homepage/config/services.yaml` on ybytu | §(a)/§(b) |
| **Whole-fleet drift** | `stenio --reconcile` (run from the repo root) | Re-derives **every per-host row below** against the live hosts and the Tailscale policy, via the manifest [`governance/stenio/sources.toml`](../governance/stenio/sources.toml) — emits `REALITY-UNDECLARED` / `DECLARATION-STALE` / `PURPOSE-MISSING` / `POLICY-UNDERIVABLE` |

**Rules of the road:**

1. **Ports live in [`ports.md`](network/ports.md).** This catalogue must not duplicate the attack
   surface; when a bind changes, fix `ports.md` **and** the "port(s) + bind" cell here.
2. **The Homepage is the dashboard, not the source of truth.** Add a tile when a service becomes
   owner-facing; when a tile points at nothing (see §(b)), fix the tile or remove it — never leave a
   chip that can only ever render "not found".
3. **New service ⇒ update this file, the service manifest in [`services/`](services/), and
   `README.md`** in the same change (config-as-code). The `ports.md` entry is mandatory if it binds.
4. **Hosts without the Rust toolchain** (ybytu/ybyra/kururu) use GNU `grep`/`ss`/`netstat` for these
   probes — that is the sanctioned exception, recorded here so the next reconciler does not "fix" it.
5. **No secrets here.** Credentials belong in the SOPS store; this file names services, never keys.
6. **The engine checks this file.** `stenio --reconcile` compares these rows with what is actually
   running (containers + systemd units, declared in
   [`governance/stenio/sources.toml`](../governance/stenio/sources.toml)) and with the Tailscale
   policy. A row it flags as `REALITY-UNDECLARED`/`DECLARATION-STALE` is drift: **fix the row (or
   the host), never silence it**. A `how` the reconciler cannot classify as container/native is
   deliberately left unchecked for staleness (e.g. an `nfs mount`, an `embedded` process).

## See also

- [`network/ports.md`](network/ports.md) — canonical port catalog & attack surface
- [`network/service-topology.md`](network/service-topology.md) — inter-service dependencies & Docker networks
- [`network/topology.md`](network/topology.md) — IPs, subnets, storage mounts, firewall
- [`services/homepage.md`](services/homepage.md) — the dashboard this catalogue reconciles against
