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

> **External drive (HB-001, resolved 12/10):** the `EXPANSION-2TB` (Seagate `ST2000LM007`) was a **USB external** connected for staging; it reported 25,296 reallocated sectors and was flagged by `SmartDiskError`. It is **disconnected** and the owner confirmed it is known/remediated. Current internal disks: `sda`/`sdc` (1 TB HDDs), `sdb` (480 GB SSD), `nvme0n1` (1.8 TB), `nvme1n1` (465 GB).

> **Stray `NVME_PCI/NVME_PCI` directory (HB-024, resolved 12/10):** an **empty** duplicated path `/mnt/NVME_PCI/NVME_PCI/docker-data/volumes/sumaenimahub_umami_data/_data` existed since **2026-09-28**. Root cause: the `SUMAENIMA-HUB` `scripts/deploy-swarm.sh` guard ran `mkdir -p "$NVME_UMAMI"` **inside** a helper container that already mounted the host `/mnt/NVME_PCI` at `/mnt` — so the host path was re-prefixed (doubled) on the host. The directory was **removed** (no container, volume or compose referenced it) and the script now **re-roots** the path (`$NVME_REL`).

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
| steniorec | `sumaenima-server:cuda` | `127.0.0.1:9090` + `100.82.51.112:9090` | Whisper transcription daemon in Rust + CUDA |
| comfyui | `obeliks/comfyui:master-cu130` | `127.0.0.1:8188` + `100.82.51.112:8188` | Diffusion image generation (batch GPU consumer, started on demand under an `image_gen` lease) |
| registry | `registry:3` | `127.0.0.1:5000` + `100.82.51.112:5000` | Private TLS-authenticated image registry for cluster deployment |
| promtail | `grafana/promtail` | `127.0.0.1:9080` (health) | Log scraping agent forwarding to Loki on kavure |
| node-exporter | `prom/node-exporter` | `100.82.51.112:9100` | System metrics collection for Prometheus |
| glances | `nicolargo/glances:latest` | `127.0.0.1:61208` + `100.82.51.112:61208` | Resource monitoring |
| dockerproxy | `tecnativa/docker-socket-proxy:latest` | `127.0.0.1:2375` + `100.82.51.112:2375` | Secure socket gateway for Homepage |
| watchtower | `containrrr/watchtower:latest` | — | Automated container image updater |
| autoheal | `willfarrell/autoheal:latest` | — | Restarts unhealthy containers automatically |

> **Correction (2026-10-13):** `comfyui` was missing from this table and the bind cells for
> `glances` / `dockerproxy` claimed `0.0.0.0`. Verified live (`docker ps` + `ss -tlnp`): both bind
> **loopback + the Tailscale IP** only, and the node's full container set is exactly
> `steniorec`, `comfyui`, `registry`, `promtail`, `node-exporter`, `glances`, `dockerproxy`,
> `watchtower`, `autoheal`.

### Native & User Services (no container)

| Service | How | Port(s) + bind | Purpose |
|---|---|---|---|
| `hl-infer` | native systemd | `127.0.0.1:9095` + `100.82.51.112:9095` | Centralized GPU inference gateway (VRAM leases, fixed windows) — see [`services/hl-infer.md`](../services/hl-infer.md) |
| `ollama` | native systemd | `127.0.0.1:11434` + `100.82.51.112:11434` (`ollama-tailnet` kernel forwarder) | Local LLM runtime (leased through `hl-infer`); the forwarder gives the autopilot on **kavure** the local fallback without leaving loopback. Re-enabled 2026-10-19 (it had been stopped since 13:05) |
| `sumaenima-gpu` | native systemd | — | GPU worker supervisor (Rust) that boot-orders and revives `steniorec` |
| `libvirtd` + `dnsmasq` | native systemd | `192.168.122.1:53` (`virbr0`) | KVM hypervisor + NAT DNS/DHCP for the isolated guest network |
| `waydroid-container` | native systemd | — | Android-in-container runtime |
| `nfsd` / `rpcbind` / `rpc.mountd` | native systemd | `100.82.51.112:2049`, `111`, `20048` | NFSv4 NAS exports (`/mnt/BACKUP`) |
| `hl-wol-relay` | native systemd | `127.0.0.1:9096` + `tailscale serve` | Wake-on-LAN relay (wakes kavure) |
| `syncthing` | **user** systemd (`edu`) | `127.0.0.1:8384` + tailnet `8384` + `22000` | Vault P2P synchronization |
| `punktfunk-host` | **user** systemd (`edu`) | `0.0.0.0:47990` (ufw-scoped) + `9777/udp` | Low-latency game/desktop streaming host |
| `punktfunk-web` | **user** systemd (`edu`) | `0.0.0.0:47992` (ufw-scoped) | Punktfunk management web console |
| `punktfunk-scripting` | **user** systemd (`edu`) | `0.0.0.0:47993` (ufw-scoped) | Punktfunk plugin/script runner |

> **Autopilot moved (2026-10-19, HB-076):** the social-media engine's four timers now run on
> `kavure`. psicopompo remains the **dev/build host** and the **GPU fallback** (`hl-infer` + the
> `ollama-tailnet` forwarder). See [`../services/autopilot.md`](../services/autopilot.md).

> **Note on `live-restore`:** Strictly removed from `daemon.json` on 2026-10-02 due to fundamental incompatibility with Docker Swarm mode. See [`AGENTS.md`](../AGENTS.md).

## Pacman Mirrors & Package Management Policy (2026-10-26)

- **Root Cause & Diagnosis:**
  - `cachyos-rate-mirrors` ranks mirrors purely by ping/speed using a small test file. For Brazilian connections, it places `cdn77.cachyos.org` at #1 due to its São Paulo edge (POP).
  - However, CDN77 suffers from known upstream sync lags and URL normalization bugs on `.sig` signature files containing special characters such as `+` (e.g. `gcc-16.2.1+r23...`), returning **HTTP 404**.
  - Subsequent mirrors ranked as fallback (e.g. `mirror.krfoss.org`) triggered Cloudflare Bot Challenges (**HTTP 403 Forbidden**), causing `pacman` to abort the transaction.
  - The background timer `cachyos-rate-mirrors.timer` was running weekly, periodically overwriting manual fixes and reintroducing the broken order.

- **Canonical Configuration Applied:**
  - **Mirrorlists:** `/etc/pacman.d/cachyos-mirrorlist` and `/etc/pacman.d/cachyos-v3-mirrorlist` (backups at `*.bak`).
  - **Tier-1 Primary Mirrors (Cloudflare Anycast, ~20ms in SP, instant upstream build sync):**
    ```ini
    Server = https://us.cachyos.org/repo/$arch_v3/$repo
    Server = https://at.cachyos.org/repo/$arch_v3/$repo
    ```
  - **Systemd Masking:**
    ```bash
    sudo systemctl stop cachyos-rate-mirrors.timer
    sudo systemctl mask cachyos-rate-mirrors.timer
    sudo systemctl mask cachyos-rate-mirrors.service
    ```

- **Operational Rules:**
  - Avoid running `rate-mirrors cachyos` or clicking "Rank Mirrors" in CachyOS Hello during routine maintenance.
  - If unmasking is ever required: `sudo systemctl unmask cachyos-rate-mirrors.timer && sudo systemctl enable --now cachyos-rate-mirrors.timer`.

## See Also

- [`servers/psicopompo-gaming.md`](psicopompo-gaming.md) — Steam on Linux gaming guide
- [`guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md) — Wayland desktop environment manual
- [`network/nfs.md`](../network/nfs.md) — NFSv4 storage exports
