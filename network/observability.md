---
tags: [homelab, network, monitoring]
pending: [HB-018]
---

# Network Observability — Universal Path-Segment Model

A **durable, reusable** way to understand and troubleshoot the homelab network: model the
path as **segments**, measure every boundary with the **existing** observability stack, and
localise any incident to the failing segment — without guesswork.

> **Design rule — reuse, never a new stack.** Everything here rides on the components that
> already run: **node_exporter** (metrics) → **Prometheus** → **Grafana** → **Alertmanager → ntfy**,
> plus **promtail → Loki** for logs. The only additions are a **config-driven shell collector**
> (`netwatch-metrics.sh`, the homelab textfile-collector standard) and alert/dashboard entries.

## Why a segment model

The network is a chain: **NIC → cable → switch → gateway → uplink → internet → tailnet**.
Measuring only the endpoints ("is the server up?") cannot tell **where** a fault is. Measuring
**every boundary** turns a vague "the network dropped" into a concrete, evidence-backed answer,
and lets us **eliminate variables one by one** (cable, switch, router, ISP, DERP).

The same model stays valid when the ISP, router or physical location changes: only the
**targets config** changes, never the code.

## Segments

| # | Segment | Question it answers | Signal |
|---|---|---|---|
| 1 | **NIC / cable** | Is the physical link healthy? | `node_network_carrier`, `node_network_receive_errs_total`, `homelab_nic_errors` (`ethtool -S`) |
| 2 | **Switch (LAN)** | Can peers on the same switch reach each other by LAN IP? | `homelab_net_ping_*{target="lan_*"}` |
| 3 | **Gateway** | Is the router reachable? | `homelab_net_ping_*{target="gateway"}` |
| 4 | **Uplink / ISP** | Where does loss start? Did the WAN re-dial? | router syslog (session up/down), public-IP changes |
| 5 | **Internet** | Is the raw WAN path lossy? | `homelab_net_ping_*{target="internet_*"}` (multiple diverse targets) |
| 6 | **Tailnet (overlay)** | Are Tailscale peers / the DERP relay reachable? | `homelab_net_ping_*{target="tailnet_*"}`, `homelab_tailscale_health`, Loki (`no-derp-connection`, `derphttp`) |
| 7 | **External witness** | Is the home down as seen **from outside**? | `ybytu` pings the home over the tailnet (`home_*` targets) |

## Implementation

### Collector — `netwatch-metrics.sh`
- **Source of truth:** `MNEMOCINE-OPS/provisioning/scripts/netwatch-metrics.sh`
  (installed by `install-homelab-tools.sh`, `SHELL_TOOLS`).
- **Units:** `MNEMOCINE-OPS/provisioning/systemd/hl-netwatch-metrics.{service,timer}` (every **15 s**).
- **Output:** `/var/lib/node-exporter/textfile/netwatch.prom` → read by the node_exporter
  textfile collector (same mechanism as `health_files.prom`, `smart.prom`, `containers.prom`).

### Targets — `/etc/homelab/netwatch-targets.conf`
One line per probe, `"<segment> <host-or-ip>"`; versioned templates in
`MNEMOCINE-OPS/provisioning/templates/netwatch-targets-<host>.conf`:

| Host | Segments probed |
|---|---|
| **kavure** | `gateway`, `lan_nas`, `tailnet_nas`, `internet_{quad9,cloudflare,google}`, `tailnet_{ybytu,ybyra}` |
| **psicopompo** | `gateway`, `lan_kavure`, `tailnet_kavure`, `internet_{quad9,cloudflare,google}`, `tailnet_{ybytu,ybyra}` |
| **kuaray** | `gateway`, `lan_kavure`, `tailnet_kavure`, `tailnet_psicopompo`, `internet_{cloudflare,google}` |
| **ybyra** (cloud edge) | `gateway`, `internet_{cloudflare,google}`, `tailnet_{kavure,psicopompo,ybytu}` |
| **ybytu** (external witness) | `gateway`, `internet_{cloudflare,google}`, `home_{kavure,psicopompo}_tailnet`, `tailnet_ybyra` |

> **Coverage:** the collector runs on every node with **node_exporter** (5 of 6). **`kururu`** has neither node_exporter nor systemd → not covered yet (HB-018).

> **To adapt to a new ISP / router / house:** edit the `gateway`/`internet_*` lines. To add a
> node, append `tailnet_<name>`. Nothing else changes — the dashboard and alerts are
> label-driven and adapt automatically.

### Metrics reference

| Metric | Labels | Meaning |
|---|---|---|
| `homelab_net_ping_up` | `target` | `1` if the target answered ping |
| `homelab_net_ping_loss_ratio` | `target` | lost fraction (0..1) |
| `homelab_net_ping_rtt_seconds` | `target` | average RTT of answered pings |
| `homelab_nic_errors` | `device`, `type` | raw `ethtool -S` error counter (cable/PHY health) |
| `homelab_tailscale_health` | — | `1` when Tailscale reports no health issue (the benign `--accept-routes` advisory is ignored) |

### Alerts (Alertmanager → ntfy, group `network`)
`NetworkCarrierDown`, `NetworkRxErrors`, `NetworkRxMissed`, `NetPingLoss`,
`TailscaleHealthDegraded` — see [`../services/monitoring.md`](../services/monitoring.md).

### Dashboard
Grafana → **Network Stability** (`uid: network-stability`): reachability, loss, RTT, carrier,
NIC error rate, Tailscale health, and a Loki log panel (Tailscale rebind/DERP, NFS, Swarm,
link down).

## Interpretation table

Read the failing probe; the segment that fails points at the culprit:

| Observation | Conclusion |
|---|---|
| `homelab_nic_errors` / `node_network_*` errors rise, carrier flaps | **Cable / NIC** (segment 1) |
| `lan_*` peer unreachable while `gateway` is fine | **Switch / cable** (segment 2) |
| `gateway` unreachable | **Router / LAN** (segment 3) |
| `internet_*` all fail together while `gateway` is fine | **Uplink / ISP** (segment 4) |
| only one `internet_*` target fails | that **target/route**, not the WAN (segment 5) |
| `tailnet_*` fail / `homelab_tailscale_health=0` while internet is fine | **Tailnet / DERP** (segment 6) |
| `home_*` (ybytu) fails while the home's own probes are fine | the **external path** / cloud side (segment 7) |

> **Correlated failures across hosts** (e.g. two hosts losing the same target at the same
> time) indicate the **shared** segment (WAN or DERP), not the individual host.

## Evidence log (why this exists)

- **2026-10-09/10** — Valheim players dropped; root cause: `kavure` Tailscale
  `netcheck reported send error → Rebind`, cascading to MagicDNS, Swarm and NFS.
- **2026-10-12 12:43** — Swarm `memberlist: Suspect` on kavure/psicopompo/ybyra; root cause:
  the **Tailscale DERP São Paulo relay** reset the connection
  (`derp.Recv ... connection reset by peer`, ~13 s) — a **tailnet** fault, not LAN/WAN.
- Router syslog proved the **WAN session never dropped** in those windows → the losses were
  **degradation**, not a full outage.

## See Also

- [`topology.md`](topology.md) — physical topology, switch, IP allocation
- [`tailscale.md`](tailscale.md) — tailnet, exit nodes, subnet router, peer relays
- [`dns.md`](dns.md) — resolution chain
- [`../services/monitoring.md`](../services/monitoring.md) — the observability stack
- [`../guides/notification-methodology.md`](../guides/notification-methodology.md) — alert policy
