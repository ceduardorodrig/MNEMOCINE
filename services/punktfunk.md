---
tags: [homelab, service, punktfunk, gaming, psicopompo]
pending: [HB-122]
---

# Punktfunk

Low-latency remote gaming and desktop streaming suite — host daemon + native client applications.

**Server:** psicopompo  
**Host Port:** `UDP 9777` (punktfunk/1 QUIC)  
**Console Port:** `TCP 47992, 47993` (web console)  
**Console URL:** `https://psicopompo:47992`  

## Stack

| Component | Type | Function |
|---|---|---|
| punktfunk-host | User systemd service | Streaming host daemon (NVENC, virtual displays) |
| punktfunk-web | User systemd service | Web administration console (TanStack) |
| punktfunk-scripting | User systemd service | Scripting and plugin runner (bun) |

## Ports

| Port | Protocol | Function |
|---|---|---|
| 9777 | UDP | punktfunk/1 QUIC (native control & streaming) |
| 5353 | UDP | mDNS host discovery |
| 47990 | TCP | Management API (HTTPS, mTLS/bearer auth) |
| 47992 | TCP | Web console (HTTPS, authentication-gated) |
| 47993 | TCP | Plugin interface bindings |

## Access

- **Console:** `https://psicopompo:47992` (via LAN or Tailscale)
- **Initial Setup:** Generate client pairing PIN within web console
- **Android Client:** Google Play Store → "Punktfunk" → discover host → pair using PIN
- **Linux Client:** `sudo pacman -Syu punktfunk-client` or Flatpak
- **Moonlight:** Fully compatible (set `PUNKTFUNK_GAMESTREAM=1` in `host.env`)

## Configuration

- **host.env:** `~/.config/punktfunk/host.env`
- **GameStream:** Disabled by default (enable via `PUNKTFUNK_GAMESTREAM=1`)
- **HDR:** Unavailable under KDE Plasma (8-bit SDR only; HDR requires gamescope or GNOME 50+)
- **Systemd Linger:** Enabled (`loginctl enable-linger edu` allows background services without active GUI session)
- **Input Group:** User added to `input` group (virtual gamepads via `/dev/uinput`)

## Firewall

```bash
sudo ufw allow punktfunk-native   # UDP 9777, 5353, TCP 47990
sudo ufw allow punktfunk-web      # TCP 47992, 47993
```

## Maintenance

- **Updates:** `sudo pacman -Syu punktfunk-host punktfunk-web punktfunk-scripting`
- **Restart:** `systemctl --user restart punktfunk-host punktfunk-web`
- **Logs:** `journalctl --user -u punktfunk-host -f`
- **Status:** `systemctl --user status punktfunk-host punktfunk-web punktfunk-scripting`

## Troubleshooting: black screen while the session is up (2026-11-09)

Symptom: the client connects, the host reports a complete bring-up (`display_acquired` →
`capture_attached` → `first_frame` → `first_au` → `first_packet` in ~1.5 s), and the screen stays
black. **The host is not at fault, and the log says so:** `forced IDRs are not healing the client —
it loses the repair itself (decoder, receive buffer or link), not a host display disturbance`.

Read the two telemetry lines per session:

```sh
journalctl --user -u punktfunk-host -b | rg 'codec negotiated|link_health|recovery'
```

- **Client cannot decode** → `keyframe_req` climbs (`13`, `24`, `103`) while `egress_mbps` collapses
  to `2.0–2.4` and `loss_windows=0`, `sock_drops=0`, `unrecovered=0`. The host deliberately stops
  pushing because the client's backlog never drains.
- **Healthy** → `keyframe_req=0`, `idr=0`, and the egress matches the adaptive bitrate
  (`169 Mbps`, `372 Mbps`).

Measured on Anansi (the tablet) at **2880x1800@90**: H.265 sessions show black (`keyframe_req=24`,
egress `2.0 Mbps`); **PyroWave** sessions display immediately (`keyframe_req=0`, egress `169 Mbps`).
> **Superseded 2026-11-09 (late, HB-122):** the black screen was the host's **NVENC** encode path, not
> the MTU. Setting the host **Encoder** to **Vulkan** restored the image on the tablet on the first
> try. The last healthy NVENC session was 2026-11-08 01:42; kernel 7.3.3 and `nvidia-utils 620.70.06`
> (RTX 5050) were installed at 03:24 the same night. Read the MTU analysis below as a real but
> secondary defect (the host still logs `CANNOT carry` on the overlay path), not as the root cause.

**The cause was first read as the path MTU, not the client's decoder** — the host says it in one line:

```text
wire MTU: this path CANNOT carry full-size video datagrams — the control plane works but every
video packet is oversized for a hop, which streams as an endless black screen with zero reported
loss. Typical cause: a VPN/overlay adapter (Tailscale / Cloudflare WARP / ZeroTier) claiming the
LAN route, or a lowered NIC MTU. peer=192.168.3.41 discovered_udp_mtu=1233 needed_udp_mtu=1472
```

