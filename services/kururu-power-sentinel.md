---
tags: [homelab, service, kururu, wol, power, monitoring]
pending: []
---

# Kururu Power Sentinel

Autonomous power outage detection, coordinated safe shutdown, and closed-loop Wake-on-LAN recovery daemon for Mnemocine Homelab.

**Node:** Kururu (Samsung Galaxy Tab 3 Lite SM-T110 / Alpine Linux 3.20 ARMv7)  
**Binary:** `/usr/local/bin/kururu-sentinel` (Rust native, static musl)  
**Target Hosts:** Kavure (`192.168.3.41` / `100.124.146.77`), Psicopompo (`192.168.3.100` / `100.82.51.112`)  
**Log Path:** `/data/kururu-sentinel.log` (persistent ext4 partition)

---

## 1. Overview & Architecture (verified 2026-11-03)

Kururu acts as the dedicated **Physical Power Guardian** for the homelab. Because it is a battery-powered tablet drawing **≈0.68 W measured** (design ceiling < 0.8 W, 14 h discharge test 2026-11-04) with an integrated **Summit SMB327/SMB328 charger** (plus an **88PM822** fuel gauge — not an `axp20x` PMIC; see [`servers/kururu.md`](../servers/kururu.md) § Hardware), it remains 100% operational during complete mains power failures without relying on external UPS units.

```
                              ┌────────────────────────────────────────┐
                              │  Mains Power Grid (House Outlets)      │
                              └──────────────────┬─────────────────────┘
                                                 │
                        ┌────────────────────────┴────────────────────────┐
                        ▼                                                 ▼
             House Wall Outlets (No UPS)                      Homelab Dumb UPS Units
            - Kururu USB Charger                             - Kavure (Dell OptiPlex 3060)
            - ISP Fiber ONT (Neighbor House)                 - Psicopompo (Workstation)
                        │                                    - Gigabit Switch & Wi-Fi Router
                        ▼                                                 │
       Kururu Power Sentinel (Daemon)                                     ▼
        - PMIC: /sys/class/power_supply/                     wol-relay (:9096) HTTP Listeners
        - WAN Ping Probes (1.1.1.1)                          - POST /power/shutdown
        - Tailscale Probes (100.x.y.z)                       - GET /wake/<target>
```

---

## 2. Core Operational Pillars

### A. Independent Autonomy (Zero Home Assistant Dependency)
The daemon operates 100% locally on Kururu. It makes life-and-death decisions using its own hardware telemetry and network probes without depending on Home Assistant, MQTT brokers, or container engines.

### B. Anti-Flapping Leaky Bucket (UPS Battery Preservation)
To prevent erratic grid fluctuations ("power flapping" and auto-reclosers) from repeatedly resetting timers and draining dumb UPS batteries:
* Every second running on battery without grid power increments a **debit counter** (`debit += interval`).
* If grid power blinks back for a few seconds, the debit counter does **not** instantly reset to zero. Instead, it **drains gradually** at twice the probe rate (`debit -= interval * 2`).
* If power cuts again while residual debit exists, accumulation resumes from the remaining debit rather than starting from zero.
* Once the cumulative debit reaches **180 seconds (3 minutes)**, the safe shutdown is triggered immediately.

### C. Physical Motion & Dock Baseline Discrimination (Physics-Based Immunity) — verified 2026-11-03
To prevent false positives when unplugging Kururu for handheld use while preserving 100% detection for real blackouts:
* While charging on AC (`ac_online == 1`), Kururu's daemon continuously calibrates its **resting dock orientation vector** $\vec{V}_{dock} = (X, Y, Z)$ using a low-pass filter on the hardware 3-axis accelerometer (`/sys/class/sensors/accelerometer_sensor/raw_data`).
* When AC disconnects:
  - **Mains Witness Veto (Smart Lamps):** Before assuming an outage, Kururu checks 4 dedicated smart bulbs wired directly to house wall sockets without battery/UPS backup (`192.168.3.36-39:6668`). If at least one lamp responds, **mains electricity is alive**! Kururu enters `CableFault` (0 debit, no server shutdown) preventing bad cables or loose chargers from dropping the homelab.
  - **Real Blackout:** If the tablet remains resting motionless on its dock ($\Delta < 180$) and **all smart lamps are unreachable**, power grid collapse is confirmed. Kururu enters `BlackoutPending(StaticDockLostAc)`, triggering safe shutdown in 180s even if the router is on UPS and WAN internet is still online!
  - **Handheld / Portable Usage:** Physically unplugging the cable and picking up the tablet by hand produces a massive orientation shift ($\Delta \ge 310 - 530$ units). Kururu detects $\Delta \ge 180$, logs `[ASSESSMENT] Confidence: 10%`, and **takes zero shutdown action**.
