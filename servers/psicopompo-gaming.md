---
tags: [homelab, service, steam, gaming, server, psicopompo, tutorial]
---

# psicopompo-gaming

See also: [[psicopompo]] · [[hyprland-noctalia-guide]]

---

## 🎮 Gaming Stack (psicopompo)

| Component | Version | Function |
|---|---|---|
| GPU | RTX 5050 (driver 615.71.09, nvidia-open) | Ray tracing + DLSS |
| ReBAR | ✅ ON (`NVreg_EnableResizableBar=1`) | Resizable BAR enabled |
| Default Proton | `proton-cachyos-slr` | Proton CachyOS (system default) |
| GE-Proton | `GE-Proton11-7-x86_64` (weekly autoupdate) | Heavy ray tracing (Portal RTX) |
| VRAM boost | `dmemcg-booster` + `hyprland-focused-booster` | VRAM prioritized for the focused window via cgroups |
| Wrapper | `game-performance` | Performance power profile + disables screensaver |
| Monitoring | `mangohud` (Shift_R+F12) | In-game FPS/temperature |

> 🔍 **GPU/VRAM health checklist + pinned NVIDIA parameters:** see
> [[hyprland-noctalia-guide]] (sections 🩺 Health Check and ⚙️ NVIDIA Parameters).

> 🖥️ **Gaming Health X-ray:** run `stenio --gaming` — session-aware audit of the
> full stack (VRAM dmemcg, Hyprland scanout, 36/36 launch options, DLSS,
> kernel/NTSYNC/ReBAR, 12GB shader cache). Detects Hyprland vs KDE automatically.

### 🏗️ Global Gaming Architecture (canonicalized 21/09)

| Layer | Scope | Status |
|---|---|---|
| **VRAM boost** (`systemd-run --user --scope` + dmemcg) | **ALL 36 games** | ✅ Active in all |
| **Wayland** (`PROTON_ENABLE_WAYLAND=1`) | All games with Proton | ✅ Active |
| **Direct scanout** (`direct_scanout=2`, auto for games) | 35 games (36 when Valheim is closed) | ✅ Minimal latency |
| **Smooth Motion** (`with-smooth-motion`) | Valheim (expandable to any game) | ✅ Native, no gamescope |
| **Adaptive wrapper** (`with-smooth-motion`) | Games with Smooth Motion | ✅ Suspends scanout during the game, restores on exit |
| **DLSS upgrade** (global env) | All games with DLSS | ✅ via environment.d |

**Golden rule:** VRAM + Wayland for EVERYTHING; direct scanout active globally by default; games with Smooth Motion use the adaptive `with-smooth-motion` wrapper — never turn off a global optimization because of 1 game.

## 🛠️ steam-launch-options (CLI script, Rust)

**Declarative** manager for Steam launch options and Proton.

- **Binary:** `~/.local/bin/steam-launch-options`
- **Source:** `~/homelab/steam-launch-options/`
- **Config:** `~/.config/steam-launch-options/{profiles,games}.toml`
- **GE-Proton autoupdate:** weekly systemd timer (`steam-ge-update.timer`)

> **🖥️ Wayland mandatory:** homelab policy — ALL games run with
> `PROTON_ENABLE_WAYLAND=1` (native winewayland.drv). Xwayland is a rare exception
> (`wayland_fallback` profile) for games that break with launchers (e.g. white screen).

### Usage

```bash
steam-launch-options list       # jogos + perfil + proton + divergências
steam-launch-options sync       # aplica TODOS os perfis (idempotente, com backup)
steam-launch-options apply 730  # aplica perfil de um jogo
steam-launch-options status     # divergências TOML vs Steam (dry-run)
steam-launch-options backup     # backup manual dos .vdf
steam-launch-options discover [--add]   # detecta jogos novos nas bibliotecas montadas
steam-launch-options ge-update  # atualiza GE-Proton p/ última release
```

> ⚠️ **Steam must be CLOSED** for `sync`/`apply` (otherwise the .vdf files get overwritten by Steam on exit). Steam detection uses `pgrep -x` (exact match) — it does not match the binary itself.

### 🎯 Proton Policy (canonicalized 2026-09-21)

