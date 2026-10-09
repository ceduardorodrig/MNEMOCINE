---
tags: [homelab, service, kururu, wol, power, monitoring]
---

# Kururu Power Sentinel

Autonomous power outage detection, coordinated safe shutdown, and closed-loop Wake-on-LAN recovery daemon for Mnemocine Homelab.

**Node:** Kururu (Samsung Galaxy Tab 3 Lite SM-T110 / Alpine Linux 3.20 ARMv7)  
**Binary:** `/usr/local/bin/kururu-sentinel` (Rust native, static musl)  
**Target Hosts:** Kavure (`100.124.146.77`), Psicopompo (`100.82.51.112`)  
**Log Path:** `/data/kururu-sentinel.log` (persistent ext4 partition)

---

## 1. Overview & Architecture

Kururu acts as the dedicated **Physical Power Guardian** for the homelab. Because it is a battery-powered tablet consuming <0.8W with an integrated AXP228 PMIC, it remains 100% operational during complete mains power failures without relying on external UPS units.

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

### C. Physical Motion & Dock Baseline Discrimination (Physics-Based Immunity)
To completely prevent false positives when unplugging Kururu for handheld use without relying on fragile network IP addresses or external lamp states:
* While charging on AC (`ac_online == 1`), Kururu's daemon continuously calibrates its **resting dock orientation vector** $\vec{V}_{dock} = (X, Y, Z)$ using a low-pass filter on the hardware 3-axis accelerometer (`/sys/class/sensors/accelerometer_sensor/raw_data`).
* When AC disconnects:
  - **Real Blackout:** The tablet remains resting motionless on its dock/stand. Heavy desk vibrations, cat jumps, or typing settle at $\Delta < 86$ units (well below the $\Delta = 180$ threshold). Kururu detects zero physical pickup ($\Delta < 180$) and **immediately triggers the BlackoutPending countdown**, even if the router is on UPS and WAN internet is still online!
  - **Handheld / Portable Usage:** Physically unplugging the cable and picking up the tablet by hand produces a massive orientation shift ($\Delta \ge 310 - 530$ units). Kururu detects $\Delta \ge 180$, logs `[ASSESSMENT] Confidence: 10%`, and **takes zero shutdown action**.
* **Dock Return Trigger:** If the user is in `PortableUsage` and returns the tablet to its resting dock orientation ($\Delta < 180$) while unpowered, the daemon immediately transitions to `BlackoutPending(StaticDockLostAc)`, triggering safe shutdown even if the cable is dead.

### D. Multi-Variable Confidence Matrix & Decision Weights

To eliminate ambiguity and real-world edge cases, Kururu Sentinel evaluates four independent physical, hardware, and network vectors:

| Vector | Probe Source | Evaluation Weight | Role |
|---|---|---|---|
| **AC Mains Power** | Hardware PMIC (`axp20x-battery/ac_online`) | **Mandatory Gatekeeper** | If AC is online (`1`) and debit is `0`, confidence is strictly **0%**. |
| **Dock Orientation Shift** | 3-axis accelerometer ($\|\vec{V} - \vec{V}_{dock}\|$) | **Primary Discriminator (60%)** | Distinguishes static dock placement ($\Delta < 180$) from human handling ($\Delta \ge 180$). |
| **WAN Internet Reachability** | ICMP probe to `1.1.1.1` and `8.8.8.8` | **Secondary Corroborator (40%)** | Verifies upstream network vitality without relying on local lamp IPs. |
| **Battery Charge Capacity** | Sysfs gauge (`battery/capacity`) | **Safety Watchdog (Veto)** | If battery falls to $\le 20\%$ during battery operation, escalates to `CriticalBattery` shutdown. |

#### Confidence Scoring Matrix

| AC State | Dock Shift ($\Delta$) | WAN State | Battery | Assessment | Confidence | Action / FSM State |
|---|---|---|---|---|---|---|
| **Online (1)** | Any | Any | Any | Mains grid power healthy | **0%** | `AcNormal` (Dynamic dock calibration) |
| **Offline (0)** | $\ge 180$ (Moved) | **Online** | $> 20\%$ | Handheld portable usage | **10%** | `PortableUsage` (Standby, 0 debit) |
| **Offline (0)** | $< 180$ (Static) | **Online** | Any | Power grid lost, router on UPS | **75%** | `BlackoutPending(StaticDockLostAc)` |
| **Offline (0)** | $\ge 180$ (Moved) | **Offline** | Any | Power lost while handheld / Wi-Fi lost | **85%** | `BlackoutPending(WanLostInPortable)` |
| **Offline (0)** | $\ge 180$ (Moved) | Any | $\le 20\%$ | Tablet battery critically low | **95%** | `BlackoutPending(CriticalBattery)` |
| **Offline (0)** | $< 180$ (Static) | **Offline** | Any | Full grid & WAN outage on dock | **100%** | `BlackoutPending(StaticDockLostAc)` |

#### Anti-Bounce Hysteresis & Leaky Bucket Drain
To prevent state thrashing between `PortableUsage` and `BlackoutPending`:
- `StaticDockLostAc` only de-escalates back to `PortableUsage` if a human physically lifts the tablet ($\Delta \ge 180$) **and** WAN remains reachable.
- `WanLostInPortable` only de-escalates back to `PortableUsage` if WAN connectivity recovers.
- `CriticalBattery` never de-escalates unless physical AC power is restored.
- In `BlackoutPending`, detecting AC drains debit at 10s per 5s cycle. It only transitions back to `AcNormal` when debit reaches `0s`.

### E. Native HTTP Control via Tailscale (Zero SSH Complexity)
Shutdown commands do not rely on SSH keys, passphrases, or batch mode. Both Kavure and Psicopompo run `wol-relay` (native Rust on port `9096` as root):
* **Kavure:** `POST http://100.124.146.77:9096/power/shutdown`
* **Psicopompo:** `POST http://100.82.51.112:9096/power/shutdown`
Each node receives the command over Tailscale and executes `shutdown -P now` instantly.

### F. Simultaneous Closed-Loop Recovery
When mains power returns:
1. **Stabilization Quarantine:** Kururu requires **180 continuous seconds of AC power** (`ac_online == 1`). If power cuts during quarantine, the timer resets.
2. **Parallel Wake:** Kururu fires WoL magic packets for **both Kavure and Psicopompo simultaneously** via local `kururu-wake` (`127.0.0.1:9096`).
3. **Closed-Loop Feedback:** Kururu polls their Tailscale IPs every 10 seconds. If a node does not respond within 40 seconds, it re-emits the WoL packet automatically until confirmed alive.

---

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