* **Dock Return Trigger:** If the user is in `PortableUsage` and returns the tablet to its resting dock orientation ($\Delta < 180$) while unpowered:
  - If smart lamps are online $\rightarrow$ transitions to `CableFault` (standing by).
  - If smart lamps are dead $\rightarrow$ transitions to `BlackoutPending(StaticDockLostAc)` (countdown to safe shutdown).

### D. Decision Table & Confidence Labels — implemented 2026-11-04 (was documentation-only)

The guardian is a **table, not a weighted score**. `assess(moved, witness, wan, battery)` in
`crates/kururu-sentinel/src/main.rs` is the single source of truth, and
`the_documented_matrix_is_the_binary_and_the_binary_is_the_matrix` walks every row — a change to one
is a change to the other. The confidence figures are **labels attached to the row that fired**, not an
arithmetic sum over the vectors: for a safety interlock, "this row, this evidence" is auditable and a
weighted blur is not. An earlier version of this section claimed weights of 60 % (dock) and 40 % (WAN);
no such computation ever existed in the binary (HB-109).

Kururu Sentinel evaluates five independent physical, hardware, and network vectors:

| Vector | Probe Source | Role |
|---|---|---|
| **AC Mains Power** | Hardware PMIC (`/sys/class/power_supply/sec-charger/online`) | **Gatekeeper.** AC online with zero debit means `AcNormal`, and the table is never consulted. |
| **Mains Grid Witness** | Tuya Local TCP `:6668` (`192.168.3.36-39`) | **Physical veto, three-valued.** Four wall-powered bulbs without UPS. Any answer ⇒ `Healthy`. No answer **while the rest of the network answers** ⇒ `Dead`. No answer *and* nothing else answers ⇒ `Unknown`, which is not evidence of anything. |
| **Dock Orientation Shift** | 3-axis accelerometer ($\|\vec{V} - \vec{V}_{dock}\|$) | **Primary discriminator.** Static dock ($\Delta < 180$) versus human handling ($\Delta \ge 180$). |
| **WAN Internet Reachability** | ICMP probe to `1.1.1.1` and `8.8.8.8` | **Corroborator.** Never sufficient on its own, and it shares the tablet's uplink, so it is used to grade confidence, not to decide. |
| **Battery Charge Capacity** | Sysfs gauge (`battery/capacity`) | **Override.** $\le 20\%$ escalates to `CriticalBattery` regardless of every other vector — the one reading that does not travel over the network. |

#### Decision matrix (mirrors `assess()` row for row)

