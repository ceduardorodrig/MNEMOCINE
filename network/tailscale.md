---
tags: [homelab, network, tailscale]
---

# Tailscale

**Tailnet:** chimaera-heptatonic.ts.net

## Machines on the Tailnet

| Machine | Tailscale IP | Role |
|---|---|---|
| psicopompo | `100.82.51.112` | Dev + GPU workers (StênioBOT) |
| ybytu | `100.115.253.109` | Exit Node, DNS |
| ybyra | `100.66.224.34` | Cloud — primary edge |
| kuaray | `100.94.209.99` | Media — Funnel Home Assistant |
| kavure | `100.124.146.77` | Dedicated services server (Project Zomboid, panel, aiostreams, comet) |
| anansi | `100.71.232.79` | Android |

## Access Pattern (Tailscale SSH)

**Default method to access the servers: Tailscale SSH** — uses tailnet authentication (WireGuard), without exposing port 22 to the internet.

```bash
tailscale ssh kavure@kavure
tailscale ssh root@kuaray
tailscale ssh ubuntu@ybyra
```

### Check mode (periodic reauth)

The Tailscale **default ACL** uses `action: check` to connect to **your own devices** → it asks for **browser reauthentication every 12h** (`checkPeriod` default). This is expected behavior.

- **For users:** fine (confirm in the browser every 12h).
- **For AI agents/headless automation:** they cannot click the link → fix with an **`action: accept`** rule in the ACL (no check) for the agent's host → `dst`. E.g.:

```json
"ssh": [
  {
    "action": "accept",
    "src": ["user:ceduardorodrig@gmail.com"],
    "dst": ["tag:server"],
    "users": ["autogroup:nonroot"]
  }
]
```

### Fallback: classic SSH with key

When Tailscale SSH is not viable (e.g. automation, a tool that needs a key), use **classic SSH with a per-host key** — repo standard (`~/.ssh/config` on psicopompo):

```
Host kavure
    HostName 100.124.146.77
    User kavure
    IdentityFile ~/.ssh/id_ed25519
    PreferredAuthentications publickey
```

> **A fixed LAN IP is not needed** — the tailnet IP (100.x) is fixed and stable, independent of DHCP.

## Exit Nodes

| Server | Status | Traffic |
|---|---|---|
| psicopompo | ❌ (does not offer) | — |
| ybytu | ✅ Active (**only** exit node) | Tailnet traffic |

### Usage

On any client machine on the tailnet:

```bash
# Listar exit nodes disponíveis
tailscale exit-node list

# Usar ybytu como exit node (único exit node da tailnet)
tailscale set --exit-node=ybytu

# Parar de usar exit node
tailscale set --exit-node=
```

## Funnels

Funnels expose local services publicly (via Tailscale) without needing to open ports on the router.

| Server | Funnel | Internal Service |
|---|---|---|
| kavure | `kavure.chimaera-heptatonic.ts.net:10000` | AioStreams (`kavure:3000`) |
| sumaenima (tunnel) | `sumaenima.chimaera-heptatonic.ts.net` | StênioBOT (via tunnel `sae-edge_tunnel`, proxy to `api:9090` on kavure) |
| miracena (tunnel) | `miracena.chimaera-heptatonic.ts.net` | WordPress (via tunnel `miracena-tunnel`, proxy to NPM `:80` → WordPress `:8085`) |

> **Home Assistant** is **tailnet-only** access: `http://100.124.146.77:8123`. No public Funnel — access restricted to the tailnet for security.

### Configuring a Funnel

```bash
# Expor serviço local via funnel
tailscale funnel --bg 443 [--set-path /] http://localhost:PORTA

# Ver status
tailscale funnel status

# Remover
tailscale funnel off
```

### Tailscale Tunnel (Docker container)

For services that need their own hostname on Tailscale (e.g. `miracena.chimaera-heptatonic.ts.net`), create a dedicated Tailscale container:

```yaml
# Exemplo: miracena-tunnel
tunnel:
  image: tailscale/tailscale:latest
  container_name: miracena-tunnel
  hostname: miracena
  environment:
    - TS_AUTH_KEY=${TS_AUTH_KEY}
    - TS_HOSTNAME=miracena
    - TS_SERVE_CONFIG=/etc/tailscale/serve.json
    - TS_STATE_DIR=/var/lib/tailscale
    - TS_USERSPACE=false
  volumes:
    - ./tailscale:/etc/tailscale
    - tailscale_state:/var/lib/tailscale
  cap_add: [NET_ADMIN, SYS_MODULE]
  sysctls:
    - net.ipv4.ip_forward=1
    - net.ipv6.conf.all.forwarding=1
```

The `serve.json` defines how the Funnel routes traffic:

```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://servico:porta" } }
    }
  },
  "AllowFunnel": { "${TS_CERT_DOMAIN}:443": true }
}
```

**Limitation:** Tailscale MagicDNS does not support subdomains (`site.miracena.xxx` does not resolve). Each tunnel only registers one hostname. For multiple public services, use NPM as a reverse proxy at the Funnel destination.

## Serve (internal network)

No serve configured currently (only funnels for external exposure).

## Server Configuration

### IP Forwarding (for Exit Nodes)

Enabled on **ybytu** (only exit node):

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### Key Expiry

Disabled on the servers via the Tailscale admin console.
