---
tags: [homelab, recovery, kuaray, miracena, hardware, log]
---

# Incident 2026-11-06 — kuaray stopped dead at 14:44:44 (30 minutes of Miracena outage)

**Host:** kuaray · Dell Inspiron 5437 (P37G), BIOS A08 (2013-12-27), i5-4200U (15 W TDP), 5.7 GiB RAM
**Stack:** `miracena-frappe-*` (production) + `miracena-frappe-rc-*` (rehearsal 0.1.0-rc116) · `/srv/data/miracena`
**Status:** host recovered (manual power-on 15:14:44) · **cause not proven** · prevention tracked in **HB-113**, release in **HB-112**

## Verdict (three levels)

### Proven (evidence, no hypothesis)

1. **The machine stopped between 14:44:43.97 and 14:44:44.00 while it was writing to disk.** The last system
   record is `/var/log/syslog:9572126` at `14:44:43.965254` and the file is **NUL-filled from that point to the
   next boot** — a block allocated but never written. The kernel was logging a netfilter packet when it died.
2. **The OS never began a shutdown.** No `Reached target Power-Off/Reboot`, no `systemd-shutdown`, nothing; and
   `/boot/efi` (FAT, `/dev/sda1`) came back with the **dirty bit set** — *"Dirty bit is set. Fs was not properly
   unmounted"* (`systemd-fsck[634]`, boot 0). Only a power removal or a full-machine freeze produces that.
3. **It was a cliff, not a decay.** In the final 12 s the host completed SSH sessions in under a second each
   (`14:44:32 → 14:44:36 → 14:44:37 → 14:44:40 → 14:44:41`, each `Session complete` + `Wait: code=2`).
   No saturation, no stall, no warning. Exhaustion of any resource takes minutes; this took one second.
4. **No software-side death record exists**: no OOM, no MCE/EDAC, no `hung_task`, no softlockup, no oops, no
   panic. `/sys/fs/pstore` and `/var/lib/systemd/pstore` are empty, `kdump` is not installed
   (`is-enabled kdump-tools` → `not-found`), and `RuntimeWatchdogUSec=0` — the kernel watchdog was **disarmed**,
   so a freeze would not have rebooted itself.
5. **kuaray is a laptop running with no battery.** `ACPI: battery: Slot [BAT0] (battery absent)`; the only
   power supply in `/sys/class/power_supply/` is `AC`; `upower` reports `percentage: 0%`,
   `icon-name: 'battery-missing-symbolic'`. There is **no energy buffer**: any interruption of the DC input of
   even a few tens of milliseconds is an immediate, unlogged power-off.
6. **The mains at the house was up.** The two sibling hosts that share the LAN did not restart:
   `kavure` up since 2026-10-31 23:46, `psicopompo` since 2026-11-03 15:30, both continuously through 14:44.
   A grid outage is therefore excluded as the cause.
7. **Memory was not the mechanism.** Production stack measured at **478.8 MiB** (9 containers, `docker stats`),
   i.e. **8.2 % of 5837 MiB**. A second identical stack costs ~0.47 GiB, so two stacks ≈ **0.94 GiB = 16.4 %**.
   Swap was idle (`/swapfile` 2 GiB, 0 B used; zram 5.7 GiB, 121 MiB used, 3.54:1). Nothing was near a ceiling.
8. **The dump restore was not an I/O storm.** `dump.sql.gz` is **536 KiB** (`/srv/data/miracena/rehearsal-0.1.0-rc116/dump.sql.gz`).
   `bench migrate`/`create-site` had already finished at 14:41:59 (33.3 s CPU) and 14:41:14 (53.9 s CPU).
9. **The degraded HDD was not in the I/O path.** `/mnt/storage` (`/dev/sdb1`, 18 pending sectors) has **no
   `mnt-storage.mount` entries in the previous boot** and `findmnt` finds nothing now; the directory holds a
   20 KiB skeleton. The dying disk is a real problem — but not this one.
