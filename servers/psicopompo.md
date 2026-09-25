---
tags: [homelab, server, psicopompo, gaming, docker, storage, power, gpu, nvidia, rebar]
---

# psicopompo

**Role:** Main server — physical local machine
**Default shell:** fish (`/bin/fish`) — zsh and bash also installed

## Hardware

| Item | Specification |
|---|---|
| **OS** | CachyOS Linux (Arch-based) |
| **Kernel** | 7.0.11-1-cachyos-bore |
| **CPU** | Intel Xeon E-2246G @ 3.60 GHz — 6C/12T |
| **GPU** | NVIDIA GeForce RTX 5050 |
| **RAM** | 46 GB (ZRAM: 46 GB) |
| **System Disk** | 462 GB NVMe (Kingston NV3) — `/dev/nvme1n1p2` — 49% used (06/09) |
| **PCIe Disk** | 1.8 TB NVMe (Kingston NV2) — `/mnt/NVME_PCI` — 36% used, ~1.2TB free (06/09, after a Docker cleanup of ~570GB — see [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md)). BTRFS merge: nvme1n1p5 + the 100GB nvme1n1p1 from the old Windows install. Biggest consumers: SteamLibrary ~550G, containerd-data ~59G, homelab/sumaenimahub ~50G |
| **SATA SSD** | 448 GB (Kingston A400) — `/mnt/SSD_SATA` — 10% used |
| **SATA SSD — Scryfall Mirror** | `/mnt/SSD_SATA/scryfall-mirror` — image/bulk cache for Arandu, exported via NFS to kavure (`/srv/data/scryfall-mirror`). Daily sync at 03:00 runs on kavure (`hl-scryfall-mirror.timer`). See [`services/scryfall-mirror.md`](../services/scryfall-mirror.md) |
| **SATA HDD** | 932 GB (Seagate 1TB) — `/mnt/HDD_SATA` — permanently mounted (BTRFS) |
| **SATA HDD (Backup)** | 932 GB (1TB) — `/mnt/BACKUP` — permanently mounted (BTRFS) |
| **MicroSD** | 116 GB — `/dev/sdd1` — exFAT — MICROSDXC |
| **Swap** | 46 GB (ZRAM) + 48 GB swapfile `/swap` (hibernation) |
| **Tailscale IP** | 100.82.51.112 |
| **Tailscale DNS** | psicopompo.chimaera-heptatonic.ts.net |
| **Network** | Intel I219-LM Gigabit Ethernet |

## GPU / NVIDIA — ReBAR and DDC/CI (25/08/2026)

> **GPU:** NVIDIA GeForce RTX 5050 (proprietary 610.x driver). The **Dell BIOS on psicopompo does not allow enabling ReBAR**, but with Linux that becomes possible via a kernel parameter.

### ReBAR (Resizable BAR) — how it is guaranteed
- **Enabled via the kernel cmdline**, not by the BIOS: `nvidia.NVreg_EnableResizableBar=1` in `/etc/default/limine` → `KERNEL_CMDLINE[default]` (canonical source that regenerates `limine.conf` for every entry — current kernel, alternatives, and snapshots).
- **Runtime verification:**
  - `grep EnableResizableBar /proc/driver/nvidia/params` → must show `1`
  - `lspci -vvv -s 01:00.0` → `Region 1: Memory at ... [size=8G]` (64-bit prefetchable = ReBAR active; without ReBAR the BAR would be smaller)
- **Careful:** when restoring a snapshot, check that the entry's cmdline still carries `EnableResizableBar=1`.

### DDC/CI — external monitor brightness control
- Documented NVIDIA fix applied via `nvidia.NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100` (same `/etc/default/limine` file). Forces software I2C — a requirement for DDC/CI on the proprietary NVIDIA driver.
- **Samsung C24F390 monitor (HDMI):** DDC/CI communication stays **intermittent** even with the fix (VCP read works ~25% of the time) — a limitation of the monitor/HDMI+GPU, **not** of the fix. The fix is generic and benefits any future DDC-capable monitor.
- Backups created: `/etc/default/limine.bak-ddc-20260825-032720`, `/boot/limine.conf.bak-ddc-20260825-032934`.

## Audio — GB207 HDMI Disabled (01/09/2026)

