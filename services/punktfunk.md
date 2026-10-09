---
tags: [homelab, service, punktfunk, gaming, psicopompo]
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

## See also

- [[psicopompo]] — Host workstation node
- [[psicopompo-gaming]] — Linux Steam/Proton optimization guide
- [Official Documentation](https://docs.punktfunk.unom.io)
- [GitHub Repository](https://git.unom.io/unom/punktfunk)

## Note: Duplicate HDMI Audio Sinks (GB207)

The NVIDIA GB207 audio controller on psicopompo generates 6 duplicate HDMI sink endpoints in PipeWire (all pointing to monitor C24F390). **This is an upstream NVIDIA driver trait, not a Punktfunk bug**. Resolved by disabling the audio controller in WirePlumber (see [[psicopompo#Audio — Disabled GB207 HDMI Controller]]). Punktfunk allocates independent virtual sound devices (`punktfunk-speaker-*`, `punktfunk-mic`) and operates unaffected.
