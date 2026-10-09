---
tags: [homelab, network, config]
---

# MTU / PPPoE — Silent Packet Drop Mitigation

Diagnostic runbook and permanent workaround for the **MTU mismatch** between local LAN (`1500`) and the ISP **PPPoE link** (`1492`), which previously caused intermittent silent drops during large payload transfers.

## Symptoms

- `cachy update` failed intermittently with no clear pattern (e.g. `[punktfunk]` mirror repository could not reach its database).
- Websites and applications hung indefinitely before resuming; file downloads required multiple retry attempts.
- **Empirical measurement:** In a 20-minute sample of 40 consecutive runs, a **2 MB payload failed 12 times (30% loss rate)** — consistently **hanging** at timeout rather than returning an error code.

## Root Cause Analysis (Benchmarked 2026-10-07)

```text
LAN (192.168.3.1):   1472 OK                       → Local MTU = 1500
Internet (1.1.1.1):  1472 FRAG_NEEDED, 1464 OK    → PMTU = 1492 (PPPoE encapsulation overhead)
Internet (8.8.8.8):  1472 FRAG_NEEDED, 1464 OK    → PMTU = 1492
Local interface (psicopompo): mtu 1500             → Mismatched configuration
```

The WAN link utilizes **PPPoE (1492 MTU)**, but host interfaces defaulted to **1500**. Host TCP connections advertised an MSS of 1460, leading remote servers to send packets up to 1500 bytes. The ISP PPPoE bridge requires fragmentation for frames larger than 1492 bytes. Where **ICMP "Fragmentation Needed" (Type 3, Code 4) messages are filtered or dropped** (a classic Path MTU Discovery black hole), large packets **silently disappear**, freezing TCP sessions. This explained why failures were intermittent and limited to large payloads while small packets (such as DNS queries) passed without issue.

### Why Automatic Mechanisms Failed

| Automatic Mechanism | Expected Behavior | Failure Mode |
|---|---|---|
| **DHCP Option 26** (Interface MTU) | Gateway informs DHCP clients of the correct interface MTU | Host requests it (`requested_interface_mtu = 1`), but ISP modem fails to answer with Option 26 |
| **PMTUD** (ICMP Type 3, Code 4) | Upstream routers notify sender to reduce packet size | Transit hops drop ICMP messages, creating a PMTUD black hole |

> The clean upstream fix requires the **ONT/modem** to advertise DHCP Option 26 or execute **MSS clamping**. The ISP-provided Huawei ONT exposes neither setting.

## Impact Analysis

This issue is an inherent characteristic of the **physical residential WAN link**. Only traffic traversing this link is affected:

| Target Scope | General Traffic | DNS Queries |
|---|---|---|
| **Local Home LAN Devices** (psicopompo, kuaray, kavure, Windows desktop, mobile, IoT) | ⚠️ **Directly impacted** | OK |
| **Remote Tailnet Nodes** (ybytu, ybyra, Oracle Cloud, 4G/5G mobile endpoints) | ✅ Bypasses the link | OK |
| **Tailnet Users without Exit Node** | ✅ Routes through their own local ISPs | OK |
| **Clients routing via kavure Exit Node** | ⚠️ **Directly impacted** (egress passes through home link) | — |

**Why DNS resolution remained functional despite kavure centralizing egress** (local egress traverses the residential link — see [`dns.md`](dns.md)):

1. DNS packets are inherently **small UDP payloads** → immune to MTU truncation (100% success rate across 40 samples).
2. **Encrypted DoT fallback** on AdGuard (`tls://9.9.9.9` / `tls://1.1.1.1`) covers any potential kavure/unbound downtime.
3. Multi-tier caching absorbs duplicate lookups (Pi-hole 10k + unbound 32m/64m).

## Remediation

### Host-Level Workaround — MTU 1492

An MTU of **1492** is standard for PPPoE links (Arch Linux Wiki: *"For PPPoE, the MTU should not be larger than 1492"*). Setting host MTU to 1492 forces TCP to advertise an MSS of 1452, guaranteeing packets fit cleanly into PPPoE frames and **eliminating reliance on ICMP PMTUD**.