10. **The `MIRACENA EGRESS BLOCK` flood was not a load source.** 5976 lines in 4 d 20 h ≈ **1/min**; measured now
    **30 lines in 5 min = 6/min**. At ~150 bytes per line it is log noise, not CPU.

### Probable (best explanation; what would confirm it)

**Loss of DC input — the original 65 W-class adapter, its barrel jack, or the cable — on a notebook with no
battery to cover the gap.** Supporting shape: instantaneous stop, no OS trace at all, grid confirmed up, host
fresh from the heaviest CPU burst it ever runs (two `bench migrate`/`create-site` runs at 14:41), no thermal
event, and a **six-week history of abrupt stops that began on 2026-10-04** — the day kuaray was reactivated into
production (see the history table below). What would confirm it: the canary of HB-113 surviving the next stop
with the last 10 s of load/temperature/AC state, and the `stress-ng` load test reproducing a stop.

### Indeterminate (needs hands on the machine)

- ~~Whether the box was **off** or **on and frozen**~~ — **answered by the owner the same day: off.** No LED, fan
  stopped, nothing on the screen. A kernel hang leaves the board powered (LEDs lit, fan turning), so this rules out a
  software freeze and leaves loss of DC input as the only mechanism that fits the evidence.
- ~~The adapter's **model and rated wattage**~~ — **model confirmed: Dell Inspiron 5437, and the adapter is the one
  that shipped with it.** Dell's own reference guide for the 3421/5421/3437/5437 family lists 65 W (19.5 V, 3.34 A)
  or 90 W (19.5 V, 4.62 A) (dl.dell.com, *Inspiron 14/14R — Specifications*, "Power Adapter"). Which of the two sits
  on the desk is still unverified until someone reads the label, and it decides how close the brick is to its ceiling
  under load. Either way it is a twelve-year-old adapter with **no battery behind it**: `ACPI: battery: Slot [BAT0]
  (battery absent)` means a momentary DC dip has nowhere to go, and an aged brick under a full-core burst trips its
  own protection with no OS trace — exactly the shape this incident has.
- What the screen showed at 15:14 (nothing, since the box was dark).
- Condition of the barrel jack and the wall socket; whether the host is on a UPS or a shared power strip.
- Whether the abrupt stops share a room-temperature/season pattern (October onward only).

### What the owner's answer changes

Before it, "power loss" and "hard freeze" were symmetric hypotheses and the document had to hold both. With the box
found **dark**, the freeze is out and the remaining explanations are all on the DC path: the brick (aged, possibly at
its ceiling), the barrel jack (a known wear point on this generation), the cable, or the socket. That is why HB-113's
acceptance criterion is a canary that survives the stop rather than another round of log reading: the component is
decided by **when the power drops relative to the load**, and nothing on the disk can record its own power cut.

## Timeline (2026-11-06, -03)

| Time | Event | Source |
|---|---|---|
| 14:39:49 | rehearsal stack recreated (`rc-create-site-1`) | dockerd journal |
| 14:41:14 | `rc-create-site-1` exits, 53.9 s CPU | `systemd[1]: Consumed 53.862s CPU time` |
| 14:41:59 | `rc-migrate-1` exits, 33.3 s CPU | `Consumed 33.342s CPU time` |
| 14:42:00–14:42:01 | `rc-backend-1`, `rc-frontend-1` join the network | dockerd journal |
| 14:44:21–14:44:41 | six short SSH sessions read `auth.py` in the rc backend | tailscaled audit |
| 14:44:43.965 | last record ever written: one `MIRACENA EGRESS BLOCK` packet | `/var/log/syslog:9572126` |
| 14:44:44 | **dead.** File extended, data never flushed (NUL tail) | `/var/log/syslog:9572127` |
| 15:14:24 | power button pressed (~12 s of firmware + loader before the kernel) | `systemd-analyze`: 8.027 s firmware + 4.224 s loader |
| 15:14:36 | kernel sets the clock from RTC: `18:14:35 UTC` — RTC had kept correct time | `PM: RTC time` |
| 15:14:44 | journal starts, boot 0 | `journalctl --list-boots` |
| 15:15:03 | `fsck` of `/boot/efi` removes the dirty bit; `fsck` of `sdb1` gives up | `systemd-fsck[634]`, `[644]` |
| 15:26 | production stack up, rehearsal stack down (owner action) | `docker stats` |

