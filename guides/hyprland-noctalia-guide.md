---
tags: [homelab, hyprland, noctalia, guide, cachyos, gpu]
created: 2026-09-21
---

# Hyprland + Noctalia Desktop Guide — CachyOS (psicopompo)

Operational and architectural manual for Hyprland paired with the Noctalia desktop shell on CachyOS.

## Core Concepts

psicopompo runs Hyprland configured with the **native `scrolling` layout (Niri / PaperWM style)** (canonized 2026-09-27) — windows are arranged across a continuous horizontal ribbon of columns that glides smoothly across the viewport, supporting vertical window stacking within columns. The **Super** (Windows) key serves as the primary modifier.

## Display Manager & Login Sessions

System authentication is managed by the **Noctalia Greeter** (`greetd`, installed 2026-09-22, replacing KDE plasmalogin). Available sessions:

| Session Option | Description |
|---|---|
| **Hyprland (uwsm-managed)** | ✅ Recommended default — launched via UWSM with optimized NVIDIA environment variables |
| **Plasma (Wayland)** | Traditional KDE Plasma fallback (dual desktop environments retained by design) |

**Greeter Configuration:** `/etc/greetd/config.toml` specifies `command = "/usr/bin/noctalia-greeter-session"`, user `greeter`.
**Rollback:** `sudo systemctl disable --now greetd && sudo systemctl enable --now plasmalogin`.

**Declarative Greeter Config (`/var/lib/noctalia-greeter/greeter.toml` — v1.5.0):**
- `[session] default = "Hyprland (uwsm-managed)"`
- `[appearance] theme_mode = "dark"`
- `[output] name = "HDMI-A-4", 1920x1080, scale 1` (Samsung display supports native 71.91 Hz, matched at 72 Hz).
- `[keyboard] layout = "us"`
- `[cursor] theme = "McMojave" size = 36 path = "/usr/share/icons"`
- `[idle] timeout = 300` (5-minute blank timeout in greeter mode).

**Dual-DE Daemon Policy:** Redundant KDE daemons are suppressed in the Hyprland session:
- ✅ Disabled: `akonadi`, `kalendarac`, `kactivitymanagerd`, `baloo` (indexing), and `powerdevil` (power management).
- ✅ Preserved: `org.kde.kdeconnect.daemon`, `plasma-xdg-desktop-portal-kde` (Qt file pickers), and `gnome-keyring`.

## Idle, Screen Power & Media Inhibitors (2026-09-24)

Managed exclusively by Noctalia's native idle system — standalone `hypridle` and `swayidle` daemons are not executed. Persistent settings in `~/.local/state/noctalia/settings.toml`:

| Action | Configured Threshold | Rule Behavior |
|---|---:|---|
| Screen Off | `0s` unlocked / `60s` locked | Screen never powers down during active sessions; turns off 60s after session lock |
| Lock Screen | `900s` (15 min) | Session locks automatically after 15 minutes of inactivity |
| Suspend on Idle | `0s` (Disabled) | Automatic idle suspend is disabled |
| Pre-Action Fade | `2s` | Visual gamma fade prior to lock; user input cancels transition |

Noctalia natively honors `org.freedesktop.ScreenSaver.Inhibit` signals from Chromium, Zen, Stremio, Electron, and Steam WebHelper, suppressing screen off during media playback.

## Essential Keybindings

### Application Launchers

| Shortcut | Action |
|---|---|
| `Super + Return` | Launch Kitty terminal |
| `Super + E` | Launch Yazi terminal file manager |
| `Super + W` | Launch Zen browser |
| `Super + T` | Launch text editor |
| `Super + C` | Launch calculator |
| `Ctrl + Shift + Esc` | Launch system monitor (`btop`) |
| `Super + Space` | Open Noctalia application launcher |
| `Super + .` | Open emoji picker |

### Window Management

| Shortcut | Action |
|---|---|
| `Super + Q` | Close active window |
| `Super + Escape` | Force kill window |
| `Super + D` | Maximize column (fullscreen mode 1 with padding) |
| `Super + F` | True fullscreen |
| `Super + Alt + Space` | Toggle floating state |
| `Super + Tab` | Noctalia window switcher |
| `Alt + Tab` | Cycle active windows |

### Scrolling Layout Navigation (Horizontal Ribbon)

