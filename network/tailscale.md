---
tags: [homelab, network, tailscale]
---

# Tailscale

**Tailnet:** `chimaera-heptatonic.ts.net`

## Tailnet Node Inventory

| Machine | Tailscale IP | Role |
|---|---|---|
| psicopompo | `100.82.51.112` | Workstation, Dev + GPU worker nodes (StênioBOT) |
| ybytu | `100.115.253.109` | Exit Node, DNS, Peer Relay (`:40000/udp`) |
| ybyra | `100.66.224.34` | Primary Cloud Edge Reverse Proxy |
| kuaray | `100.94.209.99` | Multimedia and Archive Storage Mirror |
| kavure | `100.124.146.77` | Dedicated Services Server, Swarm Manager, Peer Relay (`:40000/udp`), Subnet Router (`192.168.3.0/24`) |
| anansi | `100.71.232.79` | Android Mobile Device |
| kururu | `100.127.188.45` | Headless lightweight probe node (Samsung SM-T110 / Alpine Linux) |

## Access Standard (Tailscale SSH)

**Primary administration access method: Tailscale SSH** — leverages end-to-end WireGuard authentication within the tailnet without exposing TCP port 22 to the public internet.

```bash
tailscale ssh kavure@kavure
tailscale ssh root@kuaray
tailscale ssh ubuntu@ybyra
```

### Check Mode Mitigation → Non-Root `accept` Rule (2026-09-29)

Tailscale's **default ACL** applies `action: check` when connecting to **one's own devices**, requiring **browser re-authentication every 12 hours** (`checkPeriod: 12h`). While manageable for interactive human sessions, this broke headless automation runs: automated scripts like `deploy-swarm.sh` invoking remote SSH commands stalled waiting for interactive authorization links.

**ACL Policy Fix Applied via Tailscale Admin Console** (Access Controls → JSON Editor) on **2026-09-29**: non-root connections proceed directly without re-auth; `root` retains mandatory SSO verification.

```jsonc
"ssh": [
  // 1) Automation and routine non-root access: bypasses browser re-auth prompts
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["autogroup:nonroot"],
  },
  // 2) Root access retains mandatory interactive SSO check (least privilege standard)
  {
    "action": "check",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["root"],
  },
],
```

**Rationale for `autogroup:self` over `tag:server`:** earlier ACL drafts specified `dst: ["tag:server"]`, but no homelab machines carry static tags (`Tags: None` on kavure, psicopompo, and ybyra), rendering tag-based policies ineffective. `autogroup:self` automatically matches all devices owned by the account.

