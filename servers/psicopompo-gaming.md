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
| **Online Multiplayer / Anti-Cheat** | `proton_experimental` | `vram` |
| **AAA Titles / Heavy RTX** | `GE-Proton` (auto-updated) | `vram`, `dx12`, or `rtx` |
| **Indie / Lightweight Titles** | Default (`proton-cachyos-slr`) | `vram` |
| Single Player with Optional Co-op | `GE-Proton` | `vram` |

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

## See Also

- [`servers/psicopompo.md`](psicopompo.md) — Host hardware profile
- [`guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md) — Wayland compositor tuning