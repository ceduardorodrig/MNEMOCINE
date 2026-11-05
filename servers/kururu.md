---
tags: [homelab, server, kururu]
pending: []
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
| **Power Consumption** | < 0.8 W idle by design; **≈0.68 W measured** over a 14 h discharge (2026-11-04) — backlight managed directly via `/dev/graphics/fb0` |
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

**Why ~90 % (4.14 V) and not 85 %:** `kururu` is the *power guardian* (WoL sender + coordinated shutdown), so its battery is the guardian's own UPS. The autonomy estimate that drove the decision was ≈13 h from 100 % to the 20 % veto, ≈12 h from 90 %, ≈11 h from 85 %.

**Measured on 2026-11-03/04 — the estimate was pessimistic.** Discharge test: 420 samples every 120 s over the tailnet, sentinel stopped for the duration (its 20 % veto would otherwise trigger a homelab shutdown), stop at ≤25 %.

| Metric | Value |
|---|---|
| Window | 18:41:31 (97 %) → 08:41:37 (25 %), **14.00 h** |
| Rate | **5.14 points/h** (4.71 in the first 7 h, 5.57 in the second — gentle acceleration, no cliff down to 25 %) |
| Mean draw | **≈0.68 W** (72 % of ~13.3 Wh over 14 h) — consistent with the <0.8 W design figure, so the doc's "<0.8 W" was an upper bound, not the operating point |
| Extrapolated 100 → 20 % | **≈15.6 h** of guardian window |
| Cell voltage | 4.220 V at start → **3.724 V at 25 %** (never in deep-discharge territory) |
| Connectivity | **0 unreachable samples in 420** — Wi-Fi and Tailscale held for 14 h on battery |

**Consequence for the decision:** the 4.14 V cap does not cost operational autonomy. The guardian's usable window (≈15.6 h) is *larger* than the ≈13 h the plan assumed, because the real draw is ~0.68 W rather than 0.8 W. The trade recorded when choosing 90 % over 85 % held, and the measured cost of leaving 100 % is nil.


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

### Operating the daemon (there is no service manager)

The chroot has **no `init.d` and no systemd**: the daemon is launched by the Android boot hook, and a manual restart happens from a bare shell.

**Where the log lives (v1.3, 2026-11-04).** `log_event()` resolves **one** path once at startup and prints it as the last line of the banner — read that line, never assume. Candidates are `/data/kururu-sentinel.log` (chosen, because `/data` exists in the chroot) and `/var/log/kururu-sentinel.log` (fallback). Before v1.3 the loop broke at the first writable candidate **silently**, so `/var/log/kururu-sentinel.log` froze on 2026-10-05 with 466 bytes while the live log sat in `/data` — a whole session concluded the guardian was silent while it logged every 60 s (HB-108). The file rotates at **2 MiB keeping 3 generations** (`.1` … `.3`); before that it grew unbounded (9.6 MB in 30 days on an 8 GB eMMC).

**Fleet heartbeat (v1.3).** Every 5 minutes the daemon POSTs one line to the fleet's ntfy topic (`/alerts` on ybytu): `kururu guardian: state=… ac=… bat=…% float_reg_0x02=… debit=…s`. The guardian reports **in**, so silence is the alarm — nothing polls it. Push failures are logged and swallowed; a broken network never takes the guardian down.

```sh
# Restart. The binary owns its log: redirecting stdout to the same file duplicates every line.
killall kururu-sentinel 2>/dev/null; sleep 1
nohup /usr/local/bin/kururu-sentinel >/dev/null 2>&1 &
sleep 3; tail -3 /data/kururu-sentinel.log     # banner + "Logging to …", HEARTBEAT within 60 s
```

- **A running pid proves nothing.** Check the file that is actually written (`/data/...`) and its freshness, not `pidof`.

**Toolset (provisioned 2026-11-04).** The chroot shipped with **no** Rust tools and no `git`: `eza`,
`rg`, `fd`, `bat`, `sd`, `dust`, `procs` and `btm` were all absent, so an agent following the fleet's
Rust-first rule could not run a single listing — the failure showed up as `sh: eza: not found` at the
end of a deploy. `scripts/provision-rootfs.sh` installs the eight from the official Alpine 3.20
community index and is idempotent; run it after any reflash, streamed rather than copied:

```sh
ssh kururu 'sh -s' < scripts/provision-rootfs.sh
```

`git-delta` and `duf` have no package in that index (checked 2026-11-04). `duf` is **Go**, so it
cross-compiles in one command and was installed as a static 5.6 MB binary:

```sh
GOOS=linux GOARCH=arm GOARM=7 go install github.com/muesli/duf@latest
ssh kururu 'cat > /usr/bin/duf.new' < "$(go env GOPATH)/bin/linux_arm/duf"
ssh kururu 'chmod 755 /usr/bin/duf.new && mv /usr/bin/duf.new /usr/bin/duf'
```