**Policy Syntax Nuances Verified via Official Documentation** ([Tailscale Policy Syntax](https://tailscale.com/kb/1337/policy-syntax)):

| Rule Nuance | Behavior |
|---|---|
| **Evaluation Order** | SSH rules evaluate from most restrictive to least (*check* before *accept*), but match only if the target SSH user is included in `users`. Since `check` lists only `root`, non-root sessions (e.g., `edu`, `kavure`) bypass `check` and match `accept` directly ✅ |
| **`checkPeriod` Attribute** | Available only on Premium/Enterprise plans. In personal accounts, declaring `checkPeriod` may reject policy saves; the 12h default operates implicitly |
| **SSH `dst` Targets** | Accepts tags, `autogroup:self`, or named users; wildcard `*` is prohibited |
| **Remote Username Mapping** | Tailscale authorizes connections only against pre-existing user accounts on the remote host. For example, connecting from kavure via `ssh psicopompo` fails with `tailnet policy does not permit you to SSH as user "kavure"` because no local user `kavure` exists on psicopompo. The correct invocation is `ssh -l edu psicopompo` |
| **CLI Limitations** | `tailscale` CLI (1.102.4) cannot modify ACLs directly — updates require the admin console or API |

**Automated Verification:**

```bash
ssh -o BatchMode=yes kavure 'echo OK'        # Returns OK immediately without web prompts
```

> **Loopback Connection Restriction:** Executing `ssh psicopompo` directly from within psicopompo fails with `Connection refused` because traffic addressed to the local Tailscale IP does not route through `tailscaled`'s netstack. Always test remote access across different nodes.

### ACL GitOps Pipeline (Operational Since 2026-09-29)

The tailnet access control policy is version-controlled inside the **private GitHub repository** [`ceduardorodrig/MNEMOCINE-ACL`](https://github.com/ceduardorodrig/MNEMOCINE-ACL) and deployed via [`tailscale/gitops-acl-action`](https://github.com/tailscale/gitops-acl-action) (`action: test` runs on pull requests; `action: apply` deploys automatically on commits to `main`).

- **OIDC Federated Credentials:** Configured with `policy_file` scope (Issuer `GitHub Actions`).
- **Subject Matching (Immutable Syntax):** Repositories created after July 2026 require the `owner_id/repo_id` format: `repo:ceduardorodrig@276087739/MNEMOCINE-ACL@1396147999:*`.
- **Console Lockout Active:** "Prevent edits in the admin console" is enabled under **Settings → Policy file management**, establishing Git as the single source of truth. Manual modifications in the web console are overwritten on subsequent Git pushes.

### Fallback: Classic Public-Key SSH

When Tailscale SSH cannot be utilized (such as specialized tools expecting raw keypairs), standard SSH with explicit host aliases is configured (`~/.ssh/config` on psicopompo):

```text
Host kavure
    HostName 100.124.146.77
    User kavure
    IdentityFile ~/.ssh/id_ed25519
    PreferredAuthentications publickey
```

## Exit Nodes

| Node | Advertises Exit Node | Egress Route | Operational Guidance |
|---|---|---|---|
| **ybytu** (`100.115.253.109`) | ✅ Yes | Oracle Cloud Transit | **Preferred default** — stable cloud gigabit uplink |
| **kavure** (`100.124.146.77`) | ✅ Yes | Residential WAN (PPPoE 1492) | ⚠️ Routes across local home link; subject to PPPoE MTU constraints (see [`mtu-pppoe.md`](mtu-pppoe.md)) |
| psicopompo | ❌ No | — | Workstation node |

### Exit Node Client Usage

```bash
# List available exit nodes across the tailnet:
tailscale exit-node list

# Route client traffic through ybytu (Oracle Cloud egress):
tailscale set --exit-node=ybytu

# Disable exit node routing:
tailscale set --exit-node=
```

## Subnet Routers (2026-10-05)

**kavure** serves as the authoritative **Subnet Router** for the physical residential LAN (`192.168.3.0/24`), enabling remote access to the home router management portal (`192.168.3.1`), local Tuya IoT hardware, and local network devices without requiring individual Tailscale clients.

| Subnet Router | Advertised Subnet | Local Interface | Route Authorization | NAT Mechanism |
|---|---|---|---|---|
| **kavure** (`100.124.146.77`) | `192.168.3.0/24` | `enp1s0` (Gigabit Ethernet) | `autoApprovers` via GitOps (`MNEMOCINE-ACL`) | Linux Kernel Masquerade (iptables/nftables) |

### Operational Details
- **Masquerade (SNAT):** Outbound traffic from the Tailnet into the home LAN is translated to kavure's local interface IP (`192.168.3.41`). Local devices (such as smart bulbs and the ISP ONT) see incoming requests originating directly from kavure, eliminating the need for custom static routes on the ISP gateway.
- **GitOps Auto-Approval:** The `autoApprovers.routes` stanza in `policy.hujson` automatically validates routes announced by administrative accounts (`autogroup:admin`, `ceduardorodrig@gmail.com`).

### Node Activation on kavure
```bash
# 1. Enable kernel packet forwarding (/etc/sysctl.d/99-tailscale.conf):
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# 2. Advertise the home subnet:
sudo tailscale set --advertise-routes=192.168.3.0/24
```

### Client Route Acceptance
- **Mobile Clients (Android / iOS):** Automatically accept advertised subnet routes.
- **Linux / macOS Clients:**
  ```bash
  tailscale set --accept-routes=true
  ```

### Linux Client Health Notice (`--accept-routes is false`)

Following subnet router deployment on kavure, local Linux nodes (`psicopompo`, `kuaray`, `kururu`) report:
```text
# Health check:
#     - Some peers are advertising routes but --accept-routes is false
```

> **Technical Decision (2026-10-09): Maintain `--accept-routes=false` on Local LAN Machines.**  
> Devices physically connected to the home switch already reside directly within `192.168.3.0/24`. Enabling `--accept-routes=true` on them causes kernel routing rules (`ip rule 5270 lookup 52`) to intercept local LAN packets and hairpin them needlessly through Kavure's tunnel interface. The health warning is advisory and benign; keeping it disabled on local nodes maintains peak physical network throughput.

## Public Funnels & Tunnels

Tailscale Funnels expose designated local ports publicly via TLS without requiring inbound router port forwarding.

| Endpoint | Funnel URL | Target Service |
|---|---|---|
| kavure | `kavure.chimaera-heptatonic.ts.net:10000` | AioStreams (`kavure:3000`) |
| sumaenima (tunnel) | `sumaenima.chimaera-heptatonic.ts.net` | StênioBOT (via container tunnel `sae-edge_tunnel` proxying to `api:9090` on kavure) |
| miracena (tunnel) | `miracena.chimaera-heptatonic.ts.net` | WordPress (via container tunnel `miracena-tunnel` proxying to NPM `:80` → WordPress `:8085`) |

> **Security Policy:** Home Assistant remains **strictly restricted to the tailnet**: `http://100.124.146.77:8123`. No public Funnel is provisioned for Home Assistant.

### Managing Funnels via CLI

```bash
# Expose a local service via Tailscale Funnel:
tailscale funnel --bg 443 http://localhost:PORT

# Inspect active funnel mappings:
tailscale funnel status

# Tear down funnel endpoint:
tailscale funnel off
```

## Peer Relays (High-Throughput Relaying — 2026-10-02)

**Peer Relays** allow tailnet devices to act as high-speed relay intermediaries for peer-to-peer connections when direct UDP traversal is blocked by symmetric CGNAT or restrictive firewalls, routing traffic across private relays before falling back to public DERP servers.

| Host | Tailscale IP | UDP Port | Listening Socket |
|---|---|---|---|
| **ybytu** | `100.115.253.109` | `40000` | `0.0.0.0:40000` / `[::]:40000` (`tailscaled`) |
| **kavure** | `100.124.146.77` | `40000` | `0.0.0.0:40000` / `[::]:40000` (`tailscaled`) |

### Enabling Peer Relay on Host
```bash
sudo tailscale set --relay-server-port=40000
sudo tailscale debug prefs | grep RelayServerPort
sudo ss -ulpn | grep 40000
```

### ACL Capability Grant (`policy.hujson`)
```jsonc
"grants": [
  {
    "src": ["autogroup:member"],
    "dst": ["100.115.253.109", "100.124.146.77"],
    "app": {
      "tailscale.com/cap/relay": []
    }
  }
]
```

To verify active relay traffic:
```bash
tailscale status | grep peer-relay
```
The connection status displays `peer-relay` instead of `relay` (DERP) or `direct`.

## Edge Funnel Authentication (`TS_AUTH_KEY`)

The `sae-edge` stack provisions a containerized `tunnel` instance to publish the primary public gateway using a pre-authenticated Tailscale auth key:
- Centralized inside SOPS secret store (`TS_AUTH_KEY`) and passed into Compose via runtime environment injection (`set -a; source .env`).
- Ephemeral keys are recommended for standby failover instances to prevent orphaned node records upon decommission.
