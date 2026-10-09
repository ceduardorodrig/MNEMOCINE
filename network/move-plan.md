---
tags: [homelab, network, storage, todo]
---

# Physical Relocation & Target Network Architecture Plan

Strategic planning for deploying homelab infrastructure in a new residential environment. Given current infrastructure maturity — operating critical workloads including StênioBOT, containerized game servers, Home Assistant IoT automation, and Tailscale zero-trust networking — the primary architectural focus is **strict network layer isolation**.

## Target Architecture: Edge Bridge & Dedicated Gateway Router

To achieve total routing control and operational stability, the setup avoids relying on ISP-provided routers for LAN management, adopting a **Modem Bridge + Dedicated Router Appliance** design:

```text
[External WAN / Fiber Link] 
          │
          ▼
[ISP ONT / Modem] ──(Bridge Mode)──> [Dedicated Router / Firewall]
                                                │
       ┌────────────────────────────────────────┴────────────────────────────────────────┐
       ▼                                        ▼                                        ▼
[IoT / Automation VLAN]                  [Wired Gigabit LAN]                     [Primary Wi-Fi SSID]
(Sensors, MQTT, HA)                      (Psicopompo, Kavure, Kuaray)            (Laptops, Mobile Devices, Consoles)
```

### 1. Dedicated Gateway Router Appliance

Deploy a dedicated multi-NIC device running **OPNsense / pfSense** or an open router running **OpenWrt**:

- **Execution:** Configure the ISP ONT into **Bridge Mode** (acting purely as a fiber-to-Ethernet transceiver) and pass WAN termination to the dedicated router.
- **Advantage:** The dedicated appliance serves as the central brain of the local network. Future ISP changes require only updating WAN interface parameters without touching internal LAN configurations.

### 2. VLAN Network Segmentation (IoT Isolation)

Smart home automation hardware (Wi-Fi bulbs, third-party sensors) often runs proprietary closed-source firmware:

- **Execution:** Create an isolated **IoT VLAN** for automation hardware and the Home Assistant integration bridge.
- **Advantage:** IoT peripherals communicate with Home Assistant while remaining strictly isolated from workstation endpoints (Psicopompo) and private storage shares.

### 3. Native IPv6 with Tailscale Routing

When contracting a new ISP, prioritize providers offering native dual-stack IPv6:

- **Execution:** Configure the gateway to receive native IPv6 prefix delegations.
- **Advantage:** Eliminates dual-NAT routing quirks, accelerates cloud sync, and enables clean end-to-end peer connections across the Tailnet.

## Relocation Work Breakdown

Leveraging **Docker Compose** and **Tailscale** minimizes migration overhead:

### Tier 1: Application Containers & Services (Effort: 5%)
- Workloads are fully containerized. Once hardware nodes power up, Docker Compose daemons automatically initialize databases, game servers, and background workers without manual reconfiguration.
- Tailscale discovers nodes across any WAN IP and re-establishes WireGuard tunnels transparently.

### Tier 2: Physical Cabling & Wireless Provisioning (Effort: 40%)
- Deploy physical Cat6 Ethernet runs from the central switch to Psicopompo and Kavure.
- **Golden Rule for Wi-Fi Migration:** Configure the new access points with the **exact same SSID and WPA2/WPA3 passphrase** as the existing setup. All smart bulbs, tablets, and media devices reconnect automatically without manual device resetting.

### Tier 3: Subnet Realignment & Local DNS (Effort: 55%)
- Align static IP assignments if the local LAN subnet transitions to a new CIDR range (e.g. from `192.168.3.0/24` to `192.168.1.0/24`).
- Update local DHCP options to point DNS queries toward the kavure Pi-hole resolver for local network ad filtering.