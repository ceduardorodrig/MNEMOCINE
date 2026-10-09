---
tags: [homelab, meta, taxonomy]
---

# Tag Taxonomy

Single source of truth for allowed tags across the Mnemocine Homelab infrastructure documentation.
Tags are always written in lowercase English or proper noun identifiers.
Every `tags:` declaration in YAML frontmatter must strictly use tags listed here.

## Categories

### `#homelab` — Root Namespace Tag
The mandatory root tag. Every documentation file inside `mnemocine` must include this tag.

### `#server` — Tailnet Node Classification
- `#psicopompo` — Primary workstation / AI host / gaming node (Xeon E-2246G + RTX 5050, CachyOS)
- `#ybytu` — Cloud edge / AdGuard DNS server / Pi-hole failover (Oracle Cloud OCI Always Free, Ubuntu 24.04 LTS)
- `#ybyra` — Cloud edge reverse proxy / Tailscale Funnel gateway (Oracle Cloud OCI Always Free, Ubuntu 24.04 LTS)
- `#kuaray` — Standby mirror / archive node (Linux Mint 22.3 Zena)
- `#kavure` — Dedicated services server & Docker Swarm manager (Core i3-8100, Ubuntu 24.04 LTS)
- `#kururu` — Headless lightweight experiment node (Samsung SM-T110 / Alpine Linux / Tailscale SSH)

### `#service` — Individual Service Tags
- `#adguard` — AdGuard Home network-wide DNS resolver & ad blocker
- `#aiostreams` — Audio/video web streaming microservice
- `#calibre-web` — Web reading interface and eBook library manager
- `#casaos` — Legacy web administration interface (~~active~~ — **historical archive**, removed 2026-08-08)
- `#cold-storage` — Frozen services and deactivated runbooks (preserved for reference and rollback)
- `#comet` — Usenet indexer and scraper
- `#crafty` — Crafty Controller 4 dedicated Minecraft server web manager (kavure)
- `#dnscrypt` — dnscrypt-proxy resolver (~~active~~ — **historical archive**, decommissioned 2026-10-08)
- `#duplicati` — Legacy backup system (~~active~~ — **historical archive**, replaced 2026-08-06)
- `#flaresolverr` — Proxy service for Cloudflare challenge bypass
- `#grafana` — Telemetry, metric aggregation, and system observability dashboards
- `#home-assistant` — Home automation, IoT orchestration, and sensor telemetry
- `#homepage` — Fast, consolidated homelab landing dashboard and service catalog
- `#uptime-kuma` — Self-hosted uptime monitoring and incident alerting service
- `#kavita` — Manga and comic reader (~~active~~ — **historical archive**, removed 2026-08-10)
- `#lidarr` — Automated music collection and indexing manager
- `#loki` — Distributed log aggregation and search engine (Grafana Loki)
- `#mosquitto` — Eclipse Mosquitto MQTT message broker
- `#navidrome` — Subsonic-compatible music streaming server
- `#n8n` — Visual workflow automation and self-hosted integration engine
- `#pihole` — Secondary DNS sinkhole & blocker (kavure)
- `#portainer` — Legacy Docker container management interface (decommissioned in favor of CLI + Homepage)
- `#prometheus` — Time-series metrics collection and monitoring system
- `#punktfunk` — Low-latency desktop and game streaming protocol
- `#changedetection` — Automated web page change monitoring and notification daemon
- `#ntfy` — Lightweight push notification server delivering real-time mobile alerts
- `#prowlarr` — Torrent and Usenet indexer integration hub
- `#soularr` — Soulseek and Lidarr bridge integration daemon
- `#searxng` — Privacy-respecting metasearch engine
- `#slskd` — Headless Soulseek client daemon
- `#steniobot` — AI meeting reporting and transcription bot
- `#sumaenima-local` — Local Sumænimá service management interface (`sumaenima-ctl`)
- `#stremio` — Streaming server integration
- `#syncthing` — Continuous decentralized peer-to-peer file synchronization
- `#transmission` — BitTorrent download client and daemon
- `#unbound` — Validating, recursive, caching DNS resolver with DNSSEC (kavure)
- `#vert` — Decentralized microblogging service
- `#watchtower` — Automated Docker container base image updater
- `#zomboid` — Project Zomboid dedicated persistence game server
- `#zomboid-panel` — Project Zomboid dedicated server web administration panel
- `#wol` — Wake-on-LAN and remote network power management relay