The NVIDIA driver creates multiple duplicate HDMI sinks (6× `alsa_output.pci-0000_01_00.1.hdmi-stereo`, all pointing at the same Samsung C24F390 monitor). It is not a Punktfunk bug — it is NVIDIA driver + PipeWire behavior.

**Fix:** WirePlumber rule that disables the entire GB207 audio card:
- File: `~/.config/wireplumber/wireplumber.conf.d/51-disable-gb207.conf`
- Rule: `device.disabled = true` for `alsa_card.pci-0000_01_00.1`
- Effect: removes the 6 HDMI sinks; only `Built-in Audio` + Punktfunk virtual devices remain
- Monitor HDMI audio ceases to exist (audio uses the JBL Tune 770NC over Bluetooth; streaming uses the `punktfunk-speaker-*` virtual device)
- Revert: delete the file and run `systemctl --user restart wireplumber`

## Roles

- **Tailnet NAS** (07/08): exports via NFSv4 `/mnt/BACKUP/media/music` and `/media/books` (canonical library) + `/mnt/BACKUP/sumaenima-server-kavure` (core backup) to kuaray/kavure — see [`network/nfs.md`](../network/nfs.md)
- Development, AI and gaming workstation (Steam/Wayland/Hyprland; the dedicated Zomboid, Minecraft and Valheim game servers were migrated to kavure)
- **Sumænimá GPU workers** (StênioREC / vision / audio / ollama) + build-node (07/08/2026 — the `sae-core` moved to kavure)
- Syncing (Syncthing) and Rclone (CLI active — off-site Drive + mount; GUI removed 26/08)

## Hibernation (21/08/2026)

> **State:** active and tested (S4 shutdown + full resume). The "Hibernate" option shows up in KDE Plasma (PowerDevil) because `logind` reports `CanHibernate=yes`.

"swap file for hibernation with zram" setup (ArchWiki standard): **zram (pri 100)** stays as the active swap for normal use; the **on-disk swapfile (pri 1)** stays idle and is used only as the destination for the hibernation image (`logind` ignores zram when hibernating).

| Item | Value |
|---|---|
| Subvolume `/swap` | btrfs, **sibling of `/@`** (top-level id=5) → outside the snapper snapshots |
| Swapfile | `/swap/swapfile` — 48 GB, NOCOW, `btrfs filesystem mkswapfile --size 48g --uuid clear` |
| `resume=` | `UUID=ffc60b3e-2f31-47bb-b51e-4eb785af8647` (btrfs root) |
| `resume_offset=` | `17188552` (`btrfs inspect-internal map-swapfile -r /swap/swapfile`) |
| Source cmdline | `/etc/default/limine` → `KERNEL_CMDLINE[default]+=... resume=... resume_offset=...` |
| Initramfs | systemd-based (`base systemd ...`) → native resume, no extra hook |
| fstab | `UUID=ffc60b3e... /swap btrfs subvol=/swap,noatime 0 0` + `/swap/swapfile none swap defaults,pri=1 0 0` |

**Maintenance / caveats:**
- **After restoring a snapshot:** `resume_offset` may change if the swapfile is recreated → run `limine-update` (recalculates and regenerates cmdline/initramfs).
- **Backups:** `/swap` (48 GB) sits outside the snapper snapshots of `/@` and must be **excluded** from backup routines that scan `/` (otherwise it bloats the backups).
- **Security:** root without LUKS → the hibernation image sits on disk **unencrypted** (accepted — local homelab).
- **Instant wake:** keyboard/mouse staying powered during S4 is normal (USB-powered from the Dell). To actually hibernate, wait for the case LEDs to go out before turning it back on.
- Config backups created during implementation: `/etc/fstab.bak-hibernacao`, `/etc/default/limine.bak-hibernacao`.

## Suspend / Sleep (22/09/2026)

> **State:** ✅ working — **2 full tests**: (1) runtime `mem_sleep=s2idle` → resume OK; (2) **permanent drop-in path** → journal proves `PM: suspend entry (s2idle)` + `nvidia-resume` OK + the same session continued (21:49). Ready for any reboot.

**Original symptom (early morning 22/09):** suspend via the Noctalia menu → screen went off, the machine "turned itself off" and then did a **cold boot** — resume **never ran** (0 `Waking up from S3` logs; `nvidia-resume.service` never ran).

