---
tags: [homelab, service, punktfunk, gaming, psicopompo]
---

# Punktfunk

Low-latency game/desktop streaming — host + native clients.

**Server:** psicopompo
**Host Port:** `UDP 9777` (punktfunk/1 QUIC)
**Console Port:** `TCP 47992, 47993` (web console)
**Console URL:** `https://psicopompo:47992`

## Stack

| Component | Type | Role |
|---|---|---|
| punktfunk-host | systemd user service | Streaming host (NVENC, virtual displays) |
| punktfunk-web | systemd user service | Web console (TanStack, management) |
| punktfunk-scripting | systemd user service | Plugin/script runner (bun) |

## Ports

| Port | Protocol | Role |
|---|---|---|
| 9777 | UDP | punktfunk/1 QUIC (native control) |
| 5353 | UDP | mDNS discovery |
| 47990 | TCP | Management API (HTTPS, mTLS/bearer) |
| 47992 | TCP | Web console (HTTPS, login-gated) |
| 47993 | TCP | Plugin interfaces |

## Access

- **Console:** `https://psicopompo:47992` (over LAN or Tailscale)
- **First access:** generate a pairing PIN in the console
- **Android client:** Google Play → "Punktfunk" → discover the host → pair with the PIN
- **Linux client:** `sudo pacman -Syu punktfunk-client` or Flatpak
- **Moonlight:** compatible (enable `PUNKTFUNK_GAMESTREAM=1` in `host.env`)

## Configuration

- **host.env:** `~/.config/punktfunk/host.env`
- **GameStream:** disabled by default (enable with `PUNKTFUNK_GAMESTREAM=1`)
- **HDR:** unavailable with KDE Plasma (SDR 8-bit only; HDR requires gamescope or GNOME 50+)
- **Linger:** enabled (services run without a login session)
- **Input group:** added (virtual gamepads via `/dev/uinput`)

## Firewall

```bash
sudo ufw allow punktfunk-native   # UDP 9777, 5353, TCP 47990
sudo ufw allow punktfunk-web      # TCP 47992, 47993
```

## Maintenance

- **Update:** `sudo pacman -Syu punktfunk-host punktfunk-web punktfunk-scripting`
- **Restart:** `systemctl --user restart punktfunk-host punktfunk-web`
- **Logs:** `journalctl --user -u punktfunk-host -f`
- **Status:** `systemctl --user status punktfunk-host punktfunk-web punktfunk-scripting`

## See also

- [[psicopompo]] — host server
- [[psicopompo-gaming]] — Steam/Proton setup on Linux
- [Official documentation](https://docs.punktfunk.unom.io)
- [GitHub](https://git.unom.io/unom/punktfunk)

## Note: duplicated HDMI sinks (GB207)

psicopompo's NVIDIA GB207 audio card produces 6 duplicated HDMI sinks in PipeWire (all to the same C24F390 monitor). This is **not a Punktfunk bug** — it is NVIDIA driver behavior. Fixed by disabling the card via WirePlumber (see [[psicopompo#Audio — GB207 HDMI Disabled (01/09/2026)]]). Punktfunk uses its own virtual devices (`punktfunk-speaker-*`, `punktfunk-mic`) and is unaffected.
