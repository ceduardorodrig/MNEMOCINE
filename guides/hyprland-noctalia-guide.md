---
tags: [homelab, hyprland, noctalia, tutorial, cachyos, gpu]
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
- ✅ Preserved: `org.kde.kdeconnect.daemon`, `xdg-desktop-portal-kde` (installed, but see portal note below), and `gnome-keyring`.

## XDG Desktop Portal — FileChooser Backend (2026-10-13)

Portal backend selection lives in `~/.config/xdg-desktop-portal/portals.conf`:

```ini
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=gtk
```

**`FileChooser=gtk`** (changed from `kde` on 2026-10-13). Rationale: the `FileChooser` portal is consumed by **GTK and Electron/Chromium apps on Wayland** (e.g. Obsidian runs native Wayland — `xwayland=false`), *not* by native Qt apps. Dolphin and other KDE apps use their own native Qt/KFileDialog, independent of this portal. Previously set to `kde`, which caused Electron apps (Obsidian "Export to PDF") to render the **KDE file dialog** — visually identical to Dolphin — instead of a GTK/Nautilus-style dialog, despite Nautilus being the default `inode/directory` handler.

- **Apply:** `systemctl --user restart xdg-desktop-portal.service` (the config is read at startup; portals are stateless per-call, so apps do **not** need to be restarted).
- **Qt side unaffected:** `xdg-desktop-portal-kde` remains installed; KDE/Qt apps keep their native pickers.

## D-Bus `FileManager1` Conflict — Known Benign, No Action (2026-10-13)

**Finding (known, not a defect):** Two D-Bus service files claim the same well-known name `org.freedesktop.FileManager1`:

| Service file | `Exec` | Package |
|---|---|---|
| `/usr/share/dbus-1/services/org.freedesktop.FileManager1.service` | `nautilus --gapplication-service` | `nautilus` |
| `/usr/share/dbus-1/services/org.kde.dolphin.FileManager1.service` | `dolphin --daemon` | `dolphin` |

The conflict exists because the Dolphin file violates the D-Bus naming recommendation — its filename (`org.kde.dolphin.FileManager1.service`) does not match the bus name it declares (`org.freedesktop.FileManager1`).

**Verdict: do NOT fix.** Documented decision after upstream research (2026-10-13):

