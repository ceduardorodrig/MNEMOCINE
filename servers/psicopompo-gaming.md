---
tags: [homelab, service, steam, gaming, server, psicopompo, tutorial]
---

# psicopompo-gaming

Operational and tuning documentation for Steam gaming on Linux on `psicopompo`.

See also: [`servers/psicopompo.md`](psicopompo.md) · [`guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md)

---

## 🎮 Gaming Stack Architecture (psicopompo)

| Component | Specification | Functionality |
|---|---|---|
| GPU | NVIDIA GeForce RTX 5050 (Driver 615.71.09) | Dedicated 3D rendering, Ray Tracing, and DLSS |
| ReBAR | Active (`NVreg_EnableResizableBar=1`) | Resizable BAR memory mapping |
| Default Proton | `proton-cachyos-slr` | Optimized CachyOS system Proton runtime |
| GE-Proton | `GE-Proton` (weekly automated updates) | Compatibility runtime for heavy DX12/RTX titles |
| VRAM Booster | `dmemcg-booster` + `hyprland-focused-booster` | Cgroup v2 dynamic VRAM prioritization for focused window |
| Launcher Wrapper | `game-performance` | System performance profile lock and screensaver inhibitor |
| In-game Telemetry | `mangohud` (Toggle: Shift_R + F12) | Real-time FPS, frame timing, and thermal overlay |

> 🖥️ **Gaming Governance Audit:** Run `stenio --gaming` for automated validation of VRAM cgroup controllers, Hyprland scanout states, 36/36 launch options, DLSS environment flags, and shader disk cache size.

### Global Gaming Invariants (Canonized 2026-09-21)

| Layer | Target Scope | Status |
|---|---|---|
| **VRAM Priority** (`systemd-run --user --scope` + dmemcg) | **All 36 configured games** | ✅ Active across library |
| **Native Wayland** (`PROTON_ENABLE_WAYLAND=1`) | Proton titles | ✅ Active |
| **Direct Scanout** (`direct_scanout=2`, automatic for games) | 35 titles (36 when Valheim closes) | ✅ Sub-millisecond latency |
| **Smooth Motion** (`with-smooth-motion`) | Valheim (modular to any title) | ✅ Native without gamescope jitter |
| **Adaptive Scanout Wrapper** (`with-smooth-motion`) | Smooth Motion titles | ✅ Suspends scanout during play, restores on exit |
| **Global DLSS Upgrade** | All DLSS titles | ✅ Configured via `environment.d` |

## 🛠️ Declarative Steam Launch Configuration (`steam-launch-options`)

Declarative command-line manager controlling per-game Proton versions and launch options.

- **Binary:** `~/.local/bin/steam-launch-options`
- **Configuration:** `~/.config/steam-launch-options/{profiles,games}.toml`
- **Automation:** Systemd timer `steam-ge-update.timer` executes weekly to maintain upstream GE-Proton releases.

### Operations

```bash
steam-launch-options list       # Display titles, profiles, and configuration drift
steam-launch-options sync       # Apply all TOML profiles idempotently with backups
steam-launch-options apply 730  # Apply configuration for a specific App ID
steam-launch-options status     # Dry-run audit comparing TOML against active Steam VDFs
steam-launch-options discover   # Detect newly installed titles in library paths
steam-launch-options ge-update  # Pull and unpack latest GE-Proton release
```

> ⚠️ Steam must be closed when running `sync` or `apply` to prevent Steam from overwriting VDF files on exit.

### 🎯 Proton Version Assignment Policy

| Category | Target Proton Tool | Assigned Profile |
|---|---|---|
| **Default / Stack Padrão** | `proton-cachyos-slr` (Proton CachyOS) | `vram` |
| **AAA Titles / Heavy RTX** | `GE-Proton` (auto-updated) | `vram`, `dx12`, ou `rtx` |
| **Online Multiplayer / Anti-Cheat específico** | `proton_experimental` | `vram` |
| Single Player com Coop Opcional | `GE-Proton` | `vram` |

> 💡 **Valheim:** Segue o Proton padrão do sistema (`proton-cachyos-slr`). Anteriormente utilizava override para `proton_experimental`, mas o Proton CachyOS padrão provou entregar desempenho, frametime e estabilidade superiores com os mods via Gale/BepInEx e Wayland nativo.

### Global Environment Variables (`~/.config/environment.d/gaming.conf`)

- **Global DLSS Upgrade:** `PROTON_DLSS_UPGRADE=1` ensures games automatically leverage modern DLSS DLL revisions.
- **Dedicated Shader Cache (12 GB):** `__GL_SHADER_DISK_CACHE_SIZE=12000000000` prevents shader compilation stutter on initial game launches.
- **Steam Shader Pre-Caching Disabled:** Disabled in Steam settings to avoid redundant cache downloads, as CachyOS and GE Proton bundle modern codec libraries.

### Adaptive Smooth Motion & Direct Scanout Architecture

When running frame generation via `NVPRESENT_ENABLE_SMOOTH_MOTION=1`, Hyprland's `direct_scanout = 2` sends framebuffers directly to the display, preventing the Vulkan presentation layer from injecting interpolated frames and locking refresh rates to 30 FPS.

**Solution:** The open-source Rust utility **`with-smooth-motion`** ([GitHub: ceduardorodrig/WITH-SMOOTH-MOTION](https://github.com/ceduardorodrig/WITH-SMOOTH-MOTION)):
1. Temporarily suspends direct scanout in Hyprland (`direct_scanout = 0`);
2. Sets `NVPRESENT_ENABLE_SMOOTH_MOTION=1` inside the game's child process;
3. Executes the game natively in Wayland with full compositor frame pacing;
4. Restores `direct_scanout = 2` upon process exit or termination via Rust RAII drop guards.

### Non-Steam Emulation & Neural Remastering Stack

| Title / Utility | Host Location | Target Proton | Launch Profile | Functionality |
|---|---|---|---|---|
| **Azimuth (Forza PC)** | `/mnt/NVME_PCI/azimuth (forza_pc)/azimuth.exe` | System Default | `dx12_smooth_motion` | Xbox One to DX12 translation with descriptor heap, Reflex low latency, and NVIDIA Smooth Motion frame generation |
| **PCSX2** | `/usr/bin/pcsx2-qt` (AUR `pcsx2` 2.8.2, maintainer xiota) | Native Linux (no Proton) | `game-performance` | Native PS2 emulation, Vulkan renderer; DLSS 5 experiment via `DLSS5VKLayer` planned |

#### PCSX2 (native) Architecture
- **Replaced (2026-11-01):** the Windows build `pcsx2-qt.exe` under Proton plus the UNCANNY STRATA stack were removed entirely. Reasons: UNCANNY is a closed-source, unsigned Windows alpha whose PowerShell-based installer cannot run under Wine, and the Windows build with `Renderer = -1` (Auto) selected D3D12/VKD3D, which failed on `Method 'Load' for structured buffers` and produced a black screen. `Renderer = 11` is the *Null* renderer, not D3D12.
- **Install:** AUR `pcsx2` (builds upstream `PCSX2/pcsx2` v2.8.2 against system libs). Flatpak was rejected because its sandbox cannot see host Vulkan layers (needed by `DLSS5VKLayer`).
- **Data directory:** `~/.config/PCSX2/` (`inis/PCSX2.ini`, `bios/`, `memcards/`, `sstates/`, `cheats/`, `patches/`, `gamesettings/`, `inputprofiles/`, `covers/`, `textures/`). Game images live in `/mnt/NVME_PCI/pcsx2-games/` (`[GameList] RecursivePaths`).
- **Graphics:** `Renderer = 14` (Vulkan), `UpscaleMultiplier = 3`, `LoadTextureReplacements = true`.
- **Gamepad:** Xbox Wireless Controller (`14:CB:65:A4:3D:32`) via SDL (`[InputSources] SDL=true`), DualShock 2 bindings under `[Pad1]`. Power the controller on (Xbox button) before launching.
  - **udev (2026-11-01):** `steam-devices` only grants `uaccess` to the Xbox Elite 2 (`0B22`). The Xbox Series pad over Bluetooth (`045E:0B13`, `uhid`) came up as `hidraw` `root:root 600`, so SDL listed it ("Added HIDAPI device") but never opened it and the Start button did nothing. Fixed with `/etc/udev/rules.d/70-xbox-series-uaccess.rules` (`0B12` USB + `0B13` BT, `MODE=0660`, `TAG+="uaccess"`), same pattern as Valve's rule. Reconnect the controller (or restart PCSX2) after applying.
- **Steam shortcut:** non-Steam entry `PCSX2` (same `appid` 3162449111 so grid artwork persists) with launch options `systemd-run --user --scope game-performance %command%`. No Proton, no `PROTON_ENABLE_WAYLAND`. DLSS 5 is **not** used here (see below).
- **Hyprland:** window rule matches `pcsx2.*` → `workspace = name:gaming`, `content = "game"`, no forced `fullscreen_state` (see `windowrules.lua`).
- **VRAM Boost:** `systemd-run --user --scope game-performance` + `hyprland-focused-booster`.
- **DLSS 5 (experimental, working 2026-11-01):** community Vulkan layer [`DLSS5VKLayer`](https://github.com/bmitch87/DLSS5VKLayer) 0.3.2-1 (AGPL-3.0), installed per-user from the release tarball (`install.sh --user`) into `~/.local/lib/dlssnr/` with Vulkan manifests in `~/.local/share/vulkan/implicit_layer.d/`. The installer's global `~/.config/environment.d/dlssnr.conf` (`VK_INSTANCE_LAYERS`) was deliberately **removed** so the layer only loads when `VKLayer_DLSS5=1` is set. It generates synthetic motion vectors via `VK_NV_optical_flow`, so PCSX2 need not provide depth/motion.
  - **Manifest location (2026-11-01):** Steam's runtime container (`pressure-vessel`) only searches system dirs for Vulkan layers and ignores `~/.local/share/vulkan` and `VK_ADD_IMPLICIT_LAYER_PATH` (loader log showed only `MESA_device_select`). The 64-bit manifest therefore lives in `/etc/vulkan/implicit_layer.d/VK_LAYER_NV_dlssnr.x86_64.json` (admin-local dir per the Vulkan Loader spec), pointing at `~/.local/lib/dlssnr/layer/libVkLayer_NV_dlssnr.so`; the duplicate under `~/.local/share/vulkan` was removed to avoid loading the layer twice. Related upstream: ValveSoftware/steam-runtime #564, #662, #837.
  - **NGX runtime:** `nvngx_dlssnr.dll` is imported from the official DLSS 5 update of Portal with RTX (`.../SteamLibrary/steamapps/common/PortalRTX/bin/.trex/`) via `dlssnr-helper import-binaries` into `~/.local/share/dlssnr/binaries/`. No leaked builds. If Portal RTX is updated or removed, re-import.
  - **Helper:** a Windows helper runs under `proton-cachyos-slr` in a managed prefix (`~/.local/share/dlssnr/prefix`, config `~/.config/dlssnr/config.ini`, log `~/.local/state/dlssnr/helper.log`). Manage with `dlssnr-helper {status,doctor,start,stop}`.
  - **Per-game use (2026-11-02):** DLSS 5 is enabled per game by putting `/home/edu/.local/bin/with-dlss5` in front of the command in its launch options (declaratively via a `steam-launch-options` profile). PCSX2 was tested (~80% emulation speed vs 100%, ~+10% with `workingscale 0.75` but visibly softer) and **reverted to no DLSS 5**. First real target: Valheim (profile `gale-valheim-native-dlss5` = `gale-valheim-native` + wrapper: `systemd-run --user --scope game-performance /home/edu/.local/bin/with-dlss5 ./start_game_bepinex.sh %command%`; rollback = set Valheim back to `gale-valheim-native` in `games.toml`). Do **not** combine with Smooth Motion (layer order). Candidates considered (unverified API, DX11/DX9 via DXVK): GTA IV, Hellblade, Ghostrunner, Enshrouded; avoid DX12/VKD3D titles, online/anti-cheat games and OpenGL (Project Zomboid).
  - **Live controls (2026-11-02):** `dlss5 fx` toggles the effect (`enabled`) and `dlss5 style [next|default|natural|cinematic]` switches the model style (0/1/2) through `dlssnr-shmctl` on the shared-memory header, with a `notify-send` OSD. Hyprland binds in `~/.config/hypr/config/binds.lua`: **`SUPER+F10`** = next style, **`SUPER+F11`** = effect on/off (A/B). Persistent defaults live in `~/.config/dlssnr/settings.conf` (`key value` lines, applied by `with-dlss5` at every start; currently `style 2` = Cinematic). Full key list: `dlssnr-shmctl /tmp/dlssnr-1000/shm.bin settings`. The layer also has a native single-key toggle (`togglekey`, Linux `KEY_` code or `DLSSNR_TOGGLE_KEY`) that only flips `enabled`; not used. `compare` (1 side-by-side, 2 wipe) gives an in-engine A/B.
  - **Performance (2026-11-02):** with DLSS 5 on, PCSX2 runs ~80% speed vs 100% off (shared RTX 5050). Per project source, `workingscale` = fraction of the frame the model works at (0.25-2.0); cost scales roughly with its square (community report). Measure with `DLSSNR_TIME=1` (helper log `[time] ... flow= eval= total= ms`).
  - **Verified working 2026-11-01:** helper log shows `Feature=18 created=true path=vulkan-snippet size=1920x1080`, `neural ready 1920x1080` and optical-flow passes while Burnout 3 runs; `GetFeatureRequirements -> 0xbad00005` is logged but harmless. **Caveats:** experimental third-party stack; no source documents PCSX2 specifically; Smooth Motion layer ordering (`VK_LAYER_NV_present`) is not configured. The effect is neural post-processing of the final frame, not DLSS-native motion data.
- **Steam Grid Artwork:** capsule (`3162449111p.png`), hero, logo, icon and landscape files live in the Steam userdata `grid/` folder; the shortcut icon is `~/.config/PCSX2/icon.png`.


## See Also

- [`servers/psicopompo.md`](psicopompo.md) — Host hardware profile
- [`guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md) — Wayland compositor tuning