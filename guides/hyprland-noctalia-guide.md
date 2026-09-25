---
tags: [homelab, hyprland, noctalia, guide, cachyos, gpu]
created: 2026-09-21
---

# Hyprland + Noctalia Guide — CachyOS (psicopompo)

Quick reference guide for using Hyprland with the Noctalia shell on CachyOS.

## Basic Concept

Hyprland is a **tiling compositor** — windows arrange themselves in a grid on their own, without overlapping. **Super** (the Windows key) is the main shortcut key.

## Sessions at Login

Login uses the **Noctalia Greeter** (greetd, installed 22/09/2026 — it replaced the KDE plasmalogin). Through the greeter you pick the session:

| Session | Description |
|---|---|
| **Hyprland (uwsm-managed)** | ✅ Recommended — uses UWSM with NVIDIA env vars |
| **Plasma (Wayland)** | Traditional KDE Plasma (intentional dual DE — fallback) |

**Greeter config:** `/etc/greetd/config.toml` → `command = "/usr/bin/noctalia-greeter-session"`, `user = "greeter"`. Theme/initial user configurable in `docs.noctalia.dev` (noctalia-greeter). Backup of the original config: `/etc/greetd/config.toml.bak-*`. **Rollback:** `sudo systemctl disable --now greetd && sudo systemctl enable --now plasmalogin` (plasmalogin is intentionally left installed).