**Correction to the working note:** the previous boot did **not** start at `2026-11-02 12:00:04`. That is the
oldest *surviving* journal entry for that boot, and it belongs to a **user** manager
(`systemd[2360319]: Queued start job for default target default.target`), not PID 1 — the system journal for the
first ~17 h was rotated away (853 MB retained). `last -x` gives the real boot: **2026-11-01 19:10**, i.e. an
uptime of **4 d 20 h 03 m**, not 4 d.

## Evidence (command → result)

### 1. Cold boot or freeze? What the boot itself says

```
$ systemd-analyze
Startup finished in 8.027s (firmware) + 4.224s (loader) + 7.309s (kernel) + 1min 45.651s (userspace)

$ journalctl -k -b 0 | head -2
kernel: Linux version 7.0.0-42-generic ... #42~24.04.1-Ubuntu ...
kernel: Command line: BOOT_IMAGE=/boot/vmlinuz-7.0.0-42-generic root=UUID=... ro quiet splash pcie_aspm=off

$ sudo dmidecode -t 0        → Version: A08, Release Date: 12/27/2013
$ sudo dmidecode -s chassis-type → Portable
```

8.0 s of firmware is a **full POST**, which a cold power-on and a warm reset both produce — it does not separate
the two cases. What does separate them is the absence of any OS record *and* the dirty filesystem: a Linux
hang leaves the machine powered, so the owner would have had to force it off, which also leaves the dirty bit.
The two hypotheses converge on disk. **Boot duration is not diagnostic here; the deciding observation is
physical** (was the machine off or on-and-frozen).

### 2. Where the power path fails

```
$ journalctl -k -b 0 | rg -i battery
ACPI: AC: AC Adapter [AC] (on-line)
ACPI: battery: Slot [BAT0] (battery absent)          ← no pack installed

$ eza -l /sys/class/power_supply/
AC -> ../../devices/platform/ACPI0003:00/power_supply/AC    ← the only supply

$ upower -i /org/freedesktop/UPower/devices/DisplayDevice
  unknown  percentage: 0%  icon-name: 'battery-missing-symbolic'

$ cat /sys/class/power_supply/AC/uevent
POWER_SUPPLY_NAME=AC / POWER_SUPPLY_TYPE=Mains / POWER_SUPPLY_ONLINE=1
```

There is no battery, no UPS (`lsusb` shows no HID power device; no `nut`/`apcupsd` units) and no adapter
telemetry. A 15 W-TDP Haswell with a 15.6" panel, one HDD and one SSD draws roughly 30–40 W at load — inside a
healthy 65 W brick, which points at a **degraded** adapter rather than an undersized one. **Not verified:** the
brick's label.

### 3. Thermal and hardware health

```
$ sensors
Package id 0: +52.0 C (high = +100.0 C, crit = +100.0 C)   Processor Fan: 2298 RPM
dell_smm: CPU +51.0 C · Ambient +45.0 C / +42.0 C · GPU +16.0 C
$ /sys/class/thermal/thermal_zone0/trip_point_0_temp → 98000 (98 C)
```

51–52 °C idle, 12 °C below the high threshold, fan healthy. A THERMTRIP would need a jump no evidence supports,
and the kernel throttles (and logs) long before the trip point. **No MCE/EDAC**: `dmesg | rg -i "machine check|edac"`
matches only the `EDAC MC: Ver: 3.0.0` banner; `mcelog`, `edac-util` and `ras-mc-ctl` are not installed.