**Root cause (documented case):** the firmware advertises **deep (S3)** but does not wake up → ArchWiki *Power management* §Changing suspend method: *"faulty firmware advertises support for deep sleep, while only `s2idle` is supported"*.

**Diagnostics that were ruled out (checked before concluding):**
- NVIDIA VRAM preservation is **correct** (`UseKernelSuspendNotifiers: 1` + `TemporaryFilePath: /var/tmp` — official ArchWiki §Preserve video memory check; driver 615.71.09 uses the 595+ mechanism)
- Wake sources OK (`XHC` USB enabled) · normal inhibitors (4× delay) · `MODULES=()` (no early KMS → the doc's hibernation caveat does not apply)
- Recurring AER RxErr (correctable) on port `0000:00:01.0` (**PEG0 = GPU**) — **monitor** it in case it causes future problems

**Fix applied (ArchWiki §Changing suspend method):**
1. Runtime test (proved it): `echo s2idle | sudo tee /sys/power/mem_sleep` → suspend OK
2. **Persistent:** `/etc/systemd/sleep.conf.d/60-freeze.conf`:
   ```ini
   [Sleep]
   SuspendState=freeze   # systemd-suspend.service escreve "freeze" em /sys/power/state
   ```

**Hibernation NOT affected (separation by design):** `SuspendState=` (suspend → `/sys/power/state`) and `HibernateMode=` (hibernation → `/sys/power/disk`) are independent options belonging to different services — `systemd-sleep.conf(5)`. Hibernation config (21/08) untouched.

**Caveats:** avoid suspending with a hot CPU (journal warning `intel_pch_thermal: S0ix might fail` at ≥66C); keep an eye on AER RxErr on the GPU.

## Hyprland/Noctalia Desktop Idle Policy (24/09/2026)

The desktop uses **Noctalia's native Idle Behavior**, with no extra `hypridle` or `swayidle`. The policy persisted in `~/.local/state/noctalia/settings.toml` is:

- **screen off:** `timeout = 0` when unlocked; `locked_timeout = 60 s` (1 min after lock);
- **lock:** `900 s` (15 min of idle);
- **lock + suspend:** disabled (`timeout = 0`, `enabled = false`);
- **pre-action fade:** `2 s`;
- **lock before manual suspend:** enabled (`lock_before_suspend = true`).

When the session enters the locked state, Noctalia rearms the `screen-off` timer at `60 s`; on unlock, the monitor turns back on and the behavior is disabled again (`timeout = 0`). The order is `lock` → `screen-off`, so the screen is not turned off before the session locks. `systemd-logind` still uses `IdleAction=ignore`; therefore the PC does not suspend automatically on inactivity. The `lock_and_suspend` action in the session menu and `SUPER+H` remain manual.

During media playback, players that send idle inhibitors suspend both timers. Noctalia's log should be checked in `~/.cache/noctalia/noctalia.log`; Firefox may not signal consistently. The full operational guide is in [[hyprland-noctalia-guide]].

`settings.toml` is a Settings override, takes precedence over the declarative TOML files, and is included in the `config-backup` mirror. `merged-config.toml` is generated daily and must not be edited.

## See also
- [[psicopompo-gaming]] — Steam gaming guide on Linux
- [[zomboid-psicopompo-handoff]] — shutting down the local PZ server (migrated to kavure)
- [[plasma-kirigami-applet-bug]] — workaround for the network/volume applet bug (`appletsrc` reset, 25/08/2026)

## Tailscale Funnels

None currently (Sumænimá traffic is routed through Nginx proxies on ybyra and kuaray).

## Docker Swarm — GPU role (07/08/2026)

> **State (07/08/2026):** psicopompo became a **Swarm worker with `role=gpu`** — the core (`sae-core`) migrated to **kavure** (manager). Only the **GPU workers** (vision/audio/ollama) live here via standalone `gpu.yml`, connected to kavure's `sumaenima_sumaenima-net` Swarm overlay. psicopompo is also the **build-node** (ADR-026: the only machine that builds Docker images).

| Container | Image | Ports | Function |
|---|---|---|---|
| steniobot_vision | sumaenimahub-steniobot-vision:latest | — | Vision (OCR + SAM 2) — GPU |
| steniobot_audio | sumaenimahub-steniobot-audio:latest | — | Audio (Whisper) — GPU |
| steniobot_ollama | ollama/ollama:latest | `0.0.0.0:11434` | LLM (qwen3.6) |
| portainer | portainer/portainer-ce:latest | `0.0.0.0:9000` | Docker management |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoring |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `0.0.0.0:2375` | Docker socket proxy (homepage) |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers (24h) |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart of containers |

> **Removed:** RustDesk hbbs/hbbr (no longer exist), WinBoat (shut down), **crafty-controller + Minecraft** (migrated to kavure on 08/08/2026 — Phase F).
> **Migrated to kavure (07/08):** `sae-core` stack (Sumænimá/StênioBOT) — db, valkey, api, umami-db, backup, asciline.
> **GPU workers:** come up on demand via `sumaenima-ctl start` (auto-exit after 180s idle to free VRAM).
> **Syncthing: ACTIVE** (22/09 — canonical user unit `syncthing.service`; see `services/syncthing.md` for the fix of the duplicated units). **Rclone:** CLI active (off-site backup + mount); **GUI removed 26/08** (never used, RC daemon without auth — see `services/rclone.md`).
> **Build node (06/09):** builder standardized on **`default`** (docker driver) — `default-builder` (container BuildKit) and the dead remote builder `kavure` removed; BuildKit GC configured in `daemon.json` (`defaultKeepStorage=30GB`); monthly timer `docker-prune.timer` (day 01, 04:00). Snapper standardized (reproducible → no snapshots): `hdd` config removed, `ssd` with no config; `nvme`/`backup` keep the timeline. The cleanup recovered ~570GB (`btrfs` Used 1.22TiB→652GB; `containerd-data` ~396G→~59G, `docker-data` ~99G→~1.8G). See [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md) and [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)

## Native Programs

| Program | Function |
|---|---|
| syncthing | File syncing (Obsidian vault) — **active** (canonical user unit `syncthing.service`; config `~/.local/state/syncthing/config.xml`) |
| greetd + noctalia-greeter | Display manager (graphical login) — **22/09**: replaced plasmalogin; `display-manager` → greetd; sessions: Hyprland/UWSM + Plasma. Config: `/var/lib/noctalia-greeter/greeter.toml` (72Hz, McMojave system-wide cursor, passwordless Sync for edu) |
| rclone | CLI + remotes (off-site Drive, mount) — **active**; web GUI removed 26/08 (never used) |
| systemd timers `hl-*` | Backup scheduling (05:00–06:30, `Persistent=true` — catch-up after reboot) — **10/08** |
| cronie | Cron kept installed for future use (no jobs of its own) |
| tailscaled | Tailscale agent |
| steam | Gaming |

## Important Ports

| Port | Service | Bind |
|---|---|---|
| 11434 | Ollama (GPU worker) | `0.0.0.0` |
| 9090 | StênioREC (local GPU Whisper daemon) | `127.0.0.1` / Tailscale |
| 61208 | Glances | `0.0.0.0` |
| 2375 | Docker proxy (homepage) | `0.0.0.0` |
| 27036 | Steam | `0.0.0.0` |
| 5355 | systemd-resolved | `0.0.0.0` |

> **Ports of services migrated to kavure (no longer listening here):** 9090 (sae-core_api Swarm), 9092 (backup sentinel), 8443/8444 (Crafty Controller Minecraft), 25565 (Minecraft server), 16261 (Project Zomboid). **To reactivate:** 8384 (syncthing). **Portainer and the rclone GUI removed.**

## SMART — External Disks (fix 22/09/2026)

`smartd.service` failed on boot (exit 16) when the external disk **SSHD-1TB** was disconnected: `Unable to register device (no Directive -d removable)`. Fix in `/etc/smartd.conf` (backup `.bak-removable`): the **SSHD-1TB** and **EXPANSION-2TB** lines (both external) with **`-d removable`** → smartd **ignores it when absent** instead of exiting (ArchWiki S.M.A.R.T. § `-d removable`; man smartd.conf: *"continue instead of exiting if the device does not appear to be present"*). The `-d sat,removable` form is NOT accepted by the local smartd 7.5 (the parser rejects the comma) — used plain `-d removable` (autodetect handles the type; validated: EXPANSION plugged in, SSHD absent ignored, 3 devices monitored).
