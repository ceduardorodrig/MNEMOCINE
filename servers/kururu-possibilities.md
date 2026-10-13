---
tags: [homelab, server, kururu, roadmap]
---

# Kururu — 20 Possibilities Catalog & Strategic Roadmap

This document catalogs **20 tangible and strategic use cases** for the **Kururu** node (Samsung Galaxy Tab 3 Lite 7.0 / SM-T110), capitalizing on its bare-metal Linux architecture (Alpine v3.20 on Samsung Linux 3.4.5), **>770 MB of unallocated RAM**, and integrated sensors and hardware peripherals.

---

## 🧰 Integrated Hardware Capabilities

Unlike standard x86 servers or single-board computers (Raspberry Pi, Orange Pi), Kururu bundles integrated hardware peripherals out of the box:

1. **Hardware UPS / Battery Buffer (~3,600 mAh Li-ion):** Survives power spikes, brownouts, and total grid collapse, operating continuously for hours without utility power.
2. **Integrated 7-Inch Color Display (1024x600, 32bpp):** Direct frame-buffer access (`/dev/graphics/fb0`) with zero X11, Wayland, or desktop compositor overhead.
3. **Physical Buttons (`/dev/input/`):** Dedicated Power and Volume Up/Down keys for tactile hardware interaction.
4. **Negligible Power Draw (< 0.8W):** Annual operating cost under $1 USD.
5. **3.5mm Audio Jack & Integrated Speaker:** Hardware sound generation for audible infrastructure alerts and synthesized voice.
6. **Micro-USB Host/OTG Support:** Enables USB-Serial adapters, LoRa transceivers, or hardware key fobs.

---

## 🧭 Catalog of 20 Possibilities

### Category A: High Availability, Quorum & Electrical Resilience

#### 1. Blackout Sentinel ("Dead Man's Snitch" / Power Outage Monitor)
- **Concept:** Kururu is the **sole node with an integrated battery**.
- **Implementation:** A lightweight Rust daemon pings the 5 AC-powered nodes (`psicopompo`, `kavure`, `kuaray`, `ybytu`, `ybyra`) and the LAN router (`192.168.3.1`). If all AC hosts drop simultaneously, Kururu detects a **grid power failure** and dispatches high-priority push notifications over mobile networks or local relays before cell tower batteries drain.

#### 2. Quorum Witness (Cluster Tie-Breaker)
- **Concept:** Fault-tolerant architectures (etcd, Raft, Corosync) require an odd number of voting members to avoid split-brain states.
- **Implementation:** Serves as a neutral, low-power voter maintaining cluster consensus without spinning up heavy x86 hosts.

#### 3. Resilient Secondary DNS Resolver (Blocky / Unbound)
- **Concept:** Uninterruptible local name resolution and ad-blocking.
- **Implementation:** Secondary DNS listener on `192.168.3.55`, ensuring home devices retain name resolution even while primary server hosts reboot for kernel updates.

#### 4. Emergency Offline Secret Vault
- **Concept:** Read-only encrypted static backup of SOPS/age keys, Tailscale machine keys, and emergency SSH certificates.

---

### Category B: Visual Telemetry & Physical Interaction

#### 5. Interactive NOC Desk Dashboard (Volume Key Navigation)
- Dynamic page switching across the 7" display: Cluster node status, Docker service health, GPU thermal monitoring, and retro phosphor clocks.

#### 6. 3D Printer Status Kiosk (Moonraker / Klipper API)
- Real-time layer progress, nozzle/bed temperatures, and print timers.

#### 7. WAN Latency & Packet Loss Monitor (Ping Matrix)
- Continuous historical visual graphing of fiber connection jitter and packet loss across upstream DNS targets.

#### 8. Standalone Focus & Pomodoro Display
- Clean, non-distracting 25-minute countdown clock triggered via physical hardware button.

---

### Category C: Audio & Physical Notification

#### 9. Homelab Incident Siren (Audio Alert Soundbox)
- Audible diagnostic tones via internal speaker or 3.5mm jack: completed backup notifications, new device join alerts, or thermal emergency alarms.

#### 10. Self-Hosted Push Gateway (Ntfy Instance)
- Sovereign notification broker decoupled from external third-party mobile notification infrastructure.

#### 11. Wireless Audio Receiver (Snapcast / Shairport-Sync)
- Network streamer feeding analog speakers via 3.5mm jack.

#### 12. Procedural White Noise & Ambient Generator
- Offline background audio generator operating at <1% CPU utilization.

---

### Category D: Networking & Home Automation

#### 13. Resilient Wake-on-LAN Relay (LAN Broadcast Node) ⚡
- Always-on relay node capable of dispatching L2 Ethernet magic packets across the local subnet to wake sleeping nodes (`psicopompo`, `kavure`).

#### 14. Lightweight MQTT Message Broker (Mosquitto / Rumqttd)
- Sub-4MB RAM broker coordinating IoT switches and temperature sensors.

#### 15. Emergency Tailnet Subnet Router
- Contingency gateway advertising `192.168.3.0/24` to access router admin panels during network failures.

#### 16. Lightweight Automation Webhook Receiver
- Endpoint for external GitHub or Home Assistant action hooks.

---

### Category E: Diagnostics & Hardware Interfacing

#### 17. Portable Serial Terminal for Switches & Routers (USB-OTG TTY)
- Portable screen and terminal interface for console debugging on managed network switches.

#### 18. Local Emergency Netboot / iPXE Server
- Servicing recovery boot images (Clonezilla, MemTest86+) over TFTP/HTTP across the local switch.

#### 19. Off-Grid LoRa / Reticulum Emergency Gateway
- Paired with USB LoRa modules to act as a resilient emergency messaging transceiver.

#### 20. Continuous Governance Health Auditor (StenioWorker)
- Periodic execution of static health sweeps across cluster nodes, reporting certificate expiry and backup anomalies.

---

## 🗺️ Priority Roadmap Matrix

| Feature | Complexity | Impact | Action Item |
|---|---|---|---|
| **Resilient WOL Relay (#13)** | Low | **Critical** | Native `wake` command using stored MAC tables in secure vault. |
| **Interactive Hardware Dashboard (#5)** | Medium | **High** | Handle `/dev/input/event0` to switch dashboard views. |
| **Power Failure Sentinel (#1)** | Low | **High** | Heartbeat monitoring script alerting on AC power loss. |
| **Audible Alerts via ALSA (#9)** | Low | **Medium** | Kernel audio driver verification for backup status tones. |
| **Secondary Local DNS (#3)** | Medium | **High** | Static ARMv7 DNS binary deployment. |

## References

- [`servers/kururu.md`](kururu.md) — Primary node documentation
- [`services/wol-relay.md`](../services/wol-relay.md) — Wake-on-LAN architecture
- [GitHub: KURURU-TAB3LITE-LINUX](https://github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX)