Disks: `sda` Kingston A400 — health PASSED, `Power_On_Hours 7211`, `Reallocated 0`, `CRC 0`.
`sdb` ST1000LM24 — health PASSED but `Current_Pending_Sector 18`, `UDMA_CRC_Error_Count 59`, 21223 h, and the
kernel applies `brokenfpdmaaa nolpm`; boot 0 logs `media error` on **sector 32** — the very LBA the 2048-offset
MBR was built to bypass (see `servers/kuaray.md` §Storage). That disk is failing and must be retired, but it was
not mounted at the time of the stop.

### 4. Memory, honestly computed

| Quantity | Measured |
|---|---|
| RAM | 5.7 GiB (5837 MiB) |
| Production stack, 9 containers | 478.8 MiB = **8.2 %** |
| Second (rehearsal) stack at the same usage | ≈ 478.8 MiB → two stacks **0.94 GiB = 16.4 %** |
| `mem_limit` ceilings declared per stack (identical in both compose files) | **4288 MiB = 4.19 GiB** |
| Two stacks at their ceilings | 8.38 GiB — **more than RAM** |
| Swap | `/swapfile` 2.0 GiB (0 B used) + zram 5.7 GiB (121 MiB used, 3.54:1) |
| `vm.swappiness` | **150** |

Conclusion: at real usage both stacks fit with ~4.7 GiB to spare, so **memory is not what killed the host**.
But the guard rails do not stop a burst — the declared ceilings add up to more than physical RAM, and with
`swappiness=150` a burst turns into zram compression on a 15 W dual-core (i.e. heat and current draw, exactly
what a tired adapter handles worst). **Safe ceiling for one stack on this host: ~2048 MiB of aggregate
`mem_limit`** (available 3.0 GiB minus a 1 GiB reserve for the host and media containers), versus the 4288 MiB
declared today.

### 5. I/O around 14:44

```
$ journalctl -k -b -1 | rg -i "blocked for more than|hung_task|I/O error|nvme|ata.*error"   → (nothing)
$ journalctl -k -b 0  | rg -i "I/O error"  → attacks on sdb sector 32 / 1220611056 only, at boot (fsck)
```
No I/O stall preceded the stop, and `hung_task_timeout_secs=120` never fired — impossible to fire, because the
machine did not survive 120 s after its last log line.

### 6. The 5976-line firewall log

```
$ sudo iptables -S | rg MIRACENA
-A DOCKER-USER -s 172.22.0.0/16 -d 100.64.0.0/10 -m conntrack --ctstate NEW -j ufw-docker-logging-deny
-A DOCKER-USER -s 172.22.0.0/16 -d 192.168.0.0/16 -m conntrack --ctstate NEW -j ufw-docker-logging-deny
```
Sources are `172.22.0.4` (`miracena-tunnel`) and `172.22.0.8` (`miracena-nginx-proxy-manager`) sending UDP/41641
to LAN peers — a Tailscale client inside the Docker bridge trying to reach peers **directly**, which the
DOCKER-USER rule denies at ~6 packets/min. It is a *configuration* wart (those containers should reach the
tailnet through the host's `tailscale0`, not by opening a LAN route), and a log-rotation hazard:
`/var/log/syslog` is **2.4 GB / 9.58 M lines**, with 9441 egress lines and 41830 UFW blocks. Not a CPU problem;
a disk and observability problem.

## History: is this new?

`last -x` over the wtmp window (2026-04-26 → 2026-11-06), automatic pairing of each boot with the next
`shutdown system down` record — a boot with none ended abruptly:

| Boot | Ended | Uptime | Ended by |
|---|---|---|---|
| 2026-04-26 → 2026-10-04 (26 boots) | — | weeks | **clean**, except 4 in June |
| 2026-10-04 04:05 | 2026-10-04 14:04 | 9 h 59 m | **abrupt** |
| 2026-10-04 14:04 | 2026-10-05 18:31 | 1 d 04 h | **abrupt** |
| 2026-10-05 18:31 | 2026-10-06 14:33 | 20 h 02 m | **abrupt** |
| 2026-10-06 14:33 | 2026-10-31 21:41 | 25 d 07 h | **abrupt** |
| 2026-10-31 21:41 | 2026-11-01 19:10 | 21 h 29 m | **abrupt** |
| 2026-11-01 19:10 | 2026-11-06 14:44 | 4 d 20 h 03 m | **abrupt** |

**11 of 34 boots ended without a clean shutdown, and 6 of the 7 boots since 2026-10-04 did.** The abrupt
pattern starts on the reactivation day — the day kuaray became the production host. This is not a one-off
adapter failure and not a new fault of the last week: it is a **chronic, load-correlated loss of power** that
has been happening for a month and was masked by long uptimes between events.

## What prevents the next outage (aligned with HB-113, not a parallel plan)

HB-113 is the owner's item; this section only fills in what the evidence adds to it.

1. **Instrument before theorising (HB-113 step 1).** The reason this investigation cannot conclude is that the
   seconds before the stop were never on disk: no `sysstat` (`sar` not installed, `/var/log/sysstat` absent), no
   persistent metrics, and journald + rsyslog both lost their buffered tail. The 10-second canary is the single
   highest-value change — it converts the next stop from "unexplained" into "measured".
2. **Keep rehearsing on kuaray — and make the rehearsal leave a mark.** The owner's decision stands (the CPU is
   there for this). What changes is that every rehearsal run must start the canary first
   (`systemd-run --unit=hl-canary` and a check that the file moved in the last 30 s), so a stop *during* a
   rehearsal is captured with its load, and a stop without load is distinguishable from one at peak.
