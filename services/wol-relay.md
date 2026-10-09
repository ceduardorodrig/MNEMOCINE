---
tags: [homelab, service, wake-on-lan, wol, power, psicopompo, kavure, kururu]
---

# Wake-on-LAN Relay

Lightweight remote power management service that wakes physical servers via Magic Packets (WoL), accessible securely over the Tailscale mesh.

**Host Nodes:** kururu (24/7 dedicated sender with battery backup) / kavure / psicopompo  
**Status (Validated 2026-10-02):** Validated end-to-end across both x86 hosts — psicopompo powers on within **54 seconds** and kavure within **29 seconds** from S5 soft-off without physical interaction.

## Three-Tier Redundant Architecture

A single native Rust daemon (`kururu-wake`) deployed across three nodes:

```text
                              Homepage / Remote Client
                                          │
                                          ▼
                            ybytu (Smart Dispatcher 24/7)
                                  100.115.253.109:9096
                                   /             \
                  (Primary 24/7)  /               \ (Automatic Fallback)
                                 ▼                 ▼
              kururu (24/7 + Battery) ── Wakes ──► psicopompo  AND  kavure
                          │
        ┌─────────────────┴─────────────────┐
        ▼                                   ▼
  psicopompo ◄─────── Wakes ──────────► kavure
        ▲             (Peer-to-Peer)        │
        └───────────── Wakes ───────────────┘
```

> **Remote Dispatch Routing:** Homepage directs wake requests to the **Smart Dispatcher** running on `ybytu` (`100.115.253.109:9096`). The dispatcher routes first to **kururu**; if kururu is unreachable, it automatically falls back to waking via the alternate x86 peer node.  
> **Quorum of 3:** Maintaining any single alive node on the LAN enables waking the other two hosts.

| Component | Implementation |
|---|---|
| Cloud Smart Dispatcher | `wol-relay --dispatcher` (Native Rust, port `9096` on `ybytu`) |
| Canonical 24/7 LAN Sender | `kururu-wake` (Native Rust, port `9096` on `kururu`) |
| Redundant Peer Sender (psicopompo) | `wol-relay` (Native Rust binary, port `9096`) |
| Redundant Peer Sender (kavure) | `wol-relay` (Native Rust binary, port `9096`) |
| System Daemons | `wol-dispatcher.service` (ybytu) / `wol-relay.service` (x86) / `/system/etc/install-recovery.sh` (kururu) |
| NIC State Persistence | `wol@.service` + native network manager configurations (NetworkManager / Netplan) |
| Security Perimeter | Binds to `127.0.0.1` + Tailscale Serve on x86; binds to Tailscale IP on ybytu |

## Target Nodes & Physical MAC Addresses

| Node | Interface | Physical MAC | Tailscale IP | Operational Role |
|---|---|---|---|---|
| **kururu** | `mlan0` | `24:f5:aa:7c:e3:1e` | `100.127.188.45` | **Primary 24/7 Sender** (`kururu-wake`) — Wakes both hosts |
| **psicopompo** | `eno1` | `d0:94:66:de:8b:58` | `100.82.51.112` | Redundant sender (wakes **kavure**) and wake target |
| **kavure** | `enp1s0` | `d0:94:66:ad:f3:c4` | `100.124.146.77` | Redundant sender (wakes **psicopompo**) and wake target |

## Configuration Files

### Target Mapping (`/etc/kururu-wake.conf`)

**kururu** (Wakes both targets):
```text
psicopompo=d0:94:66:de:8b:58
kavure=d0:94:66:ad:f3:c4
```

**psicopompo** (Wakes peer):
```text
kavure=d0:94:66:ad:f3:c4
```

**kavure** (Wakes peer):
```text
psicopompo=d0:94:66:de:8b:58
```

## API Specifications

### Canonical Daemon (Kururu & x86 Peers)

| Endpoint | Method | Action | Example Response |
|---|---|---|---|
| `GET /wake/<host>` | GET | Broadcasts Magic Packet to target host | `{"status":"ok","target":"kavure","mac":"d0:94:66:ad:f3:c4","emitted":true}` |
| `GET /health` | GET | Health verification probe | `{"status":"online","service":"kururu-wol-relay","node":"kururu"}` |
| `GET /wake/<self>` | GET | Blocked loopback target | `{"status":"error","message":"Target '<host>' not found ..."}` (404 by design) |

## NIC WoL State Persistence

Runtime invocations of `ethtool -s <iface> wol g` do not survive reboots. Two-tier persistence guarantees `Wake-on: g` after cold starts:

1. **Native Network Stack:**
   - psicopompo (NetworkManager): `nmcli c modify "Wired connection 1" 802-3-ethernet.wake-on-lan magic`
   - kavure (Netplan): `wakeonlan: true` under `enp1s0` in `/etc/netplan/50-cloud-init.yaml`
2. **Systemd Template Service (`/etc/systemd/system/wol@.service`):**
   ```ini
   [Unit]
   Description=Enable Wake-on-LAN (magic packet) on %I
   After=network.target
   Wants=network.target

   [Service]
   Type=oneshot
   ExecStart=/usr/bin/ethtool -s %I wol g

   [Install]
   WantedBy=multi-user.target
   ```
   Activated with `sudo systemctl enable --now wol@<interface>`.

## Troubleshooting & Hardware Considerations

### Dell BIOS Standby Power Issue
- On Dell OptiPlex 3060 hardware, **`Deep Sleep Control`** defaults to "Enabled in S4 and S5", completely powering down the Ethernet PHY in soft-off states.
- **Resolution:** In BIOS setup, set `Deep Sleep Control = Disabled` while verifying `Wake on LAN` and `AC Recovery` remain enabled.

## Operational Commands

```bash
# Check daemon status on x86 node:
systemctl status wol-relay

# Test local loopback wake:
curl http://127.0.0.1:9096/wake/kavure

# Verify Tailscale Serve endpoint:
curl http://100.82.51.112:9096/health
```

## See Also
- [`../../servers/kavure.md`](../../servers/kavure.md) — Kavure dedicated server profile
- [`../../servers/psicopompo.md`](../../servers/psicopompo.md) — Psicopompo workstation profile
- [`../../servers/kururu.md`](../../servers/kururu.md) — Kururu 24/7 headless probe node
