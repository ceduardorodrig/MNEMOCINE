---
tags: [homelab, server, kururu]
pending: [HB-060]
---

# Kururu — Dedicated Headless Node

Autonomous, ultra-low-power node in the Mnemocine homelab engineered from repurposed **Samsung Galaxy Tab 3 Lite 7.0 (SM-T110)** hardware. Runs pure **Alpine Linux v3.20** in bare-metal headless mode (no Android runtime, zero graphical windowing overhead), functioning as an always-on utility sentinel, Wake-on-LAN relay, and telemetry dashboard.

## Hardware Specifications

| Component | Specification |
|---|---|
| **Chassis / Device** | Samsung Galaxy Tab 3 Lite 7.0 (`SM-T110` / `samsung-goyawifi`) |
| **SoC / Processor** | Marvell PXA986 (Dual-Core ARM Cortex-A9 @ 1.2 GHz) |
| **Architecture** | `armv7l` (ARM 32-bit with NEON / VFPv3) |
| **System Memory** | 1 GB LPDDR2 (~816 MB visible to kernel, **>770 MB free RAM**) |
| **Internal Storage** | 8 GB eMMC v4.5 (5.1 GB ext4 partition `/data` hosting the rootfs) |
| **Wi-Fi** | Marvell SD8777 (802.11 b/g/n, native `sd8xxx` + `mlan` driver) |
| **Power Consumption** | < 0.8W idle (backlight managed directly via `/dev/graphics/fb0`) |
| **Power Source** | Continuously connected Micro-USB cable; battery managed via AXP228 PMIC |

## Software Architecture: Native Headless Linux

1. **Bootloader & Kernel:** Unlocked OEM bootloader initializes Samsung/Marvell Linux 3.4.5 kernel with native radio calibration and direct silicon drivers.
2. **Android Runtime Deactivation:** All Android services (`zygote`, `surfaceflinger`, `system_server`, `media`, `drm`, `bootanim`) are permanently disabled in the custom boot ramdisk (`kururu_headless_boot.img`). The tablet skips JVM initialization entirely, consuming merely 43 MB of RAM on boot.
3. **Userspace Rootfs:** Minimal **Alpine Linux v3.20.3 armv7** environment built on `musl libc`, executing statically linked **Rust** binaries targeting `armv7-unknown-linux-musleabihf`.
4. **Networking:**
   - LAN: Static IP `192.168.3.55/24` on local Wi-Fi.
   - Tailnet: Native `tailscaled` daemon binding `/dev/tun`.
   - SSH: Dropbear SSH server listening on port 22 with Ed25519 key authentication.

## Connectivity

```bash
# Direct local LAN connection
ssh root@192.168.3.55

# Tailscale mesh connection
tailscale ssh root@kururu
```

## Daemons & Telemetry Engine

- **Frame-buffer Telemetry (`kururu-display`):** Native Rust v3.0 telemetry daemon drawing directly to `/dev/graphics/fb0`. Renders three distinct views: Kururu system status, Homelab WoL controls, and a retro phosphor clock. Features pixel-art animations, live battery/UPS telemetry, and full touchscreen navigation.
- **WOL Relay Daemon (`kururu-wake`):** Listens on port 9096 to dispatch L2 magic packets over local broadcast, awakening psicopompo and kavure on demand.
- **Power & Graceful Shutdown Sentinel:** Monitors LAN host heartbeats to execute coordinated shutdowns during extended power outages.

## Boot Persistence

- **Boot Hook:** Executed via `/system/etc/install-recovery.sh` on startup: initializes Wi-Fi (`wpa_supplicant`), Dropbear, `kururu-display`, `kururu-wake`, and `tailscaled`.
- **NTP Time Synchronization:** Due to a non-functional hardware RTC, the boot hook enforces an early NTP sync before initializing network daemons, ensuring accurate log timestamps.

## Known Issues

- **Tailscale netfilter (HB-015, fixed 12/10):** Tailscale's health reported `adding [-i tailscale0 -j MARK …] … MARK revision 0 not supported, missing kernel module` — the Marvell 3.4.5 kernel has **no module tree and no `xt_MARK`**, so the `ts-forward` MARK rule failed. **Fix:** `tailscale set --netfilter-mode=off` (documented — disables Tailscale's netfilter management). Functionally a no-op here (the rule never applied) and it clears the health warning. ⚠️ Tailscale now warns *"configure iptables yourself"* — acceptable for this probe/WoL node (no subnet routing/NAT). Persisted in tailscaled prefs.

## Tailnet Tagging

`kururu` is an **untagged** tailnet device (verified live 2026-10-13). It stays untagged because it is a **probe / Wake-on-LAN node — not a service host**.

> **If you host a service on `kururu`** — a Docker service, any listener, a subnet route, or a Funnel that other tailnet devices must reach — **tag it `tag:server`** (plus any role tag it takes on) **in the same change that introduces the service.** Until then, leave it untagged. The general rule and the tag procedure are in [`guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) §1 and §6.

## DNS (unmapped, 2026-10-13)

`kururu` is **L3-reachable** (`tailscale ping` → `pong … 4 ms`; Dropbear listening on
`192.168.3.55:22`) but the whole-fleet DNS audit has **no administrative path** to it: it runs
**no Tailscale SSH server** (unlike the other nodes) and its Dropbear rejects the audit key (the
only local key is **passphrase-protected** and no agent is loaded). Its resolver topology is
therefore **unmapped** (tracked as **HB-060**).

> **When it becomes reachable:** the fleet's `systemd-resolved` **stub** recipe does **not** apply
> verbatim — `kururu` is **Alpine/musl with no systemd**. The portable target is `CorpDNS=true`
> (Tailscale DNS enabled) with `/etc/resolv.conf` **not** a Tailscale-trampled static file, so the
> libc path and MagicDNS both resolve. Rationale:
> [`../guides/dns-consistency-map.md`](../guides/dns-consistency-map.md) §4.2.

## See Also

- [`servers/kururu-possibilities.md`](kururu-possibilities.md) — 20 roadmap possibilities and architectural roadmap
- [`services/wol-relay.md`](../services/wol-relay.md) — Homelab Wake-on-LAN architecture
- [`guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) — Tailnet tags: the applied map and the rules for future devices
- [GitHub Repository: KURURU-TAB3LITE-LINUX](https://github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX)