Both clients reach the host **through the Tailscale overlay** (`peer=100.89.208.75` alongside the LAN
address `192.168.3.41`), so the usable UDP payload is 1233 B instead of the LAN's 1472. Hardware
codecs (H.264/H.265/AV1) do not chunk and their datagrams were oversized; **PyroWave survived
because it is datagram-aligned packetization** (`shard_payload=1186`). The host re-keys mid-session
once it measures the path, but each new host process starts optimistic at 1408 and the first session
of every restart is black again — that is why it looked intermittent.

**Fix tried and reverted 2026-11-09 (HB-122):** `PUNKTFUNK_WIRE_MTU=1200` in `~/.config/punktfunk/host.env`
(backup `host.env.bak-20261109`). **It did not restore the image** — with 1126-byte shards the H.265 session
was still black — and it departs from the house policy (pin the MTU at the interface, never in the app;
[`network/mtu-pppoe.md`](../network/mtu-pppoe.md)). **Reverted the same day** (owner request): `host.env` is
back to the backup, `punktfunk-host` restarted (`systemctl --user is-active` → `active`, shard payload back
to the default). The oversize datagram is a real defect but not the root cause; the investigation
continues from [`temp/handoff-punktfunk-black-screen-20261109.md`](../../temp/handoff-punktfunk-black-screen-20261109.md).
Structural alternative: make LAN clients reach the host over the LAN instead of the overlay — note that
this host's ceiling is **not** 1500: `eno1` is pinned to **1492** (PPPoE policy), so the largest possible
UDP payload is **1464** and a 1472-byte seal is unsatisfiable here no matter the route. Do not
chase capture or the decoder without reading the handoff first: capture, NVENC and transport are clean in
every session (`loss_windows=0`, `sock_drops=0`), and a `grim` capture of the live streamed head shows a
real image.

## Virtual Display Integration with Hyprland, Tablet (Anansi) & Phone (Pira-Nuya)

psicopompo streams via Punktfunk virtual headless outputs (`PF-*`) to both the Samsung Galaxy Tab S9 FE+ ("Anansi", `2880x1800@90Hz`) and the Android phone ("Pira-Nuya", `2712x1220`).

- **Virtual Output:** Designated dynamically as `PF-1` / `PF-2` in Hyprland.
- **Per-Device Scaling (`~/.config/hypr/config/monitors.lua`):** Punktfunk hardcodes `scale = 1` when creating headless monitors. Hyprland listens to `monitor.added` and `config.reloaded` and runs `enforce_virtual_scale()` via `hl.timer` calls:
  - **Anansi (`2880x1800`):** enforces `2880x1800@90`, `position = "auto-right"`, `scale = 1.8` ($1600 \times 1000$ logical resolution, aligning with `HDMI-A-4` 1080p vertical viewport).
  - **Pira-Nuya (`2712x1220`):** enforces `2712x1220@<hz>` (preserves negotiated refresh rate instead of `preferred`, which falls back to `1920x1080` on headless outputs), `position = "auto-right"`, `scale = 2.0` ($1356 \times 610$ exact integer logical resolution).
  - No static `mode = "2880x1800@90"` rule is pinned to `MONITOR2` (`PF-1`), so non-tablet clients never have their resolution overwritten.
- **Topology & Workspaces (`~/.config/punktfunk/display-settings.json` & `~/.config/hypr/config/workspaces.lua`):**
  - `display-settings.json` defaults to `"topology": "auto"` with `"pnp_disable_monitors": true`, which resolves to `"exclusive"` (disables `HDMI-A-4` so the streamed output is the sole display — used by default for Pira-Nuya). Anansi has a per-client override (`"topology": "extend"`, keeping `HDMI-A-4` lit as primary and using the tablet as a second screen, switchable via `punktfunk-host ctl` or web console `:47992`).
  - `workspaces.lua` (`get_display_topology()` + `sync_secondary_workspaces()`) creates persistent workspaces `4`, `5`, `6` on `PF-*` **only when both `HDMI-A-4` and `PF-*` are active simultaneously** (`extend`). In single-screen mode (`exclusive`, where `HDMI-A-4` is disabled), workspaces `1`, `2`, `3` bind to the active `PF-*` screen and `4`, `5`, `6` are torn down.
- **Display Safety:** The tablet's IPS/TFT LCD panel has zero risk of OLED burn-in.

## See also

- [[psicopompo]] — Host workstation node
- [[psicopompo-gaming]] — Linux Steam/Proton optimization guide
- [Official Documentation](https://docs.punktfunk.unom.io)
- [GitHub Repository](https://git.unom.io/unom/punktfunk)

## Note: Duplicate HDMI Audio Sinks (GB207)

The NVIDIA GB207 audio controller on psicopompo generates 6 duplicate HDMI sink endpoints in PipeWire (all pointing to monitor C24F390). **This is an upstream NVIDIA driver trait, not a Punktfunk bug**. Resolved by disabling the audio controller in WirePlumber (see [[psicopompo#Audio — Disabled GB207 HDMI Controller]]). Punktfunk allocates independent virtual sound devices (`punktfunk-speaker-*`, `punktfunk-mic`) and operates unaffected.