| Category | Proton | Profile |
|---|---|---|
| **Online multiplayer / anti-cheat** | `proton_experimental` | `vram` |
| **Triple A / RTX** | `GE-Proton` (autoupdate) | `vram`/`dx12`/`rtx` |
| **Indie / light / stable** | default (`proton-cachyos-slr`) | `vram` |
| Single player with optional coop | GE (single is the focus) | `vram` |

Common sense: games with a multiplayer mode that you play single-player → can stay on GE. Hard rule for games that are multiplayer by nature (Sea of Thieves, MK1, RDR2 online, Valheim, L4D2, RoR2, Civ V) → experimental.

> **⚙️ Darktide (GE, not experimental — it would look like a mistake):** it is online
> co-op multiplayer, BUT **Easy Anti-Cheat was removed in jun/2024** (Fatshark,
> PCGamingWiki). Without anti-cheat, GE is safe and better for DX12 + RTX (the
> "multiplayer → experimental" rule exists because of anti-cheat; without it, GE wins).
>
> **💎 DLSS — GLOBAL (not per game):** `PROTON_DLSS_UPGRADE=1` in
> `~/.config/environment.d/gaming.conf` — CachyOS wiki best practice. Applies to
> **every game/proton** (default, GE, experimental), with no per-game launch options:
> any downloaded game already uses the latest DLSS automatically.
>
> **💾 Shader cache — GLOBAL (12GB, 21/09/2026):** `__GL_SHADER_DISK_CACHE_SIZE=12000000000`
> in the same `gaming.conf` (canonical value from the CachyOS wiki §Increase shader cache size) —
> avoids recompiling shaders all the time (stutter on the 1st launch of big games).
> Applied together with Steam's Shader Pre-caching turned OFF (Settings → Downloads):
> the wiki recommends disabling it when using Proton CachyOS/GE (they already ship the codecs).
>
> **🎮 Valheim + r2modman (known quirk):** the game has a native Linux build AND
> Proton, but the mods run via the r2modman wrapper
> (`web_start_wrapper.sh` inserted in the middle of the launch command, profile `r2modman-valheim`).
> **Proton used: `proton_experimental`** — deliberate choice: because it comes from
> Valve, the prefix is kept in place by Steam (without the quirk of reopening vanilla
> on every tool change). With GE (separate tool) you would have to open vanilla once
> on every new release — unnecessary here.
> **Smooth Motion (`NVPRESENT_ENABLE_SMOOTH_MOTION=1`):** enabled on Valheim.
> **⚠️ ROOT CAUSE of the 30fps (canonicalized 21/09):** Hyprland with
> `render.direct_scanout = 2` sent the swapchain DIRECT to the display in fullscreen,
> skipping composition → the `NVPRESENT` layer (Smooth Motion) could not inject
> frames → frame pacing ABAB (GPU ~15%, locks at half the refresh = 30fps on a
> 60Hz monitor). Confirmed symptom: **pausing works / running locks; windowed
> works / fullscreen locks**.
> **DEFINITIVE SOLUTION (Option C — with-smooth-motion, canonicalized 23/09/2026):**
> On 21/09 gamescope was tested (Option B), but it produced unwanted trade-offs:
> with VSync the SM froze, and without VSync a "rubber band effect" appeared in frametime.
> The definitive, scalable, open-source solution is the Rust utility **`with-smooth-motion`**
> ([GitHub: ceduardorodrig/WITH-SMOOTH-MOTION](https://github.com/ceduardorodrig/WITH-SMOOTH-MOTION) · `/usr/local/bin/with-smooth-motion`), which:
> 1. Temporarily suspends direct scanout in Hyprland (`hyprctl eval 'hl.config({ render = { direct_scanout = 0 } })'`)
> 2. Keeps an **active watchdog thread** every 2s to recover the scanout in case Alt+Tab or a desktop switch resets it
> 3. Sets `NVPRESENT_ENABLE_SMOOTH_MOTION=1` natively on the child process
> 4. Runs the game natively and cleanly (without gamescope's overhead or jitter)
> 5. Forwards graceful signals (`SIGINT`, `SIGTERM`) to the child and restores `direct_scanout = 2` via RAII (`ScanoutGuard::drop`)
> 6. If it runs on another compositor (e.g. the fallback KWin), it touches nothing and runs clean.
> That way, the 36 games use direct scanout and low latency, and any game
> that wants Smooth Motion runs with active composition on demand.
> Important rules:
> - **The game's V-Sync must stay OFF** — with V-Sync on, Smooth Motion
>   conflicts and locks at half the refresh.
> - **No FPS limiter** — user preference (a limiter also locks
>   the SM; Fallout76 case: cap 120 + SM = 30fps).
> - **`dxvk.latencySleep=True` / `dxvk.maxFrameLatency=1` do NOT work with SM**
>   — they cause the 30fps lock in Unity games (DXVK #5507 + Smooth Motion FAQ).
> - **`PROTON_ENABLE_NVAPI=1` is LEGACY/unnecessary** — since Proton 9,
>   DXVK-NVAPI is already enabled by default for all titles; the flag no longer
>   does anything. Removed.
> - **`DXVK_NVAPI_REFLEX_LOW_LATENCY=2` does NOT exist** — an unknown env var is
>   ignored (the old line worked despite it). Do not use.
> **Flawless flow:**
> 1. Launch via **r2modman → Start Modded** (fills `wrapper_args.txt`
>    with the BepInEx wrapper; the file is cleaned on every run, so vanilla
>    launched directly from Steam runs without mods — r2modman's anti-injection behavior)
> 2. The wrapper is created/updated by r2modman itself when you use the
>    Start Modded button.
> ⚠️ Steam must be **restarted** to detect new compat tools —
> relevant for GE (not for experimental, which Steam manages).

### 🪄 Playbook: How to Enable Smooth Motion on New Games (Replicability)

NVIDIA's Smooth Motion (`VK_LAYER_NV_present`) generates AI-interpolated frames. To replicate the same perfect smoothness from Valheim on any other game in the library:

1. **Vanilla games (no mods / Steam default):**
   Just map the game to the **`smooth_motion`** profile in `~/.config/steam-launch-options/games.toml`:
   ```toml
   [[games]]
   appid = <APPID_DO_JOGO>
   profile = "smooth_motion"
   proton = "proton_experimental" # ou GE-Proton conforme a categoria
   note = "Jogo com Smooth Motion nativo via with-smooth-motion"
   ```
   And apply (with Steam closed):
   ```bash
   steam-launch-options apply <APPID_DO_JOGO>
   ```

2. **Games with mods / wrappers (e.g. r2modman, BepInEx):**
   Add `/usr/local/bin/with-smooth-motion` before the wrapper script in `profiles.toml`:
   ```toml
   [[profiles]]
   name = "r2modman-<jogo>"
   description = "Mods + Smooth Motion nativo com scanout adaptativo"
   options = "PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance /usr/local/bin/with-smooth-motion \"/path/to/wrapper.sh\" %command%"
   ```

3. **Mandatory in-game rules (for any game with SM):**
   - **In-game V-Sync:** always **OFF** (in-game FIFO VSync makes the frame generator drop frames).
   - **In-game FPS limiter:** always **OFF / Uncapped**.
   - The Rust wrapper (`with-smooth-motion`, source in `~/homelab/with-smooth-motion/`) automatically suspends Hyprland's direct scanout during the match and restores `direct_scanout = 2` the moment you close the game. Zero manual intervention.

### 📦 Automatic Library Discovery (removable drive)

`discover` reads Steam's `libraryfolders.vdf` (which records all libraries, mounted or not):

- **Drive disconnected** → missing libraries are ignored, games do not break
- **Mount point changed** → the current path is read dynamically (e.g. `/run/media/edu/EXPANSION-2TB`)
- **Newly installed game** → `discover` suggests a profile by size (`SizeOnDisk`):
  - `≥ 20G` → `vram`
  - `< 5G` → `vram` (light indie, but VRAM active)
- `discover --add` generates the entries in `games.toml` automatically

### 📐 Profile Governance (canonicalized 21/09)

Clear rules for deciding when to create/keep a profile:

| Category | Naming pattern | When to use |
|---|---|---|
| **Base** | `vram` | Any game with no special need (the default) |
| **By API/render** | `dx12`, `rtx`, `low_latency` | API/render-specific flags (DX12, RTX, competitive) |
| **Per-game exception** | `ferramenta-jogo` (e.g. `r2modman-valheim`) | ONLY when a single game is the one using it (mod wrapper, one game's flag) |
| **Global (env)** | `environment.d/gaming.conf` | Flags that apply to EVERY game/proton (DLSS upgrade) — do NOT become a profile |

**Practical rules:**
1. **Base/API profiles** need a real technical reason (descriptor_heap, Reflex, etc.)
2. **Exception profiles** = `ferramenta-jogo` name — never generic (`r2modman` becomes `r2modman-valheim` when the wrapper belongs to a single game)
3. **On-demand flags** (e.g. `NVPRESENT_ENABLE_SMOOTH_MOTION`): add **as needed** (user rule) — do not apply to everything without a symptom
4. **New game** → routine: `discover --add` → adjust proton (multiplayer→experimental, AAA→GE) → `sync`
5. **Mods (r2modman etc.)** → wrapper is **per-game** (`web_start_wrapper.sh` path): each modded game gets its own `r2modman-<jogo>` profile

### Profiles (profiles.toml)

| Profile | Launch options | Use |
|---|---|---|
| `vram` | `PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command%` | Default (22 games: indie/AAA without special flags) |
| `gta4` | `WINEDLLOVERRIDES="dinput8=n,b" PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command% -nomemrestrict -norestrictions` | GTA IV legacy (dinput8 override) |
| `rtx` | `DXVK_NVAPI_VKREFLEX=1 PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command%` | Ray tracing + Reflex Vulkan (Portal RTX) |
| `dx12` | `VKD3D_CONFIG=descriptor_heap PROTON_VKD3D_LOWLATENCY=1 PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command%` | **DX12**: descriptor_heap (+5-8% FPS) + vkd3d low-latency (Reflex DX12) |
| `low_latency` | `PROTON_ENABLE_WAYLAND=1 PROTON_DXVK_LOWLATENCY=1 systemd-run --user --scope game-performance %command%` | Competitive DX11 (CS2) |
| `smooth_motion` | `PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance with-smooth-motion %command%` | Generic games with native Smooth Motion (disables direct_scanout during the session) |
| `r2modman-valheim` | `WINEDLLOVERRIDES="winhttp,version=n,b" PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance with-smooth-motion "<wrapper r2modman Valheim>" %command%` | Valheim mods + native Smooth Motion with adaptive scanout (no gamescope, no vsync, no lock) |
| `wayland_fallback` | `systemd-run --user --scope game-performance %command%` | NO Wayland (Xwayland) for games that break on winewayland |

> **💾 VRAM Policy (canonicalized 21/09):** ALL profiles include
> `systemd-run --user --scope` (VRAM boost) — including light indie.
> **🖥️ Wayland:** in all profiles (except `wayland_fallback`, a rare exception).
> **💎 DLSS — GLOBAL (CachyOS wiki best practice):** `PROTON_DLSS_UPGRADE=1`
> defined in `~/.config/environment.d/gaming.conf` → applies to EVERY game/Proton
> (default, GE, experimental) with no per-game launch options. Any downloaded game
> already uses updated DLSS automatically.
> **⚡ `dx12` profile:** 11 games (Control, Cyberpunk, RDR2, RE4, Returnal, MK1,
> Darktide, Scorn, Midnight Walk, Viewfinder, Teardown) — descriptor heap +
> vkd3d low-latency (native Reflex DX12, Proton-CachyOS 11+). The DLSS upgrade stays
> global (env), it is not repeated in the profile.
> **🐛 GTA IV:** `WINEDLLOVERRIDES="dinput8=n,b"` (dinput8 override for FusionFix/modding)
> + `-nomemrestrict -norestrictions` (removes the memory limit — ProtonDB Gold).

### Proton per game (games.toml)

**NVMe PCI (12 games):**

| Game (AppID) | Profile | Proton |
|---|---|---|
| GTA IV (12210) | gta4 | default |
| **Expedition 33 (1903340)** | vram | **GE-Proton** |
| CS2 (730) | low_latency | default* |
| Enshrouded (1203620) | vram | default |
| Ghostrunner (1139900) | vram | default |
| **Hellblade (414340)** | vram | **GE-Proton** |
| Out of Action (1670780) | vram | default |
| **Portal RTX (2012840)** | **rtx** | **GE-Proton (autoupdate)** |
| **Project Zomboid (108600)** | vram | **proton_experimental (FIXED — saves)** |
| **Scorn (698670)** | **dx12** | default |
| **The Midnight Walk (2863640)** | **dx12** | default |
| **Valheim (892970)** | **r2modman-valheim** | **experimental (r2modman mods)** |
| **Darktide (1361210)** | **dx12** | **GE-Proton (EAC removed 2024)** |

*\*CS2 is native Linux (does not use Proton) — only the low_latency profile applies.*

**SSD SATA (6 games):**

| Game (AppID) | Profile | Proton |
|---|---|---|
| Incredibox (1545450) | vram | default |
| **L4D2 (550)** | vram | **experimental (coop)** |
| Noita (881100) | vram | default |
| The Long Dark (305620) | vram | default |
| **Viewfinder (1382070)** | **dx12** | **GE-Proton (DLSS)** |
| I Am Your Beast (1876590) | vram | default |

**HD 2TB EXPANSION (17 games):**

| Game (AppID) | Profile | Proton |
|---|---|---|
| **Control UE (870780)** | **dx12** | **GE-Proton** |
| **Baldur's Gate 3 (1086940)** | vram | **GE-Proton** |
| **Cyberpunk 2077 (1091500)** | **dx12** | **GE-Proton** |
| **RDR2 (1174180)** | **dx12** | **experimental (Red Dead Online)** |
| **Sea of Thieves (1172620)** | vram | **experimental (multiplayer)** |
| **Mortal Kombat 1 (1971870)** | **dx12** | **experimental (online)** |
| **RE4 (2050650)** | **dx12** | **GE-Proton** |
| **Returnal (1649240)** | **dx12** | **GE-Proton** |
| **Risk of Rain 2 (632360)** | vram | **experimental (coop)** |
| **Civ V (8930)** | vram | **experimental (online)** |
| TWD Telltale (1449690) | vram | default |
| Hades (1145360) | vram | default |
| Hades II (1145350) | vram | default |
| Ori WotW (1057090) | vram | default |
| Little Nightmares (2149010) | vram | default |
| PEAK (3527290) | vram | default |
| **Teardown (1167630)** | **dx12** | default |

> ⚠️ **Do NOT change Zomboid's Proton** (`proton_experimental`) — the saves depend on that prefix/tool.

> ⚠️ Do NOT add `PROTON_ENABLE_NVAPI=1` — Proton 11 already enables NVAPI by default.

> 💾 **HD EXPANSION-2TB is removable** — when disconnected, its games go "missing" but the script does not break (it reads `libraryfolders.vdf` dynamically).

## 🐛 Lesson: Portal RTX pointed to a removed GE-Proton11-6

`config.vdf` mapped Portal RTX to `GE-Proton11-6-x86_64`, but that version was **deleted** by the user (only `GE-Proton11-7` exists). Steam showed the tool as invalid — the game could fail to launch.

**Fix:** `steam-launch-options sync` (with Steam closed) updates the mapping to the installed version. `ge-update` keeps the mapping in sync with the latest release automatically (weekly timer).

## 📦 GE-Proton autoupdate (weekly timer)

```bash
systemctl --user status steam-ge-update.timer   # ver timer
systemctl --user list-timers steam-ge-update    # próxima execução
steam-launch-options ge-update                  # forçar agora
```

`ge-update`:
1. Queries the latest release from GitHub (`GloriousEggroll/proton-ge-custom`)
2. If new → downloads, extracts into `compatibilitytools.d/`, removes the old version
3. Updates `games.toml` to the new version
4. Updates the mapping in `config.vdf` (only if Steam is closed — otherwise it warns)

## 📝 Routine When Installing a New Game

```bash
# 1. Baixar/instalar o jogo no Steam (normal)
# 2. Detectar automaticamente (novo comando):
steam-launch-options discover          # lista jogos novos + sugestão de perfil
steam-launch-options discover --add    # adiciona ao games.toml automaticamente
# 3. Ajustar proton se necessário (multiplayer→experimental, AAA→GE):
subl ~/.config/steam-launch-options/games.toml
# 4. Aplicar (com Steam fechado):
steam-launch-options sync
# 5. Conferir:
steam-launch-options list
```

### Visual Summary of Your Desktop

- **Bar/Widgets:** System Monitor in the bar (GPU temp/RAM) — see [[hyprland-noctalia-guide]].
- **Shift_R + F12:** MangoHud (FPS/temp) — "panic button" to see whether the GPU is working.