3. **Cap aggregate memory per stack at ~2 GiB** in both `compose.yml` files (today's 4288 MiB of ceilings
   exceeds physical RAM). That does not prevent a power stop; it prevents the box from converting a burst into
   swap thrash and heat, which is the condition the adapter fails in.
4. **Stop the egress leak**: route `miracena-tunnel` and `miracena-nginx-proxy-manager` through `tailscale0`
   instead of letting them try LAN peers directly. Removes ~6 lines/min of kernel logging and the incentive to
   rot `/var/log/syslog`, which is at 2.4 GB and holds the only surviving record of the crash second.
5. **Retire `/dev/sdb`.** 18 pending sectors, 59 CRC errors, `media error` on sector 32 at every boot, and a
   `fsck` that gives up (`UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY`, exit 4). It is not this incident, and
   it will be the next one.
6. **Hardware, in order of cost:** reseat the adapter at both ends and on a different socket → try a known-good
   65 W Dell adapter (the cheapest decisive test) → inspect the barrel jack for play/oxidation → optionally
   refit a battery (even a used one), which converts every future DC hiccup from an outage into a seamless
   transition.
7. **Tell the difference next time, cheaply.** If it happens again: look at the power LED *first* (dark = power,
   frozen image = software), then `journalctl --list-boots` and `last -x` for the dirty-bit/abrupt pair before
   doing anything else — a reboot destroys the FAT dirty bit and with it the only proof of an unclean stop.

## What this document does **not** claim

- It does not claim the adapter is faulty. It is the leading suspect, not a finding.
- It does not exclude a full-machine freeze (all CPUs stuck) followed by a manual power-off: no evidence on disk
  separates the two, and `panic=0`, `pstore` empty, no kdump mean a kernel death would leave exactly this trace.
- It does not claim the rehearsal caused the stop. It happened ~2.5 min after `migrate` finished, at a moment of
  low load; the rehearsal is a *heating* antecedent, not a proven trigger.

## See also

- [`servers/kuaray.md`](../servers/kuaray.md) — hardware, storage remediation, NIC power tuning
- [`backlog.md`](../backlog.md) — **HB-112** (the outage/release) · **HB-113** (find what turns kuaray off)
- [`recovery/incident-2026-10-miracena-wp.md`](incident-2026-10-miracena-wp.md) — previous kuaray incident
- [`services/miracena-stack.md`](../services/miracena-stack.md) — the stack that goes down with the host