1. **The live bus is `dbus-broker`, not `dbus-daemon`.** Confirmed via `systemctl --user status dbus.service` (`dbus-broker.service`) and `pgrep -a dbus-broker`. Per the dbus-broker maintainer (bus1/dbus-broker issue #339), the broker **deterministically ignores the Dolphin file** and honours the correctly-named one. Verified on host: `GetNameOwner org.freedesktop.FileManager1` → `/usr/bin/nautilus`.
2. **The dbus-daemon man page** calls the same-directory duplicate case "arbitrary" — but that ambiguity applies to the reference daemon, not to dbus-broker.
3. **The classic workaround** (symlink/service file in `~/.local/share/dbus-1/services/`) targets `dbus-daemon` precedence semantics and would introduce an orphan override pointing at a possibly-absent binary — i.e. risk with no benefit on this host.
4. **Upstream attribution:** the malformed service file ships in the `dolphin` package; KDE is responsible for correcting it (the dbus-broker maintainer explicitly urges this).

**Only remaining symptom:** a cosmetic journal line at boot (`Service file '...org.kde.dolphin.FileManager1.service' is not named after the D-Bus name...` / `Ignoring duplicate name 'org.freedesktop.FileManager1'`). This is log noise, not a functional fault.

**Revisit condition:** only if a "reveal / Open containing folder" action ever launches Dolphin instead of Nautilus (downloads, PDF export, etc.). That does not occur today because Nautilus owns the name and the broker is deterministic.

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
| `Super + E` | Launch Nautilus file manager (floating, centered) |
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
| `Super + Shift + S` | **Toggle the active window to/from the scratchpad** — sends it when it sits on a desktop, pulls it back to the active (non-special) workspace when it is already inside the scratchpad. The drawer closes on the way back. |
| `Super + S` | Show / hide the scratchpad drawer (independent of the toggle above) |

**Scratchpad implementation (2026-10-19):** `hl.dsp.window.move({ workspace = "special" })` alone is not a toggle — Hyprland 0.56.2 short-circuits when the target workspace is the one the window already lives in (`Actions::moveToWorkspace`), so pressing the old bind while inside the scratchpad did nothing. `config/binds.lua` now branches on `hl.get_active_window().workspace.special` and sends `+0` when the window is already special; `+0` resolves to `monitor->activeWorkspaceID()` (the special lives in `m_activeSpecialWorkspace`, so `+0` is always the desktop underneath). Leaving the special also makes Hyprland clear the active special workspace, so the drawer closes by itself. Note: focusing any window that lives in the scratchpad re-opens the drawer — the drawer state follows the focused window's workspace.

**`hyprctl dispatch` gotcha on the Lua config manager (2026-10-19):** with `hyprland.lua` (Hyprland 0.55+) the compositor uses the **Lua** config manager, and `hyprctl dispatch X` is evaluated as `hl.dispatch(X)`. Legacy dispatcher strings therefore fail with a Lua parse error (`hyprctl dispatch movetoworkspace special` → `')' expected near 'special'`). Use the Lua form instead: `hyprctl dispatch 'hl.dsp.window.move({ workspace = "+0" })'`. For read-only inspection, `hyprctl repl 'return <lua>'` prints the result (e.g. `hyprctl repl 'return hl.get_active_window().workspace.name'`), while `hyprctl eval` only answers `ok`. Also note `hyprctl keyword` is refused under Lua (`keyword can't work with non-legacy parsers. Use eval.`).

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

- **KeePassXC:** Only the **main window** floats centered at 960×702 — the match requires the
  DB prefix in the title (`title = "^.+ - KeePassXC$"`, e.g. `AlgoAqui.kdbx [Locked] - KeePassXC`).
  ⚠️ **Bug fixed 2026-10-26:** the *Attach file* dropdown (`Add file...` → "New Text Document /
  Load from Disk...") has the **exact** title `KeePassXC`. The old regex (`title = "KeePassXC$"`,
  any suffix) matched it, so Hyprland stretched the popup to 960×702 **and** re-centered it over
  the window while Qt's mouse grab stayed at the original coordinates — the two options became
  unclickable. The size/center rules are now scoped to the main-window title, and popups carry a
  trailing `persistent_size = false` (last match wins, per the 0.56 wiki) so the global
  `float → persistent_size` rule cannot re-restore the bad size from its class+title memory.
  Accepted trade-off: a fresh instance with **no DB open** (title also exactly `KeePassXC`) floats
  at its natural size instead of being centered.
- **Nautilus:** Floats centered at 55% width / 65% height (default GUI file manager, bound to `Super + E`).
- **Yazi:** Floats centered at 45% width / 55% height (orphaned — no keybinding; launch via `Super + Space`).
- **Swash, Calculator (`gnome-calculator`), Ark:** Configured floating defaults (the `.*[Cc]alc.*`
  rule matches the `gnome-calculator` bound in `variables.lua`; the `org.kde.ark` rule is a
  harmless fallback while KDE Gear stays installed).
- **Minecraft & Prism Launcher:** Bound to workspace `name:gaming` with `content = "game"` to trigger GPU direct scanout.

---

## Default Applications — GNOME Utilities Policy (2026-10-26)

The Hyprland/Noctalia session standardizes on **GNOME utilities** wherever a choice exists, while
KDE/Plasma remains fully installed and functional as the fallback session (retention is by design;
the appearance layer was fully unified in the *Unification Pass* below). **Owner exception: Okular**
stays the PDF handler by
owner preference; it was installed on 2026-10-26 because `~/.config/mimeapps.list` pointed to
`org.kde.okular.desktop` while the package was absent (broken handler).

`~/.config/mimeapps.list` defaults:

| MIME type | Handler (desktop id) | App |
|---|---|---|
| `application/pdf` | `org.kde.okular.desktop` | **Okular** (KDE — owner exception) |
| `image/{png,jpeg,webp,gif}` | `org.gnome.Loupe.desktop` | **Loupe** (GPU rendering + sandboxed *glycin* loaders; handles >256 MP images without stalling — replaced Gwenview as default) |
| `zip` `7z` `bzip2` `tar` `gzip` `xz` | `org.gnome.FileRoller.desktop` | **File Roller** (fixes `zip` → `gale.desktop`, a mod manager) |
| `text/plain` | `org.gnome.TextEditor.desktop` | **GNOME Text Editor** — unified with the `Super + T` binding (Zed removed from the default) |
| `inode/directory` | `org.gnome.Nautilus.desktop` | Nautilus (unchanged) |
| `text/html` + `http(s)` | `zen.desktop` | Zen (unchanged) |

Operational notes:

- **`mimeapps.list` is user-global:** these defaults also apply when logging into the Plasma
  session — KDE apps keep working, they simply stop being the *default* openers.
- **`TERMINAL=kitty`** added to `~/.config/uwsm/env` (canonical location per `man uwsm`, XDG
  `uwsm/env`). Noctalia uses `$TERMINAL` for `Terminal=true` apps and previously depended on its
  fallback discovery list (which includes Konsole). Effective from the **next login**.
- Noctalia community template **`konsole` removed** by owner (2026-10-26) from
  `~/.local/state/noctalia/settings.toml` (`theme.templates.community_ids` → `opencode`,
  `papirus-icons`). The `kcolorscheme`/`qt` built-in templates remain — they generate the Qt
  palette (`qt6ct → colors/noctalia.conf`) that keeps Qt/KeePassXC apps on the wallpaper scheme.
- **Nothing was uninstalled:** `kcalc`, `konsole`, `spectacle`, `kdialog`, `gwenview`, `ark`,
  `xdg-desktop-portal-kde`, `kdeconnect` and the Dolphin/KIO SFTP integration all stay — removing
  KDE Gear risks breaking Plasma and shared dependencies (owner decision, 2026-10-26).
- Packages installed 2026-10-26: `okular`, `loupe`, `file-roller` (both in `cachyos-extra-v3`).
  Caveat: `threadweaver` (okular dep) was unavailable on the CachyOS v3 mirrors (HTTP 404 /
  truncated file on `cdn77.cachyos.org` and `mirror5.krfoss.org`) and had to be pulled from the
  official Arch `extra` repo at the same upstream version (`6.30.0-1`).

### Unification Pass — Cursor, Icons, Font, Qt Widgets (2026-10-13)

Second KDE→GNOME pruning round, this time on the **appearance layer**. Principle: each visual
attribute has **one source per toolkit/layer**, all pointing at the same value.

- **Cursor = McMojave (36px) everywhere.** Already correct: `~/.config/uwsm/env`
  (`HYPRCURSOR_THEME`/`XCURSOR_THEME` + sizes), `~/.Xresources` (legacy X11/Steam apps),
  `gsettings` (`org.gnome.desktop.interface`), greeter (`/var/lib/noctalia-greeter/greeter.toml`)
  and `qt6ct.conf`. **Stale Bibata-Modern-Classic fixed** in: `gtk-3.0/settings.ini`,
  `gtk-4.0/settings.ini`, `~/.config/xsettingsd/xsettingsd.conf` (legacy GTK2/X11) and
  `~/.config/kcminputrc` (Plasma session) — all now `McMojave` + size 36.
  The theme is a **manual install** (`/usr/share/icons/McMojave`, v1.0.0, no pacman owner —
  unified Hyprcursor+XCursor build; source copy in `~/.local/share/icons/McMojave-cursors`):
  updates are manual rebuilds, not pacman.
- **Icons = Papirus-Dark everywhere.** Already correct: `gsettings`, `gtk-*.ini`, Noctalia
  `papirus-icons` template. **Stale breeze-dark fixed** in: `qt6ct.conf` (`icon_theme`),
  `xsettingsd.conf` (`Net/IconThemeName`), `kdeglobals` `[Icons] Theme=` and
  `~/.config/kdedefaults/kdeglobals` (Plasma defaults override).
- **Proportional font = Lexend 10 everywhere.** Applied in `gsettings` (`font-name`),
  `gtk-*.ini` (`gtk-font-name`), `xsettingsd.conf` (`Gtk/FontName`), `qt6ct.conf` (`[Fonts]
  general`, was 9) and `kdeglobals` `[General] font=` (key was missing). Noctalia already used
  `font_family = "Lexend"`. Monospace stays **Hack** (Lexend has no mono variant). Package:
  AUR `lexend-fonts-git`.
- **Qt widgets → Adwaita style.** `qt6ct.conf`: `style=Klassy → style=adwaita` (AUR package
  `adwaita-qt6 1.4.2`, plugin at `/usr/lib/qt6/plugins/styles/adwaita.so`). KeePassXC, Dolphin,
  Okular and kcalc now draw buttons/menus in the GNOME style. The **palette remains
  wallpaper-derived** (`qt6ct custom_palette` + `colors/noctalia.conf`, Sumænimá theme) — only
  the widget style changed.
- **Qt window decorations (titlebar/X): structurally inert under Hyprland.** The compositor
  advertises `zxdg_decoration_manager_v1` (verified via `wayland-info`) → Qt negotiates
  **server-side decoration** (Hyprland's border, no titlebar) and the CSD plugin is never loaded
  (`QT_DEBUG_PLUGINS` stays empty). Empirical test: native-Wayland `kcalc` with
  `QT_WAYLAND_DECORATION=adwaita` and `=bradient` → no titlebar in either case. CSD plugins
  (`qadwaitadecorations-qt6`, `QT_WAYLAND_DECORATION`) only engage on compositors **without**
  xdg-decoration (e.g. GNOME/Mutter). Consequence: Qt windows are titleless by Hyprland design —
  close via `Super + Q`, right-click menu or the Noctalia kill-switch. GTK apps keep their own
  headerbar with the close button (client-side, toolkit-drawn). Packages `qadwaitadecorations-qt6`
  and `qt5-wayland-decorations` were installed for the test and **uninstalled the same day**
  (2026-10-13, inert here). Caveat: `qt6-wayland` entered the system as their dependency but was
  **kept deliberately** (`pacman -D --asexplicit`) — it enables native-Wayland Qt6 apps, finally
  honoring the `QT_QPA_PLATFORM="wayland;xcb"` that `~/.config/uwsm/env` had requested since
  2026-09-27 (before that it silently fell back to XWayland/xcb).

---

## Appearance: Window Opacity & Icon Theme (2026-10-12)

### Window Opacity (Hyprland compositor)

Global opacity set in `~/.config/hypr/config/decorations.lua`:

| Setting | Value | Behavior |
|---|---:|---|
| `active_opacity` | `1.0` | Focused windows are **fully opaque** |
| `inactive_opacity` | `0.70` | Unfocused windows fade to **30% transparent** |
| `fullscreen_opacity` | `1` | Fullscreen always opaque |

> **Whitelist exception:** `firefox|zen`, terminals, and media players (`mpv`, `vlc`, etc) carry an `opacity = "1.0 override"` window rule (`windowrules.lua:140-142`) — they remain opaque even when unfocused, so terminal/browser text stays readable at a glance. All other apps (including Nautilus) follow the global active/inactive values.

### GTK Icon Theme (Nautilus & GTK apps)

The GTK icon theme is **`Papirus-Dark`** (modern third-party theme). Configured in three places:

- `~/.config/gtk-3.0/settings.ini` → `gtk-icon-theme-name=Papirus-Dark`
- `~/.config/gtk-4.0/settings.ini` → `gtk-icon-theme-name=Papirus-Dark`
- `gsettings get org.gnome.desktop.interface icon-theme` → `'Papirus-Dark'`

> **Unified since 2026-10-13:** the former dual-DE icon split (GTK=Papirus-Dark vs Qt/Plasma=
> breeze-dark) was retired — `qt6ct.conf`, `xsettingsd.conf`, `kdeglobals [Icons]` and
> `kdedefaults/kdeglobals` now also use `Papirus-Dark`. See *Unification Pass* above for the
> full inventory. Preview and switch GTK themes live with `nwg-look`.

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
