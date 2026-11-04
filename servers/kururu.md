---
tags: [homelab, server, kururu]
pending: [HB-105]
---

# Kururu — Dedicated Headless Node

Autonomous, ultra-low-power node in the Mnemocine homelab engineered from repurposed **Samsung Galaxy Tab 3 Lite 7.0 (SM-T110)** hardware. Runs pure **Alpine Linux v3.20** in bare-metal headless mode (no Android runtime, zero graphical windowing overhead), functioning as an always-on utility sentinel, Wake-on-LAN relay, and telemetry dashboard.

## Hardware Specifications (verified 2026-11-03)

| Component | Specification |
|---|---|
| **Chassis / Device** | Samsung Galaxy Tab 3 Lite 7.0 (`SM-T110` / `samsung-goyawifi`) |
| **SoC / Processor** | Marvell PXA986 (Dual-Core ARM Cortex-A9 @ 1.2 GHz) |
| **Architecture** | `armv7l` (ARM 32-bit with NEON / VFPv3) |
| **System Memory** | 1 GB LPDDR2 (~816 MB visible to kernel, **>770 MB free RAM**) |
| **Internal Storage** | 8 GB eMMC v4.5 (5.1 GB ext4 partition `/data` hosting the rootfs) |
| **Wi-Fi** | Marvell SD8777 (802.11 b/g/n, native `sd8xxx` + `mlan` driver) |
| **Power Consumption** | < 0.8W idle (backlight managed directly via `/dev/graphics/fb0`) |
| **Power Source** | Continuously connected Micro-USB cable; battery managed via **Summit SMB327/SMB328** switch-mode charger (`6-0034`, `sec-charger`) + **Marvell 88PM822** fuelgauge/PMIC (`2-0030`, `sec-fuelgauge`) |

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
# Canonical Tailscale mesh connection (Dropbear on 100.127.188.45:22 via ~/.ssh/kururu_agent_ed25519)
ssh kururu
ssh root@100.127.188.45

# Restore ~/.ssh/kururu_agent_ed25519 from SOPS (KURURU_SSH_PRIVATE_KEY_B64) on a fresh host/session
./scripts/kururu-unlock.sh --check
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

## DNS & Tailnet Data Path (mapped & verified 2026-11-03 — HB-060, HB-106, HB-107 resolved)

- **Tailnet data path restored (`HB-106`, resolved 2026-11-03):**
  - **Root cause 1 (Tailscale ACL PacketFilter):** `psicopompo` carries `tag:server` while `kururu` (`100.127.188.45`) is untagged (`autogroup:member`). After Phase 3 (`HB-049`) removed the allow-all rule on 2026-10-13, `tag:server` only had grants to `autogroup:member` on `tcp:9096` (WoL) and `tcp/udp:1716` (KDE Connect), so `kururu`'s inbound `tailscaled` `PacketFilter` silently dropped `100.82.51.112 -> 100.127.188.45:22` (the regression was **not** caused by `ufw` or `--netfilter-mode=off`). Fixed in `MNEMOCINE-ACL` PR [#17](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/17) (`dff00a6`), granting `tag:server -> 100.127.188.45` on `tcp:22` and pinning `"100.127.188.45:22"` in ACL CI tests.
  - **Root cause 2 (`tailscaled --ssh` intercept):** `/system/etc/install-recovery.sh` started `tailscale up --hostname=kururu --ssh --accept-routes=false`, causing `tailscaled` to intercept TCP/22 in userspace and reject `tag:server` connections before they reached Dropbear (`0.0.0.0:22`). Fixed live (`tailscale set --ssh=false`) and persisted in `/system/etc/install-recovery.sh` (`92d82f9` in `KURURU-TAB3LITE-LINUX`).
- **Dedicated automation SSH credential (`HB-107`, resolved 2026-11-03):**
  - Provisioned dedicated passwordless automation key `~/.ssh/kururu_agent_ed25519` (`SHA256:H/cFnGUejM81bsBMXeetaHibQCib74Mpg+NfrOdinJY kururu-agent@psicopompo`), authorized in `/root/.ssh/authorized_keys` on `kururu`, wired in `~/.ssh/config` (`Host kururu 100.127.188.45`), and stored encrypted as `KURURU_SSH_PRIVATE_KEY_B64` in `mnemocine/secrets.enc.env` (and synced to `/mnt/NVME_PCI/secrets/secrets.env`). `scripts/kururu-unlock.sh` restores the key directly from SOPS with zero human interaction.
- **Resolver topology (`HB-060`, resolved 2026-11-03):**
  - `kururu` is Alpine/musl with no `systemd-resolved`; `/etc/resolv.conf` points directly at `100.100.100.100` (`fd7a:115c:a1e0::53`, `search chimaera-heptatonic.ts.net`) with `Tailscale DNS: enabled` (`CorpDNS=true`), forwarding in parallel to `100.115.253.109` (AdGuard/ybytu) and `100.124.146.77` (Pi-hole/kavure).
  - Verified live over the tailnet: `getent hosts doubleclick.net` → `::` (`nslookup` → `0.0.0.0`), `getent hosts kavure.chimaera-heptatonic.ts.net` → `100.124.146.77`, `getent hosts psicopompo.chimaera-heptatonic.ts.net` → `100.82.51.112`. See [`../guides/dns-consistency-map.md`](../guides/dns-consistency-map.md) §4.2.