| AC State | Dock Shift ($\Delta$) | Witness | WAN | Battery | Assessment | Confidence | Action / FSM State |
|---|---|---|---|---|---|---|---|
| **Online (1)** | Any | Any | Any | Any | Mains present; table not consulted | **0%** | `AcNormal` (dynamic dock calibration) |
| **Offline (0)** | Any | Any | Any | $\le 20\%$ | Tablet battery critically low — outranks every vector | **95%** | `BlackoutPending(CriticalBattery)` |
| **Offline (0)** | $\ge 180$ (Moved) | **Healthy** | Any | $> 20\%$ | Lifted while the grid is healthy | **10%** | `PortableUsage` |
| **Offline (0)** | $\ge 180$ (Moved) | **Dead** | Any | $> 20\%$ | Lifted with the grid down | **85%** | `BlackoutPending(WanLostInPortable)` |
| **Offline (0)** | $\ge 180$ (Moved) | **Unknown** | Any | $> 25\%$ | Lifted, cannot see the network: portable use, not a blackout | **30%** | `PortableUsage` |
| **Offline (0)** | $\ge 180$ (Moved) | **Unknown** | Any | $\le 25\%$ | Lifted, blind and out of time: the battery clock decides | **80%** | `BlackoutPending(StaticDockLostAc)` |
| **Offline (0)** | $< 180$ (Static) | **Healthy** | Any | $> 20\%$ | Cable fault / loose charger, mains UP | **0%** | `CableFault` |
| **Offline (0)** | $< 180$ (Static) | **Dead** | **Online** | $> 20\%$ | Grid lost, router still on UPS | **90%** | `BlackoutPending(StaticDockLostAc)` |
| **Offline (0)** | $< 180$ (Static) | **Dead** | **Offline** | $> 20\%$ | Grid lost and WAN also down | **100%** | `BlackoutPending(StaticDockLostAc)` |
| **Offline (0)** | $< 180$ (Static) | **Unknown** | Any | $> 25\%$ | Blind spot: nothing answers, so nothing proves a blackout | **0%** | `CableFault` (standing by, **never** escalates) |
| **Offline (0)** | $< 180$ (Static) | **Unknown** | Any | $\le 25\%$ | Blind and out of time | **80%** | `BlackoutPending(StaticDockLostAc)` |

`Unknown` is the row the old matrix lacked, and its absence was the defect: "all lamps silent" was
read as "the grid fell" whether or not the tablet could see anything at all.

#### The shutdown race is dual-path, and both legs were measured (HB-074, 2026-11-04)

`trigger_node_shutdown` fires **two threads at once** — `http://<lan_ip>:9096/power/shutdown` and
`http://<tailnet_ip>:9096/power/shutdown` — and commits on the first HTTP 200, so a dead WAN (Tailscale
down) does not remove the only way to ask a host to power off. Measured from Kururu itself, `GET
/health` answered **200 on all four legs**: psicopompo `192.168.3.100` and `100.82.51.112`, kavure
`192.168.3.41` and `100.124.146.77`. Both relays listen on `0.0.0.0:9096` with UFW scoped to
`192.168.3.55` (Kururu) plus the peer, which is what makes the LAN leg work at all — psicopompo's own
document said `127.0.0.1` and was corrected.

The `POST` itself is still never exercised without a real host: the relay has no dry-run endpoint, so
the commit-on-first-200 logic rests on review and on the reachability above, not on a fired shutdown.

#### Exercising the table without an outage: `--assess`

The guardian reads its vectors, prints them and the assessment it *would* make, then exits — it never
claims the pid file and never enters the FSM, so it is safe beside the live daemon:

```sh
kururu-sentinel --assess                      # real vectors
kururu-sentinel --assess --lamps 127.0.0.1:1 --sim-ac 0            # DEAD, real network probes
kururu-sentinel --assess --lamps 127.0.0.1:1 --sim-ac 0 --moved    # DEAD while lifted
kururu-sentinel --assess --sim-witness unknown --sim-ac 0          # blind spot: stands by
```

Flags: `--lamps a:6668,b:6668` (override the probe list), `--moved` (the tablet is in hand),
`--sim-ac 0|1` and `--sim-witness healthy|dead|unknown` (simulate an input the one-shot process cannot
observe). Every simulated value is printed with `(simulated)` next to it, because the point is to
classify a scenario, not to claim the world changed. Measured 2026-11-04:

```
DEAD, static   -> Blackout(StaticDockLostAc) 90%   "mains witness dead while the network answers"
DEAD, moved    -> Blackout(WanLostInPortable) 85%  "lifted with the grid down"
UNKNOWN, static-> CableFault 0%                    "witness unknown: standing by, not escalating"
UNKNOWN, moved -> PortableUsage 30%                "lifted, witness unknown: portable use"
```

