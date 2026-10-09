---
tags: [homelab, meta]
---

# Open-Source Acknowledgments — Mnemocine Homelab

The Mnemocine Homelab infrastructure is powered by open-source projects and technologies maintained by the global developer community. We gratefully acknowledge the foundational open-source components supporting our servers and services:

## Operating Systems, Storage & Kernel

- **[CachyOS](https://cachyos.org/)** / **[Arch Linux](https://archlinux.org/)** (GPL) — Operating system with optimized BORE/EEVDF kernel built with x86-64-v3/v4 instruction sets for the primary node `psicopompo`.
- **[Ubuntu Server](https://ubuntu.com/)** (GPL) — Base distribution for edge and dedicated service nodes (`kavure`, `ybytu`, `ybyra`).
- **[Linux Mint](https://linuxmint.com/)** (GPL) — Desktop/server distribution utilized on the standby archive node `kuaray` (version 22.3 Zena).
- **[Btrfs](https://btrfs.readthedocs.io/)** (GPL) — Copy-on-write filesystem featuring subvolume snapshots and transparent zstd compression.
- **[Snapper](http://snapper.io/)** (GPL-2.0) — Automated Btrfs snapshot management pre/post package transactions and system upgrades.
- **[Restic](https://restic.net/)** (BSD-2-Clause) — Secure, deduplicated, and encrypted backup solution targeting NAS storage.
- **[NFSv4](https://datatracker.ietf.org/doc/html/rfc7530)** (IETF Standard) — Network file sharing protocol configured with resilient soft-mount parameters.

## Networking, Security & Cryptography

- **[Tailscale](https://tailscale.com/)** (BSD-3-Clause) — WireGuard mesh overlay interconnecting all bare-metal nodes, exit nodes, and Funnel gateways.
- **[AdGuard Home](https://adguard.com/adguard-home.html)** (GPLv3) & **[Pi-hole](https://pi-hole.net/)** (EUPL) — Local recursive DNS resolvers with network-wide ad blocking and telemetry sinkholing.
- **[SOPS](https://github.com/getsops/sops)** (MPL-2.0) & **[Age](https://github.com/FiloSottile/age)** (BSD-3-Clause) — Centralized secret encryption and encrypted environment variables store.
- **[Nginx](https://nginx.org/)** (2-Clause BSD) — High-performance reverse proxy and TLS termination gateway.
- **[Syncthing](https://syncthing.net/)** (MPL-2.0) — Decentralized, peer-to-peer file synchronization between workstations, nodes, and mobile devices.

## Containerization & Active Services

- **[Docker & Docker Compose](https://www.docker.com/)** (Apache 2.0) — Microservice container runtime, multi-container orchestration, and Swarm clustering.
- **[Home Assistant](https://www.home-assistant.io/)** (Apache 2.0) — Local-first home automation and telemetry platform.
- **[Navidrome](https://www.navidrome.org/)** (GPLv3) — Personal music streaming server compatible with Subsonic clients.
- **[Calibre-Web](https://github.com/janeczku/calibre-web)** (GPLv3) — Clean web reader and eBook library management interface.
- **[Prowlarr](https://prowlarr.com/)**, **[Lidarr](https://lidarr.audio/)**, **[Transmission](https://transmissionbt.com/)** (GPL) — Multimedia indexing, download management, and media pipeline automation.
- **[Homepage](https://gethomepage.dev/)** (GPLv3) — Fast, unified homelab dashboard integrating service health and Docker socket telemetry.
- **[SearXNG](https://github.com/searxng/searxng)** (AGPLv3) — Privacy-respecting metasearch engine.
- **[ChangeDetection.io](https://changedetection.io/)** (Apache 2.0) — Automated website change detection and notification platform.
- **[Watchtower](https://containrrr.dev/watchtower/)** (Apache 2.0) — Controlled automated updates for standalone Docker containers.

## Terminal Tools & Rust Linters

The homelab strictly enforces modern, native Rust high-performance CLI utilities:
- **`eza`** (GPL-3.0) — Modern, feature-rich replacement for `ls`.
- **`bat`** (Apache-2.0 / MIT) — Syntax-highlighted viewer replacement for `cat`.
- **`ripgrep` (`rg`)** (Unlicense / MIT) — Ultra-fast recursive code and text searching tool.
- **`fd`** (Apache-2.0 / MIT) — User-friendly, fast alternative to `find`.
- **`sd`** (MIT) — Intuitive search-and-replace CLI tool.
- **`delta`** (MIT) — Syntax-highlighting pager for git and diff inspection.
- **`dust`** (Apache-2.0) & **`duf`** (MIT) — Visual disk space utilization and disk monitoring tools.
- **`xh`** (MIT) — Fast and ergonomic HTTP client.
- **`bottom` (`btm`)** (MIT) & **`procs`** (MIT) — Graphical process and system resource monitors.
- **[StenioSentinel](https://github.com/ceduardorodrig/STENIO-SENTINEL)** (Proprietary / MIT) — Native Rust architectural governance sentinel and static verification engine.

## Decommissioned Services & Historical Notes

Retained for traceability across historical backup and migration runbooks:
- *Kavita* (decommissioned from the reading stack).
- *Duplicati* (replaced by the modern Restic + Snapper + Btrfs pipeline).
- *Legacy Python steniocheck scripts on ybyra* (replaced by native Rust StenioSentinel).