### `#network` — Network, DNS & Firewall Architecture
### `#tailscale` — Tailscale Mesh & WireGuard Zero-Trust Networking
### `#oracle` — Oracle Cloud Infrastructure (OCI)
- `#oracle` — Oracle Cloud Always-Free tenancy and infrastructure configurations
- `#oci` — OCI CLI automation, API keys, and cloud virtual machine management
### `#backup` — Backup Strategies & Procedures
- `#snapshot` — Btrfs and Snapper copy-on-write filesystem snapshots (anti-deletion safeguard)
- `#snapper` — Snapper subvolume snapshot configuration
- `#btrfs` — Btrfs native filesystem features and tuning
- `#config` — Configuration files, environment templates, and compose manifests
- `#compose` — Docker Compose configuration and swarm stacks
- `#ritual` — Scheduled backup drills, verification rituais, and integrity checks
- `#checklist` — Validation checklists and migration checklists
### `#recovery` — Disaster Recovery & Contingency Planning
### `#docker` — Docker Engine, Swarm Mode & Container Infrastructure

### Functional Service Domains
- `#media` — Media streaming, audio, and digital reading libraries
- `#download` — Torrents, Usenet, Soulseek, and download pipelines
- `#dns` — Recursive DNS, AdGuard, Pi-hole, and local domain resolution
- `#automation` — IoT automation, Home Assistant, and MQTT brokers
- `#monitoring` — Uptime Kuma, Homepage, Glances, Prometheus, and Grafana
- `#gaming` — Crafty Controller, Steam, Project Zomboid, Valheim, and Minecraft
- `#storage` — Disks, NVMe pools, RAID arrays, mountpoints, and NFS shares
- `#cloud` — Cloud storage, remote providers, and off-site synchronization
- `#rclone` — Rclone storage sync, cloud remotes, and Google Drive mounts
- `#tutorial` — Operational tutorials and step-by-step technical guides
- `#todo` — Work-in-progress, pending improvements, or roadmap tasks
- `#env` — Environment variables, port configurations, and socket bindings
- `#sops` — Centralized secret encryption (SOPS + Age) and credentials store
- `#ssl` — TLS/SSL certificates, reverse proxy termination, and Let's Encrypt
- `#meta` — Metadata tags defining repository governance and structure
- `#taxonomy` — Central taxonomy reference (applied to `_tags.md` itself)
- `#agents` — Instructions, conventions, and constraints for AI agents
- `#steam` — Steam client, Proton, and native Linux gaming optimizations
- `#power` — System power states, ACPI suspend, and hibernation handling (S3/S4)

### `#hardware` — Physical Devices, Peripherals & Media
- `#usb` — USB buses, external drives, flash memory, and flash recorders
- `#fat` — FAT32 / vfat filesystem handling and dirty bit recovery
- `#gpu` — Discrete graphic cards (GPUs) and hardware video acceleration
- `#nvidia` — Proprietary NVIDIA display drivers, CUDA, and cuBLAS runtimes
- `#rebar` — Resizable BAR (ReBAR) memory addressing under Linux

### `#desktop` — Desktop & Workstation Environments
- `#kde` — KDE Plasma desktop session, applets, and system configuration
- `#plasma` — Plasma Shell widgets, system trays, and desktop workarounds

### `#wallpaper` — Wallpaper Collection & Upscaling
- `#wallpaper` — Desktop wallpaper collection, resolution categorization, and AI upscaling
