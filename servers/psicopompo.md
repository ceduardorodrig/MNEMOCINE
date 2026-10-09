---
tags: [homelab, server, psicopompo, gaming, docker, storage, power, gpu, nvidia, rebar]
---

# psicopompo

**Role:** Primary host — physical local workstation and build node  
**Default Shell:** fish (`/bin/fish`) — zsh and bash also available  

## Hardware Specifications

| Component | Specification |
|---|---|
| **OS** | CachyOS Linux (Arch-based rolling distribution) |
| **Kernel** | 7.0.11-1-cachyos-bore |
| **CPU** | Intel Xeon E-2246G @ 3.60 GHz — 6C/12T |
| **GPU** | NVIDIA GeForce RTX 5050 |
| **RAM** | 46 GB (ZRAM: 46.9 GB zstd compressed RAM) |
| **OS Disk** | 462 GB NVMe (Kingston NV3) — `/dev/nvme1n1p2` |
| **PCIe Work Disk** | 1.8 TB NVMe (Kingston NV2) — `/mnt/NVME_PCI` — Btrfs array |
| **SATA SSD** | 448 GB (Kingston A400) — `/mnt/SSD_SATA` |
| **Scryfall Mirror SSD** | `/mnt/SSD_SATA/scryfall-mirror` — Bulk JSON and high-res card cache for Arandu, exported via NFS to kavure |
| **SATA HDD** | 932 GB (Seagate 1 TB) — `/mnt/HDD_SATA` (Btrfs) |
| **SATA HDD (Backup)** | 932 GB (1 TB) — `/mnt/BACKUP` (Btrfs NAS root) |
| **MicroSD** | 116 GB — `/dev/sdd1` — exFAT |
| **Swap** | 46.9 GB pure ZRAM (zstd, priority 100) — zero disk swap wear |
| **Tailscale IP** | 100.82.51.112 |
| **Tailscale DNS** | psicopompo.chimaera-heptatonic.ts.net |
| **Network** | Intel I219-LM Gigabit Ethernet |
| **MTU (PPPoE)** | **1492** (NetworkManager) configured 2026-10-07 to eliminate MTU mismatch drops across WAN |

## GPU / NVIDIA Architecture — ReBAR & DDC/CI

> **GPU:** NVIDIA GeForce RTX 5050 (proprietary driver). The Dell OEM BIOS disables ReBAR toggle, but the Linux kernel enforces it dynamically.

### Resizable BAR (ReBAR) Implementation
- **Kernel Command Line Activation:** `nvidia.NVreg_EnableResizableBar=1` in `/etc/default/limine` → regenerates `limine.conf` across boot targets.
- **Verification Commands:**
  - `grep EnableResizableBar /proc/driver/nvidia/params` $\rightarrow$ reports `1`
  - `lspci -vvv -s 01:00.0` $\rightarrow$ reports `Region 1: Memory at ... [size=8G]` (64-bit prefetchable)

### Audio Pipeline: GB207 HDMI Audio Disablement
The NVIDIA proprietary driver spawns 6 duplicate HDMI audio sinks for a single display. WirePlumber disables the redundant GB207 controller via `~/.config/wireplumber/wireplumber.conf.d/51-disable-gb207.conf` (`device.disabled = true` on `alsa_card.pci-0000_01_00.1`), preserving built-in analog audio, Bluetooth headphones, and Punktfunk virtual outputs.

## Primary Roles & Services

- **Tailnet NAS (NFSv4):** Exports `/mnt/BACKUP/media/music` and `/media/books` + `/mnt/BACKUP/sumaenima-server-kavure` to kuaray and kavure (see [`network/nfs.md`](../network/nfs.md)).
- **Workstation & Gaming Host:** Hyprland Wayland environment with native scrolling layout; games executed locally; dedicated multiplayer servers offloaded to kavure.
- **Sumænimá GPU Inference & Build Node:** Runs local AI transcription (`steniorec` with Whisper in Rust + CUDA) and standalone GPU vision/audio services. Sole authorized container build node.

## Maximum Performance & Energy Configuration (2026-10-03)

- **PCIe Maximum Throughput:** Power management locked at maximum throughput (`pcie_aspm=off pci=noaer`), eliminating PCIe state transition latency during CUDA and 3D rendering.
- **ACPI Sleep States Disabled:** Hardware quirks in Dell Precision 3630 PCH thermal sensors prompted disabling S3 and S4 states in systemd (`AllowSuspend=no`, `AllowHibernation=no`). Host operates via 8-second fast boots and graceful clean power-offs.
- **Disk Swap Eliminated:** `/swap/swapfile` purged (+48 GB free space); memory swap handled entirely in RAM via ZRAM.

## Wake-on-LAN Verification (2026-10-02)

The host awakens from S5 power-off via magic packets dispatched by kavure or kururu within 54 seconds. Configuration persisted via NetworkManager (`802-3-ethernet.wake-on-lan magic`) and `wol@eno1`. Local WOL relay operates on `127.0.0.1:9096` exposed across the Tailnet via `tailscale serve`.

## Docker Swarm — GPU Worker Role

Operates as a Swarm worker (`role=gpu`) attached to the `sae-net` overlay network orchestrated by kavure (Swarm Manager).

| Container | Image | Ports | Responsibility |
|---|---|---|---|
| steniorec | `sumaenima-server:cuda` | `127.0.0.1:9090` / `100.82.51.112:9090` | Whisper transcription daemon in Rust + CUDA |
| registry | `registry:3` | `100.82.51.112:5000` + `127.0.0.1:5000` | Private TLS-authenticated image registry for cluster deployment |
| promtail | `grafana/promtail` | — | Log scraping agent forwarding to Loki on kavure |
| node-exporter | `prom/node-exporter` | — | System metrics collection for Prometheus |
| glances | `nicolargo/glances:latest` | `0.0.0.0:61208` | Resource monitoring |
| dockerproxy | `tecnativa/docker-socket-proxy:latest` | `0.0.0.0:2375` | Secure socket gateway for Homepage |
| watchtower | `containrrr/watchtower:latest` | — | Automated container image updater |
| autoheal | `willfarrell/autoheal:latest` | — | Restarts unhealthy containers automatically |

> **Note on `live-restore`:** Strictly removed from `daemon.json` on 2026-10-02 due to fundamental incompatibility with Docker Swarm mode. See [`AGENTS.md`](../AGENTS.md).

## See Also

- [`servers/psicopompo-gaming.md`](psicopompo-gaming.md) — Steam on Linux gaming guide
- [`guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md) — Wayland desktop environment manual
- [`network/nfs.md`](../network/nfs.md) — NFSv4 storage exports