#### Anti-Bounce Hysteresis & Leaky Bucket Drain
To prevent state thrashing between `PortableUsage`, `CableFault` and `BlackoutPending`:
- In `CableFault`, detecting physical pickup ($\Delta \ge 180$) transitions to `PortableUsage`. If smart lamps die, it escalates immediately to `BlackoutPending`.
- `StaticDockLostAc` only de-escalates back to `PortableUsage` if a human physically lifts the tablet ($\Delta \ge 180$) **and** WAN remains reachable, or back to `CableFault` if smart lamps recover.
- `WanLostInPortable` only de-escalates back to `PortableUsage` if WAN connectivity recovers.
- `CriticalBattery` never de-escalates unless physical AC power is restored.
- In `BlackoutPending`, detecting AC drains debit at 10s per 5s cycle. It only transitions back to `AcNormal` when debit reaches `0s`.

### E. Native HTTP Control via LAN ⚡ Tailscale Concurrent Race (Zero SSH, WAN-Immune)
Shutdown commands do not rely on SSH keys, passphrases, batch mode, or external WAN internet. Both Kavure and Psicopompo run `wol-relay` (native Rust on port `9096` as root) protected by UFW rules accepting only Kururu's fixed LAN IP (`192.168.3.55`) and Tailscale:
* **Concurrent Race:** Kururu fires parallel background threads targeting both LAN (`192.168.3.x:9096`) and Tailnet (`100.x.y.z:9096`).
* **First Response Wins:** Whichever channel returns HTTP 200 first commits the shutdown. If the ISP fiber is severed during a blackout, the local Wi-Fi/switch packet completes the command in `<1ms`.
* **Kavure:** `POST http://192.168.3.41:9096/power/shutdown` ⚡ `http://100.124.146.77:9096/power/shutdown`
* **Psicopompo:** `POST http://192.168.3.100:9096/power/shutdown` ⚡ `http://100.82.51.112:9096/power/shutdown`
Each target receives the command and executes `shutdown -P now` instantly.

### F. Simultaneous Closed-Loop Recovery
When mains power returns:
1. **Stabilization Quarantine:** Kururu requires **180 continuous seconds of AC power** (`ac_online == 1`). If power cuts during quarantine, the timer resets.
2. **Parallel Wake:** Kururu fires WoL magic packets for **both Kavure and Psicopompo simultaneously** via local `kururu-wake` (`127.0.0.1:9096`).
3. **Closed-Loop Feedback:** Kururu polls their Tailscale IPs every 10 seconds. If a node does not respond within 40 seconds, it re-emits the WoL packet automatically until confirmed alive.

---

### Known gaps — audit 2026-11-04 (HB-109)

A full read of `crates/kururu-sentinel/src/main.rs` against this document. The decision model above
is **documentation, not behaviour**:

| Documented | In the binary | Verdict |
|---|---|---|
| Five vectors with weights (dock 60 %, WAN 40 %) and a computed confidence | `if/else` branches; the percentages are hardcoded `log_event` strings (`main.rs:635-667`) | **not implemented** — the matrix describes a model the code never computes |
| `CableFault`: pickup → `PortableUsage`; lamps die → escalate immediately | both checks exist (`Check 2`, `Check 3`), but `Check 3` trusted a bare `!mains` | **implemented, unsound** — a Wi-Fi drop read as a grid outage (corrected 2026-11-04) |
| `StaticDockLostAc` de-escalates (human lifts **and** WAN alive) | `deescalate` block present | ok |
| `WanLostInPortable` de-escalates when WAN returns | present | ok |
| `CriticalBattery` never de-escalates | present (`false`) | ok |
| §E LAN ⚡ Tailscale race, first HTTP 200 wins | `trigger_node_shutdown` threads, 200 check (`:453-470`, called at `:881`) | ok |
| §F 180 s quarantine, parallel WoL, 10 s polling, re-emit every 40 s | `for attempt in 1..=12`, 10 s sleeps, re-emit every 4 (`:940-962`) | ok |
| Charge cap via SMB327 reg `0x02` | implemented 2026-11-04 (HB-105) | ok |

**G1 — the mains witness is not independent of the network it watches.** The only physical evidence
of grid power is four Tuya lamps probed over TCP `:6668`, i.e. over the same Wi-Fi the tablet uses.
"All four silent" therefore means *either* "the grid is down" *or* "my Wi-Fi/router is down", and the
code reads both as mains dead.