**`/var/lib/noctalia-greeter/greeter.toml`** (declarative, configured 22/09 — **v1.5.0**):
- `[session] default = "Hyprland (uwsm-managed)"` (the user selects manually in the greeter)
- `[appearance] theme_mode = "dark"` — **no `scheme` in greeter.toml**: sync.toml manages the scheme (`Rosé Pine` on the 1st sync; `"Synced"` would require a complete `[appearance.palette]`, otherwise `writeConfig` discards it)
- `[output] name = "HDMI-A-4", 1920x1080, scale 1` — **⚠️ `refresh_rate` does NOT exist in v1.5.0** (it landed on the repo `main` after 1.5.0; CachyOS only has 1.5.0-1). The greeter's `writeConfig` normalizes the file and **discards unknown keys** — only use the v1.5.0 ones (`name/layout/scale/scales/width/height/transforms`). The greeter uses EDID-preferred mode for refresh (60Hz); desktop 72Hz → a short modeset at login is acceptable. Update it when the package moves up.
- `[keyboard] layout = "us"` (raw, no intl variant)
- `[cursor] theme = "McMojave" size = 36 path = "/usr/share/icons"` (copied system-wide — edu's home is 700, inaccessible to the greeter user)
- `[idle] timeout = 300` (blank after 5 min without input **in the greeter**; it is not the Hyprland desktop policy)

**Sync with Noctalia (22/09):** `sudo noctalia-greeter passwordless-sync enable edu` — sync **without a password prompt** (constrained action `org.noctalia.greeter.sync-appearance`, helper `/usr/bin/noctalia-greeter-apply-appearance`). To copy the look to the greeter: **Noctalia → Settings → Security → Noctalia Greeter → Sync Now** (or Auto-Sync). Restart greetd/log out to see the result. Compatible versions: greeter 1.5.0 + Noctalia 5.1.0.

**72Hz monitor discovery (22/09):** `monitors.lua` used `mode = "preferred"` → EDID marks 60Hz as preferred, but the Samsung supports 71.91Hz → **now `mode = "1920x1080@72"`** (desktop + greeter matched at 72).

> 🔮 **Future TODO (monitor swap):** when swapping the display (hopefully 2K OLED @144), the connector will be the **same `HDMI-A-4`** → it is enough to update **2 files, in the same session**:
> 1. `~/.config/hypr/config/monitors.lua` → `mode = "2560x1440@144"` (or the new display spec)
> 2. `/var/lib/noctalia-greeter/greeter.toml` → `[output] width/height` (+ `refresh_rate` once the greeter package supports it — v1.5.0 still does not; see the note above)
> `direct_scanout=2` + VRR are already in place — just swap the spec. No need for `desc:`/catch-all (fixed connector).

**Dual DE policy (22/09):** Plasma installed **on purpose** (use it if needed — Dolphin, KDE Connect), but unnecessary KDE daemons stay **stopped** in the Hyprland session:
- ✅ Stopped: `akonadi` (PIM), `kalendarac` (reminders — `.desktop` → `.disabled`), `kactivitymanagerd`, `baloo` (indexing — `.desktop` → `.disabled`), `powerdevil` (power — `.desktop` → `.disabled`)
- ✅ Kept: **KDE Connect** (`org.kde.kdeconnect.daemon`), **KDE Portal** (`plasma-xdg-desktop-portal-kde` — needed for Dolphin/Qt file pickers), `gnome-keyring`

## Idle, screen and media policy (24/09/2026)

The `psicopompo` desktop uses **only Noctalia's native idle manager** — there is no `hypridle` nor `swayidle` in the Hyprland session. The effective policy is persisted in the Settings override:

`~/.local/state/noctalia/settings.toml`

| Behavior | Effective value | Rule |
|---|---:|---|
| Screen off | `0 s` unlocked / `60 s` locked | Does not turn the screen off during use; after locking, turns off after 1 min |
| Lock | `900 s` (15 min) | Locks the session after 15 min idle |
| Lock + suspend | `0 s`, disabled | No automatic idle suspend |
| Pre-action fade | `2 s` | Visual fade before blanking/locking; activity during the fade cancels the action |

The `screen-off` behavior is configured with `timeout = 0.0` and `locked_timeout = 60.0`: it stays idle while the session is unlocked and is only armed after the lock, turning the monitor off after 1 minute. The `lock` → `screen-off` ordering prevents the screen from being blanked before the session enters the lock. On unlock or activity detection, the monitor turns back on normally and the behavior goes idle again until the next lock.

`lockscreen.lock_before_suspend = true` remains active: when a suspend/hibernate **is chosen manually**, Noctalia locks before the system goes to sleep. Session menu option `3` (`lock_and_suspend`) and `SUPER+H` remain manual actions.

`systemd-logind` stays with `IdleAction=ignore`; KDE's `PowerDevil` is inactive and does not take part in the Hyprland/Noctalia policy.

### Media inhibitors

Noctalia respects idle inhibitors. When a browser/player sends `org.freedesktop.ScreenSaver.Inhibit` (or another inhibitor recognized by the shell), the **screen off and lock timers are suspended**. On the host, the log already records inhibitors from Zen, Chromium, Stremio, Electron and Steam WebHelper during playback.

This is based on the inhibition signal, not on universal "video" detection: players that do not send the signal may still trigger the timers. Firefox behaved inconsistently in the upstream issue; if it fails, use Noctalia's manual **Caffeine** before installing any helper service.

### Sources and maintenance

- Do not edit `~/.config/noctalia/merged-config.toml`: it is generated by the 04:55 exporter and will be rewritten.
- `settings.toml` has final priority over the declarative TOMLs and is included in the `config-backup`.
- The backup window and checks remain as described in [`../backups/backup-rituals.md`](../backups/backup-rituals.md).
- Do not start `hypridle`/`swayidle` alongside Noctalia.
- Validate after changes:

```bash
noctalia config validate
noctalia config export full | rg -n -A25 '^\[idle\]'
```

References: [Noctalia Idle](https://docs.noctalia.dev/noctalia/services/idle/), [Noctalia Configuration](https://docs.noctalia.dev/noctalia/configuration/), [official `locked_timeout` PR #3388](https://github.com/noctalia-dev/noctalia/pull/3388), [lock re-arm fix #4002](https://github.com/noctalia-dev/noctalia/pull/4002), [Hypridle](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/).

**Cursor on ALL layers (unified 23/09, dual-spec Hyprcursor + XCursor in the same `McMojave` theme):**
The `McMojave` theme was consolidated following the official specification, simultaneously holding `hyprcusors/` (vector SVG for Hyprland) and `cursors/` (real 36KB XCursor binaries via the `mcmojave-cursors` AUR package), eliminating the name asymmetry (`McMojave` vs `McMojave-cursors`).
- **GTK 2/3/4**: `gtk-cursor-theme-name=McMojave` (settings.ini + gtkrc) · **gsettings**: `McMojave` (Hyprland `cursor:sync_gsettings_theme=true` syncs perfectly)
- **X11/XWayland**: `XCURSOR_THEME="McMojave"` in `uwsm/env` · **Qt/qt6ct**: `cursor=McMojave`
- **Native Hyprland**: `HYPRCURSOR_THEME=McMojave`
- **Unified size**: **36px** on all layers (comfortable, sharp and balanced).
- Persistence: everything in on-disk config (`uwsm/env`, settings.ini, qt6ct.conf, dconf, Xresources) — it comes back on reboot. Docs: [Hyprland wiki §hyprcursor](https://wiki.hypr.land/Hypr-Ecosystem/hyprcursor/) and [ArchWiki §Cursor themes](https://wiki.archlinux.org/title/Cursor_themes).

**⚠️ Cursor in Steam and "stubborn" apps (universal fix 23/09 — Steam does NOT respect XCURSOR_THEME on its own):** Steam (CEF + old GTK + chroot sandbox) queries the **XSETTINGS protocol** (which KDE provided via kded6; Hyprland does not) + a **physical** `default` fallback. Complete fix (Valve issues #10808/#825/#13209/#11484 and COSMIC#168):
1. `mcmojave-cursors` package installed via AUR with real binaries (fixing the previous 0-byte dummy files)
2. **PHYSICAL copy** to `~/.local/share/icons/default` (`cp -r`, **no symlink** — #11484: Steam does not follow symlinks)
3. **`~/.config/xsettingsd/xsettingsd.conf`** → `Gtk/CursorThemeName "McMojave"` + `Gtk/CursorThemeSize 36` — **runs as user service `xsettingsd.service` (`WantedBy=graphical-session.target`)** — the XSETTINGS mechanism that was missing; it also affects legacy Electron, Java AWT, FHS-wrapped apps
4. `~/.Xresources` → `Xcursor.theme: McMojave` / `Xcursor.size: 36` + `xrdb -merge` + `autostart.lua`
5. **1:1 XCursor vs Hyprcursor calibration (Steam/KeePassXC fix 23/09):** The `mcmojave-cursors` upstream mapped a 48px image to the nominal size 36 (0.75 factor), making X11 apps 33% larger than native Wayland apps. We recompiled the full set with `rsvg-convert` and `xcursorgen`, guaranteeing an exact 1:1 mathematical ratio at all nominal resolutions (24, 28, 32, 36, 40, 48, 64).
6. **Hand/Pointer hotspot fix (fix 25/09):** The Hyprcursor port upstream had a systematic error dividing by 24 instead of 32 in `meta.hl` (`hotspot_x = 0.67` instead of `0.39` at the fingertip), shifting the click point by ~10 pixels to the right when the mouse turned into the pointing hand. We calibrated the hotspots of all cursors (`pointer.hlc` to `0.39, 0.19`, `text`, `crosshair`, `all-scroll` and the corners to `0.50`/proportional) and recompiled the XCursor with the exact hotspots (index-finger tip at `14, 7` at 36px), eliminating the offset when clicking links/buttons.
- Restart Steam/KeePassXC to pick it up (the old process does not re-read).
- ⚠️ **`xsettingsd` only re-reads the `.conf` when (re)started** — if you change the nwg-look: `systemctl --user restart xsettingsd`. At boot the user service (graphical-session.target) already comes up with the correct theme.

## Essential Shortcuts

### Open Applications

| Shortcut | What it does |
|---|---|
| `Super + Return` | Terminal (kitty) |
| `Super + E` | File manager (Dolphin) |
| `Super + W` | Browser (Zen) |
| `Super + T` | Text editor (gnome-text-editor) |
| `Super + C` | Calculator |
| `Ctrl + Shift + Esc` | System monitor (btop) |
| `Super + Space` | **App launcher** (Noctalia) |
| `Super + .` | Emoji picker |

### Windows

| Shortcut | What it does |
|---|---|
| `Super + Q` | Close window |
| `Super + Escape` | Kill window (force close) |
| `Super + D` | Fullscreen (no bar) |
| `Super + F` | Fullscreen (with bar) |
| `Super + ALT + Space` | Toggle float/tile (floating window) |
| `Super + J` | Invert split (horizontal ↔ vertical) |
| `Super + Tab` | Window switcher (Noctalia) |
| `ALT + Tab` | Cycle windows |

### Navigating Between Windows

| Shortcut                   | What it does                          |
| -------------------------- | ------------------------------------- |
| `Super + Setas`           | Move focus (left/right/up/down)       |
| `Super + Shift + Setas`   | Move window in that direction         |
| `Super + Mouse drag`       | Drag window                           |
| `Super + Mouse right-drag` | Resize window                         |

### Workspaces (Work Areas)

| Shortcut | What it does |
|---|---|
| `Super + Ctrl + Setas` | Switch workspace (left/right) |
| `Super + Alt + 1/2/3` | Go to a specific workspace |
| `Super + Ctrl + 1/2/3` | Go to a relative workspace |
| `Super + Mouse scroll` | Scroll between workspaces |
| `Super + Shift + S` | Send window to scratchpad |
| `Super + S` | Toggle scratchpad (show/hide) |

**Moving a window between workspaces** (real binds from `binds.lua`, 22/09):

| Shortcut | What it does |
|---|---|
| `Super + Shift + Ctrl + N` | Move the window to workspace **N** and **it follows you** (goes along) |
| `Super + Shift + Alt + N` | Move the window to workspace **N**, but **you stay** where you are |
| `Super + Ctrl + Shift + ←/→` | Move the window to the **previous/next** workspace (it follows you) |
| `Super + Ctrl + Shift + scroll ↑/↓` | Move via the mouse wheel (↑ = previous, ↓ = next) |
| `Super + Shift + 1/2/3` | Move the window to **another monitor** (MONITOR1/2/3) |

> ⚠️ **Do not confuse:** `Super + Shift + Setas` moves the window's **position in the grid** (tile), it does not switch workspace · `Super + Ctrl + Setas` only **navigates** (focus) between workspaces without taking the window along · `N` = workspace number (3 per monitor plus the `gaming` one).

### Noctalia Shell (Bar + Panels)

| Shortcut | What it does |
|---|---|
| `Super + Space` | Open the app launcher |
| `Super + X` | Control panel (WiFi, Bluetooth, etc.) |
| `Super + A` | Notifications |
| `Super + Z` | Noctalia settings (theme, wallpaper) |
| `Super + V` | Clipboard (copy history) |
| `Super + Shift + W` | Change wallpaper |
| `Super + L` | Lock screen |
| `Super + ALT + C` | Session menu (logout, reboot, shutdown) |

### Hardware

| Shortcut | What it does |
|---|---|
| `F2/F3` | Volume +/- |
| `F1` | Mute |
| `F4` | Mute microphone |
| `F7/F8` | Play/Pause, Next track |
| `Print` | Region screenshot |
| `Super + Print` | Fullscreen screenshot |
| `Super + P` | Color picker (hyprpicker) |

### Session (via Super + ALT + C)

| Key in the menu | Action |
|---|---|
| `1` | Lock screen |
| `2` | Logout |
| `3` | Lock + Suspend |
| `4` | Reboot |
| `5` | Shutdown |

### Zoom

| Shortcut | What it does |
|---|---|
| `Super + +` | Zoom in |
| `Super + -` | Zoom out |

## Scratchpad — What is it?

The scratchpad is a **special hidden workspace**. Think of it as a "drawer" that shows up and disappears.

- `Super + Shift + S` → Sends the active window to the scratchpad (it disappears)
- `Super + S` → Opens/closes the scratchpad (the windows involved appear above the others)

**Practical use:** send a terminal to the scratchpad and call it back with `Super + S` when you need it, without occupying a workspace.

## The Bar (Noctalia)

The bar at the top shows:
- **Left:** Launcher + Clock + GPU temp + RAM usage
- **Center:** Workspaces (dots) + Active window
- **Right:** Media + Tray + Notifications + WiFi + Volume + Session

## Getting Started Tips

1. **There is no "minimize"** — windows stay in workspaces. Move with `Super + Shift + Setas`
2. **Scratchpad** (`Super + S`) is a hidden workspace for apps you want quick access to
3. **Float** (`Super + ALT + Space`) for apps that need a fixed size
4. **Everything is configurable** in `~/.config/hypr/config/`

## Configuration Files

| File | What it controls |
|---|---|
| `~/.config/hypr/config/variables.lua` | Default apps, monitor, workspaces |
| `~/.config/hypr/config/binds.lua` | All shortcuts |
| `~/.config/hypr/config/monitors.lua` | Monitor configuration |
| `~/.config/hypr/config/windowrules.lua` | Per-app rules (float, opacity, etc.) |
| `~/.config/hypr/config/autostart.lua` | What starts with Hyprland |
| `~/.config/noctalia/config.toml` | Theme, bar, widgets |
| `~/.config/uwsm/env` | Env of the graphical session (UWSM): cursor `HYPRCURSOR_THEME=McMojave` (native) + NVIDIA + toolkits |
| `~/.config/xdg-desktop-portal/portals.conf` | Portal config (KDE file picker) |

> 🖱️ **Cursor (installed 22/09/2026, consolidated at 36px on 23/09):** unified **McMojave** theme (dual-spec native SVG hyprcursor + real AUR XCursor in the same theme) — Hyprland + Wayland apps + Noctalia + Steam + GTK/Qt. **Size 36px** (1080p, scale 1 — a generous middle size, very sharp and uniform across all layers). Swap at runtime: `hyprctl setcursor McMojave 36`; **persistence via `~/.config/uwsm/env`** (the right layer — UWSM blows the session env over environment.d; Hyprland wiki: use `uwsm/env` for theming/xcursor). Official doc: *"Put your theme(s) in ~/.local/share/icons or ~/.icons"* (wiki.hypr.land → hyprcursor).

## Useful Commands

```bash
# Ver monitores
hyprctl monitors

# Ver versão
hyprctl version

# Recarregar config (sem reboot)
hyprctl reload

# Ver janelas abertas
hyprctl clients

# Ver workspaces
hyprctl workspaces
```

## Portal Config (avoiding the KDE/Hyprland conflict)

Created in `~/.config/xdg-desktop-portal/portals.conf`:
```ini
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=kde
```
This forces the KDE file picker in Hyprland, preventing Firefox from losing logins when switching between sessions.

## References

- [Hyprland Wiki](https://wiki.hypr.land/)
- [CachyOS Hyprland Wiki](https://wiki.cachyos.org/configuration/desktop_environments/hyprland)
- [Noctalia Wiki](https://wiki.hypr.land/Hyprland-and-Noctalia)

## ⚠️ Lesson learned: do NOT delete hyprland.desktop

**MISTAKE MADE:** We deleted `hyprland.desktop` to leave only the "managed" one, but UWSM needs it internally.

`hyprland-uwsm.desktop` calls:
```
Exec=uwsm start -e -D Hyprland hyprland.desktop
```

**Rule:** BOTH files must exist in `/usr/share/wayland-sessions/`:
- `hyprland.desktop` → base file that UWSM uses internally
- `hyprland-uwsm.desktop` → wrapper that the display manager shows to the user

If you delete `hyprland.desktop`, UWSM shows a black screen with the error "Could not find entry hyprland.desktop".

## 🎮 VRAM Management (dmemcg — NVIDIA via cgroups)

Hyprland uses kernel cgroups to manage VRAM dynamically, just like Plasma.

**Installed stack:**

| Component | Function | Status |
|---|---|---|
| `dmemcg-booster` (system + user services) | Enables the dmem controller and propagates cgroups | ✅ Active |
| `hyprland-focused-booster` (AUR) | Dynamic VRAM boost for the focused window | ✅ Active |

**How it works:**
- The CachyOS kernel has `CONFIG_CGROUP_DMEM=y` (VRAM Cgroup/DMEM in the DRM subsystem)
- `dmemcg-booster` (system + user) propagates the `dmem` controller down to the app cgroups
- `hyprland-focused-booster` listens to Hyprland's `activewindow` events (socket)
- When focus changes → writes `dmem.low = <toda VRAM>` to the focused app's cgroup
- Background apps → `dmem.low = 0` (evictable if needed)

**Verify that it is working:**
```bash
systemctl --user status hyprland-focused-booster
# O app FOCADO deve ter dmem.low alto (~8G), os outros 0:
for d in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-*/; do
  echo "$(basename $d) | dmem.low: $(cat $d/dmem.low 2>/dev/null | grep -oP 'vidmem \K.*')"
done
```

**How Noctalia integrates:** `launch_apps_as_systemd_services = true` in `~/.config/noctalia/config.toml` → launcher apps already run in systemd cgroups, which is what the booster needs to resolve PID → cgroup.

**Games (Steam):** Steam is already a systemd service → games inherit the cgroup → automatic boost. For a per-game boost: launch options `systemd-run --user --scope %command%`.

> ⚠️ NEVER run `pacman -Rns $(pacman -Qdtq)` blindly — `noctalia`, `uwsm`, `swash` were left orphaned after the removal of `cachyos-hypr-noctalia` and were explicitly marked.

## 🩺 GPU/VRAM health check (executable checklist)

Full probe to validate that the entire video stack is working (GPU, ReBAR, dmem, boost):

```bash
# 1. GPU + driver + VRAM
nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used --format=csv

# 2. ReBAR (Resizable BAR)
grep -r 'EnableResizableBar' /etc/modprobe.d/
grep -o 'NVR\w*=[0-9]*\|EnableResizableBar=[01]' /proc/cmdline
cat /proc/driver/nvidia/params | grep -i resizable

# 3. VRAM stack (dmemcg + booster)
systemctl is-active dmemcg-booster-system
systemctl --user is-active dmemcg-booster-user
systemctl --user is-active hyprland-focused-booster

# 4. Controlador dmem disponível?
cat /sys/fs/cgroup/cgroup.controllers | tr ' ' '\n' | grep dmem

# 5. TESTE FUNCIONAL: janela focada tem boost (dmem.low alto), backgrounds 0
for d in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-*/; do
  echo "$(basename $d) → dmem.low: $(cat $d/dmem.low 2>/dev/null | grep -oP 'vidmem \K.*')"
done
# ✔ Janela ativa deve ter ~8546942976 (8G), TODOS os outros 0
```

**OK criteria (verified 21/09/2026):** GPU RTX 5050 + driver 615.71.09 · ReBAR=1 (modprobe + cmdline + module) · 3 active services · `dmem` in the controller · focused=8G / bg=0.

## ⚙️ Pinned NVIDIA parameters (psicopompo)

**`/etc/modprobe.d/nvidia-rebar.conf`:**
```
options nvidia NVreg_EnableResizableBar=1
```

**`~/.config/uwsm/env` (NVIDIA variables + app defaults):**
```bash
export BROWSER=zen
export TERM=xterm-kitty
export QT_QPA_PLATFORM="wayland;xcb"
export QT_QPA_PLATFORMTHEME="qt6ct"
export ELECTRON_OZONE_PLATFORM_HINT=auto
export HYPRCURSOR_THEME="McMojave"
export HYPRCURSOR_SIZE=36
export XCURSOR_THEME="McMojave"
export XCURSOR_SIZE=36

# NVIDIA GPU (RTX 5050)
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export LIBVA_DRIVER_NAME=nvidia
export __GL_GSYNC_ALLOWED=1
export WLR_NO_HARDWARE_CURSORS=1
```

**Kernel cmdline NVIDIA (via bootloader):**
- `nvidia-drm.modeset=1` — KMS mandatory for Wayland
- `nvidia.NVreg_EnableResizableBar=1` — ReBAR (mirror of the modprobe)
- `nvidia.NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100` — I2C fix
- `resume=UUID=ffc60b3e-2f31-47bb-b51e-4eb785af8647 resume_offset=60761344` — hibernation (48G swapfile)

**Loaded modules (lsmod):** `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm` (+ `drm_ttm_helper`).

> 💡 `PreserveVideoMemoryAllocations=2` in the driver (auto) — preserves VRAM across suspend/resume. It is not the VRAM cgroup (dmem); those are different things.

## ⚠️ Quirk: Smooth Motion vs Hyprland direct_scanout (30fps lock)

**Symptom:** a game with `NVPRESENT_ENABLE_SMOOTH_MOTION=1` locks to **half the refresh rate** (30fps on a 60Hz monitor) in fullscreen; **paused raises FPS / running locks up; windowed works / fullscreen locks up**.

**Root cause (canonized 21/09/2026):** Hyprland with `render.direct_scanout = 2` sends the swapchain **straight to the display** in fullscreen, skipping compositing. The `VK_LAYER_NV_present` layer (Smooth Motion) **cannot inject frames** on that path → ABAB frame pacing (GPU ~15%, locks at half).

**Why it worked on KDE:** KWin **always composites** (it does not have Hyprland's aggressive direct scanout) → NVPRESENT injects frames normally.

**DEFINITIVE SOLUTION (Option C — with-smooth-motion, canonized 23/09/2026):**
On 21/09 gamescope (Option B) was tested, but it produced unwanted side effects (in-game VSync blocked SM, and without VSync there was jitter/"rubber band" frametime).
The definitive solution is the adaptive **`with-smooth-motion`** wrapper (`/usr/local/bin/with-smooth-motion`):
```bash
# Executa jogo com Smooth Motion sem gamescope e sem desligar o scanout global:
with-smooth-motion %command%
```
**How it works:**
1. Native Rust binary (`~/homelab/with-smooth-motion/`, installed at `/usr/local/bin/with-smooth-motion`).
2. Detects Hyprland and temporarily suspends direct scanout at runtime via `hyprctl eval 'hl.config({ render = { direct_scanout = 0 } })'`.
3. Sets `NVPRESENT_ENABLE_SMOOTH_MOTION=1` safely in the child process.
4. The game runs directly on Hyprland (pure native Wayland, no gamescope and no VSync).
5. The Rust `Drop` guard (RAII) and signal handler (`SIGINT`, `SIGTERM`, `SIGHUP`) instantly restore `direct_scanout = 2` on exit (normal or crash).
6. On other compositors (e.g.: KDE Plasma), it does not affect the compositor. Zero loss for the other 35 games and maximum smoothness on Valheim.
7. To replicate on new games: see the Playbook in [[psicopompo-gaming#🪄 Playbook: How to Enable Smooth Motion on New Games (Replicability)]].

> ⚠️ **Do not combine SM with:** `dxvk.latencySleep=True` / `dxvk.maxFrameLatency=1` (30fps lock in Unity: DXVK #5507) · in-game V-Sync ON (locks at half) · FPS limiter (locks up; Fallout76 case: cap 120 + SM = 30fps).

### ℹ️ Global scanout = `2` (auto for games) — confirmed in the wiki

`render.direct_scanout = 2` means **auto: enabled with content type 'game'** (the official wiki: *"2 - auto (enabled with content type 'game')"*). Since the windowrules mark games with `content = "game"` + `fullscreen_state = 2`, direct scanout (minimum latency) is only enabled in **game fullscreen** — it does not get in the way of the rest of the desktop.

### 🟥 ALERT: black screen in native-wayland games (Hyprland #14843)

**Scenario (same as on psicopompo):** a game with `PROTON_ENABLE_WAYLAND=1` (native wayland via Proton) + NVIDIA + `direct_scanout=2` may open a **black screen in fullscreen** (audio keeps playing, input works, moving the cursor brings the image back). It is a **known Hyprland×NVIDIA×winewayland bug** (same community thread: Overwatch, EZFN, Helldivers 2). KDE is not affected — there the DS does not even activate with NVIDIA winewayland.

**Solutions (community):**
1. `render:non_shader_cm = 0` → fixes most cases (but disables scanout)
2. `quirks:skip_non_kms_dmabuf_formats = 1` → fixes it but **forces VSync** in all native-wayland games
3. Run the game without `PROTON_ENABLE_WAYLAND=1` (XWayland is not affected)

> If any game on psicopompo opens a black screen in fullscreen with Wayland, apply option 1 or 3. (Has not happened yet — preventive alert.)

## 🎮 Gaming optimization inventory (canonized 21/09/2026 — wiki sources)

> Everything below is **already active** on psicopompo. Validate with a single command: **`stenio --gaming`**
> (session-aware X-ray — detects Hyprland vs KDE and audits each item below).

| # | Optimization | Source | Where it is |
|---|---|---|---|
| 1 | **CachyOS-BORE** kernel (7.2.6) | [CachyOS wiki](https://wiki.cachyos.org/features/kernel/) | `uname -r` |
| 2 | **VRAM management (dmemcg)** — `CONFIG_CGROUP_DMEM` + `dmemcg-booster-{system,user}` + `hyprland-focused-booster` | CachyOS feature | cgroup v2 + 3 services |
| 3 | **game-performance** on-demand (profile → `performance` during the game) | [CachyOS wiki §Power Profile](https://wiki.cachyos.org/configuration/gaming/) | launch options on **36/36 games** |
| 4 | **NTSYNC** (`/dev/ntsync` + `PROTON_USE_NTSYNC=1`) | ArchWiki | `~/.config/environment.d/env.conf` |
| 5 | **ReBAR** (`nvidia.NVreg_EnableResizableBar=1`) | NVIDIA/CachyOS | `/proc/cmdline` |
| 6 | **Global DLSS upgrade** (`PROTON_DLSS_UPGRADE=1`) | [CachyOS wiki §DLSS](https://wiki.cachyos.org/configuration/gaming/) | `~/.config/environment.d/gaming.conf` |
| 7 | **NVIDIA 12GB shader cache** (`__GL_SHADER_DISK_CACHE_SIZE=12000000000`) | [CachyOS wiki §Shader cache](https://wiki.cachyos.org/configuration/gaming/) | `~/.config/environment.d/gaming.conf` — applied 21/09 |
| 8 | **Steam shader pre-caching DISABLED** (Proton CachyOS/GE already has the codecs) | [CachyOS wiki §Pre-caching](https://wiki.cachyos.org/configuration/gaming/) | Steam → Settings → Downloads — disabled 21/09 |
| 9 | **Direct scanout for games** (`direct_scanout=2`, auto with content `game`) | [Hyprland wiki](https://wiki.hypr.land/Configuring/Variables/) | `~/.config/hypr/config/misc.lua` |
| 9b | **Hyprland splash/logo DISABLED** (`disable_splash_rendering` + `disable_hyprland_logo`, 22/09 — killed the <1s flash of the distro wallpaper between login and Noctalia; splash color changed from `SUMAEPrimary` to `CACHYLGREEN`, skel default) | [Hyprland wiki §misc](https://wiki.hypr.land/Configuring/Basics/Variables/) | `~/.config/hypr/config/misc.lua` + `colors.lua` |
| 10 | **Windowrule** `content = "game"` + `fullscreen_state = 2` (scanout trigger) | Hyprland wiki | `~/.config/hypr/config/windowrules.lua` |
| 11 | **TSC clocksource** (less overhead than HPET) | [ArchWiki §clock_gettime](https://wiki.archlinux.org/title/Gaming#Improve_clock_gettime_throughput) | `/sys/devices/system/clocksource/...` |
| 12 | **Wayland in all games** (`PROTON_ENABLE_WAYLAND=1` + `PROTON_USE_NTSYNC=1`) | Proton-EM / CachyOS | `env.conf` + launch options |
| 13 | **VRAM cgroup in all games** (`systemd-run --user --scope`) | dmemcg architecture | launch options on 36/36 |
| 14 | **Isolated gamescope for Valheim** (Smooth Motion composites only there) | [ArchWiki §Utilities](https://wiki.archlinux.org/title/Gaming) | `r2modman-valheim` profile |

**Informational notes (NOT changed — owner's decision):**
- `vm.max_map_count` = `1048576` — Proton treats it as sufficient (SteamOS uses `2147483642`, optional)
- `kernel.split_lock_mitigate` — `0` improves certain Wine games (ArchWiki), not applied
- In-game V-Sync + SM → conflict; FPS limiter + SM → locks up (see the quirk above)

**Gaming config backup (enabled 21/09):** `~/.config/hypr`, `~/.config/noctalia`, `~/.config/uwsm` (22/09 — cursor/NVIDIA), `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia` are now mirrored by the `config-backup` (05:00) → NAS + git + restic + snapper. `noctalia config export` runs at 04:55 (user timer), generating `merged-config.toml` in the mirrored folder. See [`../backups/config-backup.md`](../backups/config-backup.md).

## 💾 Swap: ZRAM + hibernation (correctly configured)

| Swap | Size | Priority | Use |
|---|---|---|---|
| `/dev/zram0` (zstd) | 46.9G (`zram-size = ram`) | **100** | Used first (compressed RAM) |
| `/swap/swapfile` | 48G | **1** | Hibernation only (`resume=`) |

Confirmation:
- `zram-generator.conf` → `swap-priority = 100` ✅
- `/etc/fstab` → `/swap/swapfile ... pri=1` ✅
- Kernel params: `resume=UUID=ffc60b3e... resume_offset=60761344` → hibernation uses the swapfile ✅

## 📦 Important discovery: CachyOS Hyprland packages

**`cachyos-hypr-noctalia` and `cachyos-hyprland-settings` are MUTUALLY EXCLUSIVE** — both have `Provides: cachyos-desktop-settings` + `Conflicts With: cachyos-desktop-settings`. Installing one **automatically removes the other** (which is why Noctalia became an orphan with no explicit removal log).

- ✅ **`cachyos-hypr-noctalia`** — the CORRECT one (meta-package with deps: noctalia, uwsm, kitty, qt6ct, brightnessctl, grim, slurp, etc.)
- ❌ **`cachyos-hyprland-settings`** — vanilla (waybar/mako/wofi/swaylock), unnecessary for Noctalia

**Extra hypr* packages NOT needed** (Noctalia replaces them):
- `hyprlock` → `noctalia msg session lock`
- `hypridle` → built-in Idle service
- `hyprsunset` → built-in Night Light
- `hyprpolkitagent` → `polkit_agent = true`
- `hyprlauncher` / `hyprpaper` / `hyprshot` / `grimblast` → built-in or uses `swash`
- `nwg-*`, `dms-shell-hyprland` → incompatible with Noctalia

**If the lock/idle services do not work** after removing the extras, check what Noctalia uses internally (the `noctalia` package does not depend on hyprlock/hypridle).

## 🔎 Searching for packages with Shelly (CLI)

Shelly has a useful CLI search to check availability:
```bash
shelly search standard -v hypr    # repos oficiais
shelly search aur hypr            # AUR
```