| Shortcut | Action |
|---|---|
| `Super + ←` / `→` | **Navigate columns** (shifts the horizontal ribbon and focuses adjacent column) |
| `Super + ↑` / `↓` | **Vertical focus** (cycle stacked windows in the current column) |
| `Super + Shift + ←` / `→` | **Swap columns** (`swapcol l/r` — shift active column left or right) |
| `Super + Shift + ↑` / `↓` | Move window vertically within stacked column |
| `Super + J` | **Toggle grouping** (`consume_or_expel` — stack window into previous column or expel into standalone column) |
| `Super + R` / `Shift + R` | **Cycle column width presets** (33% → 50% → 67% → 100%) |
| `Super + Home` / `End` | Jump to ribbon start / end |
| `Super + I` | `inhibit_scroll` — freeze horizontal scrolling |
| `Super + Alt + Wheel ↑/↓`| Scroll ribbon horizontally with mouse wheel |
| `Super + Mouse Drag` | Move floating window |
| `Super + Right Drag` | Resize window |

### Workspaces

| Shortcut | Action |
|---|---|
| `Super + Ctrl + Arrows` | Switch active workspace (left/right) |
| `Super + Alt + 1/2/3` | Switch directly to workspace N |
| `Super + Shift + Ctrl + N` | Move active window to workspace N and follow |
| `Super + Shift + Alt + N` | Move active window to workspace N without following |
| `Super + Shift + S` | Move active window to scratchpad |
| `Super + S` | Toggle scratchpad drawer |

### Hardware & Desktop Utilities

| Shortcut | Action |
|---|---|
| `F1` / `F2` / `F3` | Mute / Volume Down / Volume Up |
| `F4` | Mute microphone |
| `F7` / `F8` | Media Play-Pause / Next Track |
| `Super + G` | Region screenshot (Ctrl+C copy, Ctrl+S save to `~/Pictures/Screenshots`, Enter annotate) |
| `Super + Ctrl + G` | Fullscreen screenshot |
| `Super + P` | Color picker (`hyprpicker`) |
| `Super + Alt + C` | Session power menu |

---

## Window Rules & Floating Windows

Enforced in `~/.config/hypr/config/windowrules.lua`:

- **KeePassXC:** Floats centered at 960×702.
- **Yazi:** Floats centered at 45% width / 55% height.
- **Swash, Calculator (`kcalc`), Ark:** Configured floating defaults.
- **Minecraft & Prism Launcher:** Bound to workspace `name:gaming` with `content = "game"` to trigger GPU direct scanout.

---

## Dynamic VRAM Management (dmemcg via NVIDIA Cgroups)

The system leverages Linux kernel cgroup v2 memory controllers to dynamically prioritize VRAM allocation:

| Component | Responsibility | Status |
|---|---|---|
| `dmemcg-booster` | Enables the `dmem` controller and exposes GPU memory limits | ✅ Active |
| `hyprland-focused-booster` (AUR) | Monitors Hyprland focus events via IPC socket and grants maximum `dmem.low` (~8 GB) to active window | ✅ Active |

Unfocused applications drop to `dmem.low = 0`, allowing the kernel to evict background assets to RAM when demanding games require dedicated VRAM.

---

## NVIDIA Display & Gaming Invariants

1. **Kernel Parameters:** `nvidia-drm.modeset=1`, `nvidia.NVreg_EnableResizableBar=1` (ReBAR enabled), `resume_offset` for zstd hibernation.
2. **Smooth Motion & Direct Scanout Wrapper:** When utilizing `NVPRESENT_ENABLE_SMOOTH_MOTION=1`, direct scanout must be bypassed during execution to prevent 30 FPS half-rate locking. This is handled transparently by the native Rust wrapper **`with-smooth-motion %command%`**.
3. **ZRAM High-Performance Swap:** 46.9 GB compressed ZRAM (`/dev/zram0`) configured with priority 100 and zstd compression, eliminating disk swap wear.

## Diagnostics

```bash
# Verify active monitors and refresh rates
hyprctl monitors

# Inspect workspace rules
hyprctl workspacerules

# Check active VRAM allocations across cgroups
for d in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-*/; do
  echo "$(basename $d) | dmem.low: $(cat $d/dmem.low 2>/dev/null | grep -oP 'vidmem \K.*')"
done
```