**G2 — the failure chain that shuts the homelab down for nothing:**

```
1. charger unplugged or loose        → ac_online = 0        → CableFault (safe)
2. Wi-Fi drop / router outage        → 4 lamps unreachable  → mains = false
3. static on dock                    → BlackoutPending(StaticDockLostAc), 90-100 %
4. 180 s later                       → POST /power/shutdown to Kavure and Psicopompo
```

The grid never failed. Nothing is notified before the kill. The documented matrix has no row for
"the witness is unreachable because the network is gone" — that ambiguity is the bug.

**Fix plan**

1. ✅ **Tri-state witness** (2026-11-04). `Some(true)` a lamp answered · `Some(false)` none answered **while the LAN
   itself answers** · `None` cannot probe at all. `None` ⇒ **never** `BlackoutPending` while the
   tablet has battery to wait with; the battery veto (≤ 20 %) and the 25 % unknown-witness
   threshold are the only escalations. Applied in both places that trusted a bare `!mains`:
   `AcNormal` and `CableFault Check 3`. Live proof in the heartbeat: `witness=HEALTHY`.
2. ✅ **Compute the score** (2026-11-04). `assess(moved, witness, wan, battery)` is pure, lives in
   `main.rs`, and the FSM has no other path to a decision; the doc's matrix was rewritten to mirror it
   row for row, and `the_documented_matrix_is_the_binary_and_the_binary_is_the_matrix` walks all of
   them. The 60/40 arithmetic the doc used to claim never existed and was removed rather than invented:
   for a safety interlock, the audit trail of the row that fired is worth more than a weighted blur.
3. ✅ **`CableFault` re-evaluation** was already there (`Check 2`/`Check 3`); the audit's first pass
   said otherwise and was wrong. What it needed was (1).
4. ✅ **Notify before acting.** `push_alert` fires on the unknown/blind-spot paths and when the grid
   outage is confirmed, deduplicated inside a 10-minute window so a lasting blind spot cannot flood
   the fleet topic.
5. ✅ **Tests**: `unknown_escalates` covers 90 %, 26 %, none, 25 %, 8 % and both conclusive
   witnesses. The shutdown path stays untested live, by design — it is the one thing that must
   never be exercised by accident, and the `Dead`/`Unknown` classification cannot be simulated
   without cutting the very link used to observe it.

## 3. Finite State Machine (FSM)

```mermaid
stateDiagram-v2
    [*] --> AcNormal: AC connected (ac_online=1)

    AcNormal --> PortableUsage: AC lost WITH physical pickup (delta >= 180 & wan=OK) [10%]
    AcNormal --> BlackoutPending_Dock: AC lost while static on dock (delta < 180) [75%-100%]
    AcNormal --> BlackoutPending_Wan: AC lost WITH pickup BUT wan=OFF [85%]

    PortableUsage --> AcNormal: AC reconnected
    PortableUsage --> BlackoutPending_Dock: Returned to dock position without AC [75%]
    PortableUsage --> BlackoutPending_Wan: WAN probe fails while on battery [85%]
    PortableUsage --> BlackoutPending_Bat: Battery level <= 20% [95%]

    state BlackoutPending_Dock {
        [*] --> AccumulateDock: +5s debit per probe interval
        AccumulateDock --> PortableUsage: User lifts tablet from dock & WAN alive
        AccumulateDock --> DrainDebitDock: AC restored (drain -10s/cycle)
        DrainDebitDock --> AccumulateDock: AC lost again before 0s
        DrainDebitDock --> AcNormal: Debit reaches 0s
        AccumulateDock --> ExecutingShutdown: Debit reaches 180s threshold
    }

    state BlackoutPending_Wan {
        [*] --> AccumulateWan: +5s debit per probe interval
        AccumulateWan --> PortableUsage: WAN connectivity restored
        AccumulateWan --> DrainDebitWan: AC restored (drain -10s/cycle)
        DrainDebitWan --> AccumulateWan: AC lost again before 0s
        DrainDebitWan --> AcNormal: Debit reaches 0s
        AccumulateWan --> ExecutingShutdown: Debit reaches 180s threshold
    }

    state BlackoutPending_Bat {
        [*] --> AccumulateBat: +5s debit per probe interval
        AccumulateBat --> ExecutingShutdown: Debit reaches 180s threshold
    }

    state ExecutingShutdown {
        [*] --> SendHttpShutdown: POST /power/shutdown to 100.124.146.77 and 100.82.51.112
        SendHttpShutdown --> AwaitS5: Poll ping until both confirmed offline
        AwaitS5 --> WaitingForPower
    }

    state WaitingForPower {
        [*] --> MonitorAC: Hosts offline in S5. UPS battery preserved
        MonitorAC --> StabilizingRecovery: AC power detected (ac_online=1)
    }

    state StabilizingRecovery {
        [*] --> QuarantineTimer: Count up to 180s continuous AC
        QuarantineTimer --> WaitingForPower: AC lost during quarantine (reset)
        QuarantineTimer --> ClosedLoopWake: 180s clean power verified
    }

    state ClosedLoopWake {
        [*] --> FireParallelWoL: Simultaneous WoL to kavure and psicopompo
        FireParallelWoL --> VerifyPing: Poll 100.x.y.z every 10s
        VerifyPing --> FireParallelWoL: Re-fire if node unresponsive after 40s
        VerifyPing --> AcNormal: Both nodes confirmed online on Tailnet
    }
```