**Install tools in `/usr/bin`, never `/usr/local/bin`:** non-interactive sessions here get
`PATH=/usr/sbin:/usr/bin:/sbin:/bin`, so a binary in `/usr/local/bin` reads as `not found` even with the
file sitting there — that is what the first `duf` attempt looked like.

`git-delta` is Rust but pulls `libz-sys` and `onig_sys` (C), so it needs a C compiler for the musl
target — there is none, and `zig cc` is the toolchain. **Installed 2026-11-04: `delta 0.20.1`, 8.0 MB,**
built with the three wrappers in `scripts/zig-armv7-musl-{cc,cxx,ar}.sh` (cargo injects a Rust triple
zig rejects, and `AR_<target>` cannot hold a space) and **`LINKER=rust-lld`** — letting zig link gives
`duplicate symbol: _start`. Full recipe in the header of `scripts/provision-rootfs.sh`; the host needs
`zig` (pacman) only when rebuilding. Verified on the device with a real `diff -u … | delta`.

**Supervision and single instance (fixed 2026-11-04).** Two starters exist in this image: the Android boot hook (`killall` + `nohup chroot … kururu-sentinel`) and **`kururu-wake`**, whose daemon calls `ensure_sentinel_running()` at start and now **every 60 s** — the crash restart the image never had. They race at boot, so the daemon arbitrates through an **atomic** claim on `/data/kururu-sentinel.pid` (`O_EXCL`): one start wins, the loser exits, and a pid whose process is gone is taken over instead of blocking the next start. The first guard did read-then-write and both instances ran (pids 548 and 553). **Always check `pidof kururu-sentinel | wc -w` — it must be 1**; two daemons double the ntfy pushes, the shutdown requests and the log lines.

**PATH (fixed 2026-11-04).** The hook exports Android's `PATH=/system/xbin:/system/bin:…`, which contains neither `/bin` nor `/usr/bin`. `Command::new("ping")` therefore failed while the network was perfectly healthy, and the FSM logged `kavure_ts=DOWN psicopompo_ts=DOWN` 60 s after boot — during a cable loss that is a **false blackout**, which ends in a homelab shutdown. `ping_check` now tries `/bin/ping`, `/usr/bin/ping`, then bare `ping`, and `main` normalises `PATH` once at startup. Verified across a real reboot: one instance, `UP`/`UP`, cap `0x42`, heartbeat pushed to ntfy.

**Boot path, verified 2026-11-04.** The hook that starts the daemon lives on the Android side, outside the chroot — and it is readable from inside: PID 1 is Android's `/init` and the PID namespace is shared, so `/proc/1/root/system/etc/install-recovery.sh` is the real file. It is **byte-identical** to `boot/install-recovery.sh` in the repo (sha256 `1f0d59b8d52c2f2c…`), which means the repo copy is the deployed copy and can be reviewed/committed normally. It re-applies the cap at boot (`echo 02 > reg`, `echo 42 > data`) and starts the daemon as `killall kururu-sentinel; nohup chroot /data/alpine /usr/local/bin/kururu-sentinel > /data/kururu-sentinel-stdout.log 2>&1 &`. Since v1.3 the binary writes its own log, so that redirect only captures panics — the console copy is opt-in with `KURURU_CONSOLE=1`, otherwise every line would land twice in two files (one of them without rotation).
- **Health check is the cap, not the process.** Force the stock ceiling and time the recovery:

```sh
ssh kururu 'echo 2 > /sys/class/power_supply/sec-charger/reg; echo 56 > /sys/class/power_supply/sec-charger/data'   # stock 4.33 V ceiling
sleep 4
ssh kururu 'echo 2 > /sys/class/power_supply/sec-charger/reg; cat /sys/class/power_supply/sec-charger/data'   # expect 42
```

  Measured 2026-11-04: recovered to `0x42` in **3 s** (bounded by the 5 s poll). The sysfs register interface is **hexadecimal end to end** — `56` is the stock 4.33 V value and `42` the 4.14 V cap, the same way the daemon writes them; an earlier note in this document said "decimal" and was wrong.

**Acceptance test — completed 2026-11-04.** The 14 h discharge is recorded in the measurement table above (15.6 h projected to the 20 % veto, 0.68 W mean, zero connectivity loss). `HB-105` is archived. To re-run it: stop the sentinel first (its 20 % veto triggers a homelab shutdown), sample `capacity`/`voltage_now`/`status`/`ac/online` over SSH every 120 s, and stop at 25 % — a human has to replug before 20 %.

## See Also

- [`servers/kururu-possibilities.md`](kururu-possibilities.md) — 20 roadmap possibilities and architectural roadmap
- [`services/wol-relay.md`](../services/wol-relay.md) — Homelab Wake-on-LAN architecture
- [`guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) — Tailnet tags: the applied map and the rules for future devices
- [GitHub Repository: KURURU-TAB3LITE-LINUX](https://github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX)
