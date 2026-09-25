---
tags: [homelab, meta]
---

# Open-Source Acknowledgments — Homelab Mnemocine

The Mnemocine Homelab infrastructure is operated on the basis of open-source projects and technologies maintained by the global community. We thank and acknowledge the following fundamental components that underpin our servers and services:

## Operating Systems, Storage & Kernel

- **[CachyOS](https://cachyos.org/)** / **[Arch Linux](https://archlinux.org/)** (GPL) — Operating system with BORE/EEVDF kernel optimized with x86-64-v3/v4 builds for the primary node `psicopompo`
- **[Ubuntu Server](https://ubuntu.com/)** (GPL) — Base distribution for the edge nodes and services (`kavure`, `ybytu`, `ybyra`)
- **[Linux Mint](https://linuxmint.com/)** (GPL) — Desktop/server distribution used on the standby node `kuaray` (version 22.3 Zena)
- **[Btrfs](https://btrfs.readthedocs.io/)** (GPL) — Filesystem with copy-on-write snapshots and zstd compression
- **[Snapper](http://snapper.io/)** (GPL-2.0) — Automated management of pre/post-transaction btrfs snapshots
- **[Restic](https://restic.net/)** (BSD-2-Clause) — Encrypted and deduplicated backup for NAS storage
- **[NFSv4](https://datatracker.ietf.org/doc/html/rfc7530)** (IETF Standard) — Network file sharing protocol with resilient soft mounts

## Network, Security & Cryptography

- **[Tailscale](https://tailscale.com/)** (BSD-3-Clause) — Secure WireGuard mesh connecting all nodes, exit nodes and funnels
- **[AdGuard Home](https://adguard.com/adguard-home.html)** (GPLv3) & **[Pi-hole](https://pi-hole.net/)** (EUPL) — Local recursive DNS servers with ad and tracker blocking
- **[SOPS](https://github.com/getsops/sops)** (MPL-2.0) & **[Age](https://github.com/FiloSottile/age)** (BSD-3-Clause) — Centralized secret and environment variable encryption
- **[Nginx](https://nginx.org/)** (2-Clause BSD) — Reverse proxy and TLS termination
- **[Syncthing](https://syncthing.net/)** (MPL-2.0) — Decentralized data synchronization between psicopompo, kuaray and mobile devices

## Containerization & Active Services

- **[Docker & Docker Compose](https://www.docker.com/)** (Apache 2.0) — Execution and orchestration of microservices in containers
- **[Home Assistant](https://www.home-assistant.io/)** (Apache 2.0) — Home automation platform
- **[Navidrome](https://www.navidrome.org/)** (GPLv3) — Personal music server and streamer
- **[Calibre-Web](https://github.com/janeczku/calibre-web)** (GPLv3) — eBook collection reader and manager
- **[Prowlarr](https://prowlarr.com/)**, **[Lidarr](https://lidarr.audio/)**, **[Transmission](https://transmissionbt.com/)** (GPL) — Multimedia management and indexing
- **[Homepage](https://gethomepage.dev/)** (GPLv3) — Visual panel and dashboard for the homelab
- **[SearXNG](https://github.com/searxng/searxng)** (AGPLv3) — Privacy-focused metasearch engine
- **[ChangeDetection.io](https://changedetection.io/)** (Apache 2.0) — Automated change monitoring on the web
- **[Watchtower](https://containrrr.dev/watchtower/)** (Apache 2.0) — Controlled container updates

## Terminal Tools & Rust Linters

The homelab follows the mandatory policy of high-performance Rust tools in the terminal:
- **`eza`** (GPL-3.0) — Modern alternative to `ls`
- **`bat`** (Apache-2.0 / MIT) — File reading with syntax highlight
- **`ripgrep` (`rg`)** (Unlicense / MIT) — Ultrafast recursive text search
- **`fd`** (Apache-2.0 / MIT) — File and directory search
- **`sd`** (MIT) — Intuitive text replacement
- **`delta`** (MIT) — Diff and commit viewer
- **`dust`** (Apache-2.0) & **`duf`** (MIT) — Space and disk usage analysis
- **`xh`** (MIT) — Friendly HTTP client
- **`bottom` (`btm`)** (MIT) & **`procs`** (MIT) — Process and resource monitor
- **[StenioSentinel](https://github.com/ceduardorodrig/STENIO-SENTINEL)** (Proprietary / MIT) — Universal static governance and infrastructure engine

## Retired Services and Technologies

We document the discontinued homelab services for traceability purposes:
- *Kavita* (retired from the reading stack)
- *Duplicati* (replaced by the Restic + Snapper + Btrfs chain)
- *Legacy steniocheck Python scripts on ybyra* (replaced by the native Rust StenioSentinel)