---

## 4. Telemetry Log Sample (`/data/kururu-sentinel.log`)

```text
[19:30:00] [HEARTBEAT] state=AcNormal ac_online=1 kavure_ts=UP psicopompo_ts=UP debit=0s
[19:31:14] [INFO] AC disconnected while WAN is online -> Portable usage detected. Standing by.
[19:35:20] [ALERT] AC disconnected AND WAN probe failed! Blackout suspected.
[19:35:20] [STATE -> BlackoutPending] Initiating battery debit accumulator (target: 180s).
[19:36:20] [DEBIT] ac_online=0 wan=FAIL debit=60s/180s
[19:38:20] [CRITICAL] Blackout debit threshold reached (3 minutes). Triggering safe shutdown!
[19:38:20] [ACTION: SHUTDOWN] Emitting parallel shutdown signals via Tailscale...
[19:38:21] [SHUTDOWN] Kavure accepted shutdown request (HTTP 200).
[19:38:21] [SHUTDOWN] Psicopompo accepted shutdown request (HTTP 200).
[19:38:40] [CONFIRM] Kavure confirmed offline (S5).
[19:38:45] [CONFIRM] Psicopompo confirmed offline (S5).
[19:38:45] [STATE] Both hosts offline. UPS battery preserved. Transitioning to WaitingForPower.
[19:44:02] [EVENT] AC power detected! Entering stabilization quarantine (target: 180s continuous).
[19:47:02] [STABLE] 3-minute stabilization quarantine completed without fluctuations! Initiating recovery.
[19:47:02] [ACTION: WAKE] Emitting simultaneous WoL magic packets via kururu-wake daemon...
[19:47:35] [SUCCESS] Kavure confirmed online on Tailnet!
[19:47:58] [SUCCESS] Psicopompo confirmed online on Tailnet!
[19:47:58] [RECOVERY] All homelab servers recovered and healthy. Returning to AcNormal state.
```

---

## 5. Deployment & Configuration

### Build Commands (Monorepo)
```bash
# In /mnt/NVME_PCI/homelab/kururu-tab3lite-linux:

# 1. Build kururu-wake with /power/shutdown endpoint (x86_64 for Kavure/Psicopompo)
cargo build --release -p kururu-wake --target x86_64-unknown-linux-musl

# 2. Build kururu-sentinel for Kururu (ARMv7 Alpine musl)
cargo build --release -p kururu-sentinel --target armv7-unknown-linux-musleabihf
```

### Installation on Kururu
* Binary: `/data/alpine/usr/local/bin/kururu-sentinel`
* Persistence Hook: `/system/etc/install-recovery.sh` starts `kururu-sentinel` as a background daemon alongside `kururu-wake` and `kururu-display`.