## Battery charge cap — 4.14 V (~90 %), implemented 2026-11-03 (HB-105)

**Why:** the tablet runs continuously on Micro-USB, so under the stock board config (`chg_float_voltage = 4330` mV, reg `0x02 = 0x56`) the cell rests at ~4.31–4.32 V (100 %) — the worst case for Li-ion **calendar** ageing. Calendar data (KIT / *Batteries* 2021, graphite-NCA) puts the cliff at 100 % (≈20–40 % capacity loss within months at 40 °C) while 90 % and 80 % both sit in the 1–5 % band.

**Why ~90 % (4.14 V) and not 85 %:** `kururu` is the *power guardian* (WoL sender + coordinated shutdown), so its battery is the guardian's own UPS. Usable window to the sentinel's 20 % veto is ≈13 h from 100 %, ≈12 h from 90 %, ≈11 h from 85 %.

**Actual silicon on `SM-T110` (`samsung-goyawifi`):**
- Contrary to earlier assumptions, `kururu` does **not** have an `axp20x` PMIC and `voltage_max` is not exposed in sysfs.
- The charger IC is a **Summit Microelectronics SMB327 / SMB328** on I2C `6-0034` (`drivers/battery/smb328_charger.c`, exposed at `/sys/class/power_supply/sec-charger/{reg,data,regs}`), paired with a **Marvell 88PM822** fuelgauge/PMIC on I2C `2-0030` (`sec-fuelgauge`).
- **Register formula (`smb328_charger.c` lines 183–195):** Register `0x02` (`SMB327_FLOAT_VOLTAGE`), bits `6:1` (`CFG_FLOAT_VOLTAGE_MASK = 0x7E`), sets the Constant-Voltage (CV) float termination ceiling in **20 mV steps** from 3500 mV:
  - Stock ceiling: `0x56` (`4320–4330 mV`).
  - **Capped ceiling (`0x42` = 4.14 V / `4140 mV`):** the closest discrete step on the SMB327 20 mV ladder to the owner's 4.15 V decision.
- **Why register `0x02` and NOT `batt_slate_mode`:** writing `1` to `/sys/class/power_supply/battery/batt_slate_mode` turns off USB input/charging and sets `ac/online = 0` (`status = Discharging`), which would falsely trigger `kururu-sentinel`'s `CableFault` / `BlackoutPending` state machine. Capping `SMB327_FLOAT_VOLTAGE` (`0x02 = 0x42`) keeps `ac/online = 1` (`AcNormal`) so USB mains powers the 0.8 W system load continuously while the Li-ion cell relaxes to 4.14 V (~88–90 %) without charge/discharge cycling.

### Implementation & Persistence (`92d82f9` in `KURURU-TAB3LITE-LINUX`)

1. **Boot hook (`/system/etc/install-recovery.sh`):** writes `02` to `/sys/class/power_supply/sec-charger/reg` and `42` to `/sys/class/power_supply/sec-charger/data` at boot, and launches `/usr/local/bin/kururu-sentinel` inside the Alpine chroot.
2. **Self-healing daemon (`kururu-sentinel` v1.2, `enforce_charger_float_voltage_cap()`):** because `smb327_charger_function_control()` re-writes `pdata->chg_float_voltage` (`0x56`) to register `0x02` if a charger watchdog or cable event occurs, `kururu-sentinel` checks `/sys/class/power_supply/sec-charger/{reg,data}` every 5 seconds while `ac/online == 1` and immediately heals `0x02` back to `0x42` (verified live: `[BATTERY-CAP] Applied SMB327 float voltage cap 4.14V (reg 0x02: 0x56 -> 0x42)`).

```sh
# Inspect live SMB327 float voltage register (expect 42) and cell voltage
ssh kururu 'echo 2 > /sys/class/power_supply/sec-charger/reg; cat /sys/class/power_supply/sec-charger/data /sys/class/power_supply/battery/voltage_now /sys/class/power_supply/battery/capacity /sys/class/power_supply/battery/status'
```

**Rollback:** stop `kururu-sentinel` (or set `SMB327_FLOAT_VOLTAGE_CAP = 0x56`), run `echo 02 > /sys/class/power_supply/sec-charger/reg && echo 56 > /sys/class/power_supply/sec-charger/data`, and remove the `02`/`42` block from `/system/etc/install-recovery.sh`.

**Acceptance test (remaining in `HB-105`):** once the cell finishes relaxing to the 4.14 V ceiling, run an unplugged discharge test and record the time to the 20 % veto; if it drops below the desired outage profile, step back to `0x4c` (4.24 V) or `0x56` (4.33 V).

## See Also

- [`servers/kururu-possibilities.md`](kururu-possibilities.md) — 20 roadmap possibilities and architectural roadmap
- [`services/wol-relay.md`](../services/wol-relay.md) — Homelab Wake-on-LAN architecture
- [`guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) — Tailnet tags: the applied map and the rules for future devices
- [GitHub Repository: KURURU-TAB3LITE-LINUX](https://github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX)
