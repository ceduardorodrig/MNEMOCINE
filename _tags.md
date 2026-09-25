---
tags: [homelab, meta, taxonomy]
---

# Tag Taxonomy

Single source of truth for allowed tags in this repository.
Tags are always in English.
Every `tags:` in YAML frontmatter must only use tags listed here.

## Categories

### `#homelab` — Everything related to this repo
Root tag. Every file inside `mnemocine` must have it.

### `#server` — Tailnet servers
- `#psicopompo` — Main / gaming / desktop
- `#ybytu` — Cloud / primary DNS
- `#ybyra` — Cloud / future SPA host
- `#kuaray` — Media / Home Assistant
- `#kavure` — Dedicated services server (Project Zomboid, panel; Sumænimá in migration)

### `#service` — Individual services
- `#adguard` — AdGuard Home (DNS)
- `#aiostreams` — Web audio/video streaming
- `#calibre-web` — eBook library
- `#casaos` — kuaray management panel (~~active~~ — **historical**, removed 08/08)
- `#comet` — Usenet indexer
- `#crafty` — Minecraft server (psicopompo)
- `#duplicati` — File backup (~~active~~ — **historical**, removed 06/08)
- `#flaresolverr` — Proxy for Cloudflare
- `#grafana` — Observability dashboards
- `#home-assistant` — Home automation
- `#homepage` — Services dashboard
- `#uptime-kuma` — Uptime monitoring
- `#kavita` — Manga/comic reader (~~active~~ — **historical**, removed 10/08)
- `#lidarr` — Music manager
- `#loki` — Log aggregation (Loki)
- `#mosquitto` — Broker MQTT
- `#navidrome` — Music streaming
- `#n8n` — Visual automation (workflows)
- `#pihole` — DNS blocker (kuaray)
- `#portainer` — Docker management
- `#prometheus` — Time-series metrics (Prometheus)
- `#punktfunk` — Low-latency game/desktop streaming
- `#changedetection` — Change monitoring on pages
- `#ntfy` — Push notifications
- `#prowlarr` — Torrent/usenet indexer
- `#soularr` — Soulseek + Lidarr integration
- `#searxng` — Private search (meta-search)
- `#slskd` — Soulseek client
- `#steniobot` — AI reporting bot
- `#sumaenima-local` — Local control of SUMAENIMA (sumaenima-ctl)
- `#stremio` — Movie/series streaming
- `#syncthing` — File synchronization
- `#transmission` — Torrent client
- `#vert` — Decentralized microblogging
- `#watchtower` — Container auto-update
- `#zomboid` — Project Zomboid server
- `#zomboid-panel` — Project Zomboid web panel
- `#wol` — Wake-on-LAN, remote trigger relay

### `#network` — Network, DNS and firewall
### `#tailscale` — Tailscale specific
### `#backup` — Backup strategy and procedures
- `#snapshot` — btrfs/snapper snapshots (anti-deletion)
- `#snapper` — Snapper specific
- `#btrfs` — btrfs filesystem
- `#config` — Settings and compose
- `#compose` — Docker Compose
- `#ritual` — Rituals and backup verification
- `#checklist` — Checklist / pending items
### `#recovery` — Disaster recovery
### `#docker` — Docker, compose, containers

### Service categories
- `#media` — Streaming, music, books
- `#download` — Torrent, Usenet, Soulseek
- `#dns` — AdGuard, Pi-hole
- `#automation` — Home Assistant, MQTT
- `#monitoring` — Portainer, Homepage, Glances
- `#gaming` — Crafty, Steam, Minecraft
- `#storage` — Disks, pools, volumes, mounts
- `#cloud` — Cloud storage, remotes, off-site sync
- `#rclone` — Rclone, mounts, Google Drive
- `#tutorial` — Step-by-step guides
- `#todo` — Pending items / WIP
- `#env` — Environment variables, ports
- `#sops` — Secret encryption (sops/age), central store
- `#ssl` — Certificates, TLS
- `#meta` — Tags that describe the tag system itself
- `#taxonomy` — Used in _tags.md itself
- `#agents` — Instructions for AI agents
- `#steam` — Steam / games on Linux
- `#power` — Power, suspend, hibernate (S3/S4)

### `#hardware` — Physical devices, peripherals, media
- `#usb` — USB devices, flash drives, recorders
- `#fat` — FAT32, vfat filesystem, dirty bit
- `#gpu` — Graphics cards (GPU) and video configuration
- `#nvidia` — NVIDIA driver and configuration (proprietary)
- `#rebar` — ReBAR / Resizable BAR (Dell BIOS does not allow it; via Linux it does)

### `#desktop` — Desktop / Workstation (e.g.: KDE on psicopompo)
- `#kde` — KDE Plasma (session, applets, configuration)
- `#plasma` — Plasma shell / widgets / workarounds