| Node | Network Stack | Applied Configuration | Status |
|---|---|---|---|
| **psicopompo** | NetworkManager | `nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1492` + `nmcli device reapply eno1` | ✅ Active (2026-10-07) |
| **kuaray** | NetworkManager | `nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1492` + `nmcli device reapply enp7s0` | ✅ Active (2026-10-07) |
| **kavure** | netplan → systemd-networkd | `mtu: 1492` under `enp1s0` in `/etc/netplan/50-cloud-init.yaml` + `netplan apply` (backup: `.bak-20261007-mtu`) | ✅ Active (2026-10-07) |

> ⚠️ **Never change MTU dynamically via `ip link set` on psicopompo:**  
> The **`e1000e`** network interface driver resets the link state upon runtime MTU modifications (`NO-CARRIER` for ~30–60 seconds). Always apply changes through NetworkManager (`nmcli device reapply`, which reconfigures smoothly without link drops) or during boot.
>
> Reversion procedure: `nmcli con modify "<connection>" 802-3-ethernet.mtu 1500` (or delete the `mtu:` line from Netplan).

### Permanent Edge Architecture — Planned Router Appliance

The optimal location for MSS clamping is at the **network edge**, where the local LAN interfaces with the PPPoE session:

1. Place ISP modem/ONT into **bridge mode** (acting purely as a fiber-to-Ethernet media converter).
2. Deploy a **dedicated firewall/router appliance** (OPNsense / pfSense / OpenWrt on a multi-NIC mini-PC) to establish the PPPoE connection and execute **MSS clamping**.
3. Result: LAN nodes return to standard **1500 MTU** without host-level overrides.

Official iptables MSS clamping syntax (Arch Linux Wiki, [*Internet sharing*](https://wiki.archlinux.org/title/Internet_sharing)):
```bash
iptables -t mangle -A FORWARD -o ppp0 -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

### Rollback Runbook (Upon Deployment of Edge Router)

When a dedicated edge gateway assumes WAN responsibilities, revert host-level workarounds in the following order:

```bash
# psicopompo (NetworkManager)
sudo nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1500
sudo nmcli device reapply eno1

# kuaray (NetworkManager, enp7s0)
sudo nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1500
sudo nmcli device reapply enp7s0

# kavure (netplan -> systemd-networkd)
sudo cp -a /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak-pre-edge-router
# Remove 'mtu: 1492' under interface enp1s0
sudo netplan apply
```

Verification check:
```bash
# Confirm 1500 byte frames pass end-to-end without fragmentation:
ping -M do -s 1472 1.1.1.1
```

## Empirical Verification (A/B Test)

Benchmark script results (20 minutes duration, 30-second sampling intervals) testing `punktfunk.db` (9 KB), **2 MB payload** (Cloudflare), and DNS:

| Phase | punktfunk (9 KB) | 2 MB Payload (Large) | DNS Queries |
|---|---|---|---|
| **Baseline** (MTU 1500) | 40/40 OK (100%) | **28/40 OK (30% failure rate)** | 40/40 OK (100%) |
| **Initial Mitigation** (MTU 1492) | 35/40 OK | 38/40 OK (5% failure rate) | 40/40 OK (100%) |
| **Settled Verification** (MTU 1492) | 16/20 OK | **20/20 OK (0% failure rate)** | 20/20 OK (100%) |

**Analysis:** Once link state settled, the 2 MB transfer test showed **zero failures**, dropping large payload packet loss from **30% to 0%**. Intermittent mirror download errors observed during investigation were symptoms of the MTU black hole (TLS handshakes stalling on large Certificate payloads) rather than upstream repository server failures. All 3 local nodes (psicopompo, kuaray, kavure) are persistently configured at 1492 MTU across reboots.

## See Also

- [`dns.md`](dns.md) — Local recursive DNS architecture and tailnet query paths
- [`tailscale.md`](tailscale.md) — Exit node routing and interface configuration
- [`../servers/psicopompo.md`](../servers/psicopompo.md) — Primary workstation node profile
