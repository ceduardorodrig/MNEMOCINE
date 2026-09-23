---
tags: [homelab, hyprland, noctalia, guide, cachyos, gpu]
created: 2026-09-21
---

# Guia Hyprland + Noctalia — CachyOS (psicopompo)

Guia de referência rápida para usar o Hyprland com Noctalia shell no CachyOS.

## Conceito Básico

O Hyprland é um **tiling compositor** — as janelas se organizam sozinhas em grid, sem sobrepor. O **Super** (tecla Windows) é a tecla principal de atalhos.

## Sessões no Login

O login usa o **Noctalia Greeter** (greetd, instalado 22/09/2026 — substituiu o plasmalogin do KDE). Pelo greeter você escolhe a sessão:

| Sessão | Descrição |
|---|---|
| **Hyprland (uwsm-managed)** | ✅ Recomendado — usa UWSM com env vars NVIDIA |
| **Plasma (Wayland)** | KDE Plasma tradicional (dual DE intencional — fallback) |

**Config do greeter:** `/etc/greetd/config.toml` → `command = "/usr/bin/noctalia-greeter-session"`, `user = "greeter"`. Tema/usuário inicial configuráveis em `docs.noctalia.dev` (noctalia-greeter). Backup do config original: `/etc/greetd/config.toml.bak-*`. **Rollback:** `sudo systemctl disable --now greetd && sudo systemctl enable --now plasmalogin` (plasmalogin fica instalado de propósito).

**`/var/lib/noctalia-greeter/greeter.toml`** (declarativo, configurado 22/09 — **v1.5.0**):
- `[session] default = "Hyprland (uwsm-managed)"` (usuário seleciona manualmente no greeter)
- `[appearance] theme_mode = "dark"` — **sem `scheme` no greeter.toml**: o sync.toml gerencia o scheme (`Rosé Pine` no 1º sync; `"Synced"` exigiria `[appearance.palette]` completo, senão o `writeConfig` descarta)
- `[output] name = "HDMI-A-4", 1920x1080, scale 1` — **⚠️ `refresh_rate` NÃO existe na v1.5.0** (chegou na `main` do repo, pós-1.5.0; CachyOS só tem 1.5.0-1). O `writeConfig` do greeter normaliza o arquivo e **descarta chaves desconhecidas** — só usar as da v1.5.0 (`name/layout/scale/scales/width/height/transforms`). O greeter usa o modo EDID-preferred no refresh (60Hz); desktop 72Hz → modetset curto no login aceitável. Atualizar quando o pacote subir.
- `[keyboard] layout = "us"` (bruto, sem variant intl)
- `[cursor] theme = "McMojave" size = 36 path = "/usr/share/icons"` (copiado p/ system-wide — home do edu é 700, inacessível ao user greeter)
- `[idle] timeout = 300` (blank após 5min sem input)

**Sync com Noctalia (22/09):** `sudo noctalia-greeter passwordless-sync enable edu` — sync **sem prompt** de senha (constrained action `org.noctalia.greeter.sync-appearance`, helper `/usr/bin/noctalia-greeter-apply-appearance`). Para copiar o visual para o greeter: **Noctalia → Settings → Security → Noctalia Greeter → Sync Now** (ou Auto-Sync). Restart greetd/logout para ver o resultado. Versões compatíveis: greeter 1.5.0 + Noctalia 5.1.0.

**Descoberta monitor 72Hz (22/09):** o `monitors.lua` usava `mode = "preferred"` → EDID marca 60Hz como preferido, mas o Samsung suporta 71.91Hz → **agora `mode = "1920x1080@72"`** (desktop + greeter casados em 72).

> 🔮 **TODO futuro (troca de monitor):** quando trocar a tela (hopefully 2K OLED @144), o conector será o **mesmo `HDMI-A-4`** → basta atualizar em **2 arquivos, na mesma sessão**:
> 1. `~/.config/hypr/config/monitors.lua` → `mode = "2560x1440@144"` (ou a spec da tela nova)
> 2. `/var/lib/noctalia-greeter/greeter.toml` → `[output] width/height` (+ `refresh_rate` quando o pacote do greeter suportar — v1.5.0 ainda não tem; ver nota acima)
> `direct_scanout=2` + VRR já prontos — só trocar a spec. Não precisa de `desc:`/catch-all (conector fixo).

**Política de dual DE (22/09):** Plasma instalado **intencionalmente** (uso se necessário — Dolphin, KDE Connect), mas daemons KDE desnecessários ficam **parados** na sessão Hyprland:
- ✅ Parados: `akonadi` (PIM), `kalendarac` (reminders — `.desktop` → `.disabled`), `kactivitymanagerd`, `baloo` (indexação — `.desktop` → `.disabled`), `powerdevil` (energia — `.desktop` → `.disabled`)
- ✅ Mantidos: **KDE Connect** (`org.kde.kdeconnect.daemon`), **Portal KDE** (`plasma-xdg-desktop-portal-kde` — necessário p/ Dolphin/file pickers Qt), `gnome-keyring`

**Cursor em TODAS as camadas (unificado 23/09, dual-spec Hyprcursor + XCursor no mesmo tema `McMojave`):**
O tema `McMojave` foi consolidado segundo a especificação oficial contendo simultaneamente `hyprcusors/` (vetorial SVG para Hyprland) e `cursors/` (binários XCursor reais de 36KB via `mcmojave-cursors` AUR), eliminando a assimetria de nomes (`McMojave` vs `McMojave-cursors`).
- **GTK 2/3/4**: `gtk-cursor-theme-name=McMojave` (settings.ini + gtkrc) · **gsettings**: `McMojave` (Hyprland `cursor:sync_gsettings_theme=true` sincroniza perfeitamente)
- **X11/XWayland**: `XCURSOR_THEME="McMojave"` no `uwsm/env` · **Qt/qt6ct**: `cursor=McMojave`
- **Hyprland nativo**: `HYPRCURSOR_THEME=McMojave`
- **Tamanho unificado**: **36px** em todas as camadas (confortável, nítido e equilibrado).
- Persistência: tudo em config disco (`uwsm/env`, settings.ini, qt6ct.conf, dconf, Xresources) — volta no reboot. Docs: [Hyprland wiki §hyprcursor](https://wiki.hypr.land/Hypr-Ecosystem/hyprcursor/) e [ArchWiki §Cursor themes](https://wiki.archlinux.org/title/Cursor_themes).

**⚠️ Cursor na Steam e apps "teimosos" (fix universal 23/09 — a Steam NÃO respeita XCURSOR_THEME sozinha):** a Steam (CEF + GTK antigo + chroot sandbox) consulta o **protocolo XSETTINGS** (que o KDE fornecia via kded6; o Hyprland não) + fallback `default` **físico**. Fix completo (issues Valve #10808/#825/#13209/#11484 e COSMIC#168):
1. Pacote `mcmojave-cursors` instalado via AUR com binários reais (corrigindo arquivos dummy de 0 bytes anteriores)
2. **Cópia FÍSICA** p/ `~/.local/share/icons/default` (`cp -r`, **sem symlink** — #11484: a Steam não segue symlink)
3. **`~/.config/xsettingsd/xsettingsd.conf`** → `Gtk/CursorThemeName "McMojave"` + `Gtk/CursorThemeSize 36` — **roda como user service `xsettingsd.service` (`WantedBy=graphical-session.target`)** — o mecanismo XSETTINGS que faltava; afeta também Electron legado, Java AWT, apps FHS-wrapped
4. `~/.Xresources` → `Xcursor.theme: McMojave` / `Xcursor.size: 36` + `xrdb -merge` + `autostart.lua`
5. **Calibração 1:1 XCursor vs Hyprcursor (fix Steam/KeePassXC 23/09):** O upstream do `mcmojave-cursors` mapeava uma imagem de 48px para o tamanho nominal 36 (fator 0.75), tornando apps X11 33% maiores que os apps Wayland nativos. Recompilamos o conjunto completo com `rsvg-convert` e `xcursorgen` garantindo proporção matemática 1:1 exata em todas as resoluções nominais (24, 28, 32, 36, 40, 48, 64).
- Reiniciar a Steam/KeePassXC p/ pegar (processo antigo não relê).
- ⚠️ **`xsettingsd` só relê o `.conf` ao ser (re)iniciado** — se mexer no nwg-look: `systemctl --user restart xsettingsd`. No boot o user service (graphical-session.target) já sobe com o tema correto.

## Atalhos Essenciais

### Abrir Aplicativos

| Atalho | O que faz |
|---|---|
| `Super + Return` | Terminal (kitty) |
| `Super + E` | Gerenciador de arquivos (Dolphin) |
| `Super + W` | Navegador (Zen) |
| `Super + T` | Editor de texto (gnome-text-editor) |
| `Super + C` | Calculadora |
| `Ctrl + Shift + Esc` | Monitor de sistema (btop) |
| `Super + Space` | **Launcher de apps** (Noctalia) |
| `Super + .` | Emoji picker |

### Janelas

| Atalho | O que faz |
|---|---|
| `Super + Q` | Fechar janela |
| `Super + Escape` | Matar janela (forçar fechar) |
| `Super + D` | Fullscreen (sem barra) |
| `Super + F` | Fullscreen (com barra) |
| `Super + ALT + Space` | Alternar float/tile (janela flutuante) |
| `Super + J` | Invert split (horizontal ↔ vertical) |
| `Super + Tab` | Window switcher (Noctalia) |
| `ALT + Tab` | Ciclar janelas |

### Navegar entre Janelas

| Atalho                     | O que faz                                |
| -------------------------- | ---------------------------------------- |
| `Super + Setas`            | Mover foco (esquerda/direita/cima/baixo) |
| `Super + Shift + Setas`    | Mover janela na direção                  |
| `Super + Mouse drag`       | Arrastar janela                          |
| `Super + Mouse right-drag` | Redimensionar janela                     |

### Workspaces (Áreas de Trabalho)

| Atalho | O que faz |
|---|---|
| `Super + Ctrl + Setas` | Trocar workspace (esquerda/direita) |
| `Super + Alt + 1/2/3` | Ir para workspace específico |
| `Super + Ctrl + 1/2/3` | Ir para workspace relativo |
| `Super + Mouse scroll` | Scroll entre workspaces |
| `Super + Shift + S` | Enviar janela para scratchpad |
| `Super + S` | Toggle scratchpad (mostrar/ocultar) |

**Mover janela entre workspaces** (binds reais do `binds.lua`, 22/09):

| Atalho | O que faz |
|---|---|
| `Super + Shift + Ctrl + N` | Move a janela pro workspace **N** e **você acompanha** (vai junto) |
| `Super + Shift + Alt + N` | Move a janela pro workspace **N**, mas **você fica** onde está |
| `Super + Ctrl + Shift + ←/→` | Move a janela pro workspace **anterior/próximo** (você acompanha) |
| `Super + Ctrl + Shift + scroll ↑/↓` | Move via roda do mouse (↑ = anterior, ↓ = próximo) |
| `Super + Shift + 1/2/3` | Move a janela pra **outro monitor** (MONITOR1/2/3) |

> ⚠️ **Não confundir:** `Super + Shift + Setas` move a janela de **posição no grid** (tile), não troca de workspace · `Super + Ctrl + Setas` só **navega** (foco) entre workspaces sem levar a janela · `N` = número do workspace (3 por monitor + o `gaming`).

### Noctalia Shell (Barra + Painéis)

| Atalho | O que faz |
|---|---|
| `Super + Space` | Abrir launcher de apps |
| `Super + X` | Painel de controle (WiFi, Bluetooth, etc.) |
| `Super + A` | Notificações |
| `Super + Z` | Configurações do Noctalia (tema, wallpaper) |
| `Super + V` | Clipboard (histórico de copiar) |
| `Super + Shift + W` | Trocar wallpaper |
| `Super + L` | Lock screen |
| `Super + ALT + C` | Menu de sessão (logout, reboot, shutdown) |

### Hardware

| Atalho | O que faz |
|---|---|
| `F2/F3` | Volume +/- |
| `F1` | Mute |
| `F4` | Mute microfone |
| `F7/F8` | Play/Pause, Próxima música |
| `Print` | Screenshot região |
| `Super + Print` | Screenshot tela inteira |
| `Super + P` | Color picker (hyprpicker) |

### Sessão (via Super + ALT + C)

| Tecla no menu | Ação |
|---|---|
| `1` | Lock screen |
| `2` | Logout |
| `3` | Lock + Suspend |
| `4` | Reboot |
| `5` | Shutdown |

### Zoom

| Atalho | O que faz |
|---|---|
| `Super + +` | Zoom in |
| `Super + -` | Zoom out |

## Scratchpad — O que é?

O scratchpad é um **workspace oculto especial**. Pense nele como um "drawer" que aparece e desaparece.

- `Super + Shift + S` → Envia a janela ativa para o scratchpad (ela some)
- `Super + S` → Abre/fecha o scratchpad (as janelas envolvidas aparecem sobre as outras)

**Uso prático:** mandar um terminal para o scratchpad e chamar com `Super + S` quando precisar, sem ocupar workspace.

## A Barra (Noctalia)

A barra no topo mostra:
- **Esquerda:** Launcher + Relógio + GPU temp + RAM usage
- **Centro:** Workspaces (dots) + Janela ativa
- **Direita:** Mídia + Tray + Notificações + WiFi + Volume + Sessão

## Dicas Iniciais

1. **Não existe "minimizar"** — janelas ficam em workspaces. Mova com `Super + Shift + Setas`
2. **Scratchpad** (`Super + S`) é um workspace oculto para apps que você quer acesso rápido
3. **Float** (`Super + ALT + Space`) para apps que precisam de tamanho fixo
4. **Tudo é configurável** em `~/.config/hypr/config/`

## Arquivos de Configuração

| Arquivo | O que controla |
|---|---|
| `~/.config/hypr/config/variables.lua` | Apps padrão, monitor, workspaces |
| `~/.config/hypr/config/binds.lua` | Todos os atalhos |
| `~/.config/hypr/config/monitors.lua` | Configuração do monitor |
| `~/.config/hypr/config/windowrules.lua` | Regras por app (float, opacity, etc.) |
| `~/.config/hypr/config/autostart.lua` | O que inicia com o Hyprland |
| `~/.config/noctalia/config.toml` | Tema, barra, widgets |
| `~/.config/uwsm/env` | Env da sessão gráfica (UWSM): cursor `HYPRCURSOR_THEME=McMojave` (nativo) + NVIDIA + toolkits |
| `~/.config/xdg-desktop-portal/portals.conf` | Portal config (file picker KDE) |

> 🖱️ **Cursor (instalado 22/09/2026, consolidado 36px em 23/09):** tema **McMojave** unificado (dual-spec hyprcursor nativo SVG + XCursor real AUR no mesmo tema) — Hyprland + apps Wayland + Noctalia + Steam + GTK/Qt. **Size 36px** (1080p, scale 1 — tamanho intermediário generoso, muito nítido e uniforme em todas as camadas). Troca em runtime: `hyprctl setcursor McMojave 36`; **persistência via `~/.config/uwsm/env`** (camada certa — o UWSM sopra o env da sessão por cima do environment.d; wiki Hyprland: use `uwsm/env` para theming/xcursor). Doc oficial: *"Put your theme(s) in ~/.local/share/icons or ~/.icons"* (wiki.hypr.land → hyprcursor).

## Comandos Úteis

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

## Portal Config (evitar conflito KDE/Hyprland)

Criado em `~/.config/xdg-desktop-portal/portals.conf`:
```ini
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=kde
```
Isso força o file picker do KDE no Hyprland, evitando que o Firefox perca logins ao alternar entre sessões.

## Referências

- [Hyprland Wiki](https://wiki.hypr.land/)
- [CachyOS Hyprland Wiki](https://wiki.cachyos.org/configuration/desktop_environments/hyprland)
- [Noctalia Wiki](https://wiki.hypr.land/Hyprland-and-Noctalia)

## ⚠️ Aprendizado: NÃO deletar hyprland.desktop

**ERRO COMETIDO:** Deletamos `hyprland.desktop` para deixar só o "managed", mas o UWSM precisa dele internamente.

O `hyprland-uwsm.desktop` chama:
```
Exec=uwsm start -e -D Hyprland hyprland.desktop
```

**Regra:** AMBOS os arquivos precisam existir em `/usr/share/wayland-sessions/`:
- `hyprland.desktop` → arquivo base que o UWSM usa internamente
- `hyprland-uwsm.desktop` → wrapper que o display manager mostra ao usuário

Se deletar o `hyprland.desktop`, o UWSM dá tela preta com erro "Could not find entry hyprland.desktop".

## 🎮 VRAM Management (dmemcg — NVIDIA via cgroups)

O Hyprland usa cgroups do kernel para gerenciar VRAM de forma dinâmica, igual ao Plasma.

**Stack instalada:**

| Componente | Função | Status |
|---|---|---|
| `dmemcg-booster` (system + user services) | Habilita controlador dmem e propaga cgroups | ✅ Ativo |
| `hyprland-focused-booster` (AUR) | Boost dinâmico de VRAM para janela focada | ✅ Ativo |

**Como funciona:**
- O kernel CachyOS tem `CONFIG_CGROUP_DMEM=y` (VRAM Cgroup/DMEM no DRM subsystem)
- O `dmemcg-booster` (system + user) propaga o controlador `dmem` até os cgroups de apps
- O `hyprland-focused-booster` escuta eventos `activewindow` do Hyprland (socket)
- Quando o foco muda → escreve `dmem.low = <toda VRAM>` no cgroup do app focada
- Apps em background → `dmem.low = 0` (evictáveis se precisar)

**Verificar se está funcionando:**
```bash
systemctl --user status hyprland-focused-booster
# O app FOCADO deve ter dmem.low alto (~8G), os outros 0:
for d in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-*/; do
  echo "$(basename $d) | dmem.low: $(cat $d/dmem.low 2>/dev/null | grep -oP 'vidmem \K.*')"
done
```

**Como o Noctalia se integra:** `launch_apps_as_systemd_services = true` no `~/.config/noctalia/config.toml` → apps do launcher já rodam em cgroups systemd, que é o que o booster precisa para resolver PID → cgroup.

**Games (Steam):** Steam já é systemd service → jogos herdam o cgroup → boost automático. Para boost por jogo: launch options `systemd-run --user --scope %command%`.

> ⚠️ NUNCA rode `pacman -Rns $(pacman -Qdtq)` cegamente — `noctalia`, `uwsm`, `swash` ficaram órfãos após a remoção do `cachyos-hypr-noctalia` e foram marcados explícitos.

## 🩺 Verificação de saúde GPU/VRAM (checklist executável)

Probe completo para validar que todo o stack de vídeo está funcionando (GPU, ReBAR, dmem, boost):

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

**Criterio de OK (verificado 21/09/2026):** GPU RTX 5050 + driver 615.71.09 · ReBAR=1 (modprobe + cmdline + module) · 3 serviços ativos · `dmem` no controller · focada=8G / bg=0.

## ⚙️ Parâmetros NVIDIA fixados (psicopompo)

**`/etc/modprobe.d/nvidia-rebar.conf`:**
```
options nvidia NVreg_EnableResizableBar=1
```

**`~/.config/uwsm/env` (variáveis NVIDIA + app defaults):**
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
- `nvidia-drm.modeset=1` — KMS obrigatório p/ Wayland
- `nvidia.NVreg_EnableResizableBar=1` — ReBAR (espelho do modprobe)
- `nvidia.NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100` — fix I2C
- `resume=UUID=ffc60b3e-2f31-47bb-b51e-4eb785af8647 resume_offset=60761344` — hibernação (swapfile 48G)

**Módulos carregados (lsmod):** `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm` (+ `drm_ttm_helper`).

> 💡 `PreserveVideoMemoryAllocations=2` no driver (auto) — preserva VRAM entre suspend/resume. Não é a VRAM cgroup (dmem), são coisas diferentes.

## ⚠️ Quirk: Smooth Motion vs direct_scanout do Hyprland (30fps lock)

**Sintoma:** jogo com `NVPRESENT_ENABLE_SMOOTH_MOTION=1` trava em **metade do refresh** (30fps num monitor 60Hz) em fullscreen; **pausa sobe FPS / rodando trava; windowed funciona / fullscreen trava**.

**Causa raiz (canonizada 21/09/2026):** o Hyprland com `render.direct_scanout = 2` manda a swapchain **direta ao display** em fullscreen, pulando a composição. O layer `VK_LAYER_NV_present` (Smooth Motion) **não consegue injetar frames** nesse caminho → frame pacing ABAB (GPU ~15%, trava em metade).

**Por que no KDE funcionava:** o KWin **sempre compõe** (não tem o direct scanout agressivo do Hyprland) → o NVPRESENT injeta frames normalmente.

**SOLUÇÃO DEFINITIVA (Opção C — with-smooth-motion, canonizada 23/09/2026):**
Em 21/09 testou-se gamescope (Opção B), mas gerou efeitos colaterais indesejados (VSync in-game travava o SM, e sem VSync ocorria jitter/"efeito elástico" de frametime).
A solução definitiva é o wrapper adaptativo **`with-smooth-motion`** (`/usr/local/bin/with-smooth-motion`):
```bash
# Executa jogo com Smooth Motion sem gamescope e sem desligar o scanout global:
with-smooth-motion %command%
```
**Como funciona:**
1. Binário nativo em Rust (`~/homelab/with-smooth-motion/`, instalado em `/usr/local/bin/with-smooth-motion`).
2. Detecta Hyprland e suspende temporariamente o direct scanout em tempo de execução via `hyprctl eval 'hl.config({ render = { direct_scanout = 0 } })'`.
3. Seta `NVPRESENT_ENABLE_SMOOTH_MOTION=1` de forma segura no processo filho.
4. O jogo roda direto no Hyprland (Wayland nativo puro, sem gamescope e sem VSync).
5. O `Drop` guard em Rust (RAII) e tratador de sinais (`SIGINT`, `SIGTERM`, `SIGHUP`) restauram instantaneamente `direct_scanout = 2` no encerramento (normal ou crash).
6. Em outros compositors (ex: KDE Plasma), não afeta o compositor. Zero perda para os outros 35 jogos e máxima fluidez no Valheim.
7. Para replicar em novos jogos: ver Playbook em [[psicopompo-gaming#🪄 Playbook: Como Habilitar Smooth Motion em Novos Jogos (Replicabilidade)]].

> ⚠️ **Não combinar SM com:** `dxvk.latencySleep=True` / `dxvk.maxFrameLatency=1` (lock 30fps em Unity: DXVK #5507) · V-Sync in-game ON (trava em metade) · limiter de FPS (trava; caso Fallout76: cap 120 + SM = 30fps).

### ℹ️ Scanout global = `2` (auto p/ jogos) — confirmado na wiki

`render.direct_scanout = 2` significa **auto: ativa com content type 'game'** (a wiki oficial: *"2 - auto (enabled with content type 'game')"*). Como as windowrules marcam os jogos com `content = "game"` + `fullscreen_state = 2`, o scanout direto (latência mínima) só é ativado em **fullscreen de jogo** — não incomoda o resto do desktop.

### 🟥 ALERTA: tela preta em jogos native-wayland (Hyprland #14843)

**Cenário (igual ao psicopompo):** jogo com `PROTON_ENABLE_WAYLAND=1` (native wayland via Proton) + NVIDIA + `direct_scanout=2` pode abrir **tela preta no fullscreen** (áudio continua, input funciona, cursor devolve a imagem). É um **bug conhecido Hyprland×NVIDIA×winewayland** (mesma discussão da comunidade: Overwatch, EZFN, Helldivers 2). KDE não afetado — lá o DS nem ativa com winewayland NVIDIA.

**Soluções (community):**
1. `render:non_shader_cm = 0` → resolve maioria (mas desativa scanout)
2. `quirks:skip_non_kms_dmabuf_formats = 1` → resolve mas **força VSync** em todos os jogos native-wayland
3. Rodar o jogo sem `PROTON_ENABLE_WAYLAND=1` (XWayland não é afetado)

> Se algum jogo do psicopompo abrir tela preta no fullscreen com Wayland, aplicar a opção 1 ou 3. (Ainda não ocorreu — alerta preventivo.)

## 🎮 Inventário de otimizações de gaming (canonizado 21/09/2026 — fontes wiki)

> Tudo abaixo **já está ativo** no psicopompo. Valide com um comando: **`stenio --gaming`**
> (Raio-X sessão-aware — detecta Hyprland vs KDE e audita cada item abaixo).

| # | Otimização | Fonte | Onde está |
|---|---|---|---|
| 1 | Kernel **CachyOS-BORE** (7.2.6) | [CachyOS wiki](https://wiki.cachyos.org/features/kernel/) | `uname -r` |
| 2 | **VRAM management (dmemcg)** — `CONFIG_CGROUP_DMEM` + `dmemcg-booster-{system,user}` + `hyprland-focused-booster` | CachyOS feature | cgroup v2 + 3 serviços |
| 3 | **game-performance** on-demand (profile → `performance` durante o jogo) | [CachyOS wiki §Power Profile](https://wiki.cachyos.org/configuration/gaming/) | launch options de **36/36 jogos** |
| 4 | **NTSYNC** (`/dev/ntsync` + `PROTON_USE_NTSYNC=1`) | ArchWiki | `~/.config/environment.d/env.conf` |
| 5 | **ReBAR** (`nvidia.NVreg_EnableResizableBar=1`) | NVIDIA/CachyOS | `/proc/cmdline` |
| 6 | **DLSS upgrade global** (`PROTON_DLSS_UPGRADE=1`) | [CachyOS wiki §DLSS](https://wiki.cachyos.org/configuration/gaming/) | `~/.config/environment.d/gaming.conf` |
| 7 | **Shader cache NVIDIA 12GB** (`__GL_SHADER_DISK_CACHE_SIZE=12000000000`) | [CachyOS wiki §Shader cache](https://wiki.cachyos.org/configuration/gaming/) | `~/.config/environment.d/gaming.conf` — aplicado 21/09 |
| 8 | **Shader pre-caching do Steam DESLIGADO** (Proton CachyOS/GE já tem codecs) | [CachyOS wiki §Pre-caching](https://wiki.cachyos.org/configuration/gaming/) | Steam → Settings → Downloads — desligado 21/09 |
| 9 | **Scanout direto p/ games** (`direct_scanout=2`, auto com content `game`) | [Hyprland wiki](https://wiki.hypr.land/Configuring/Variables/) | `~/.config/hypr/config/misc.lua` |
| 9b | **Splash/logo do Hyprland DESLIGADOS** (`disable_splash_rendering` + `disable_hyprland_logo`, 22/09 — matou o flash <1s do wallpaper da distro entre login e Noctalia; cor do splash reverdida de `SUMAEPrimary` p/ `CACHYLGREEN`, padrão skel) | [Hyprland wiki §misc](https://wiki.hypr.land/Configuring/Basics/Variables/) | `~/.config/hypr/config/misc.lua` + `colors.lua` |
| 10 | **Windowrule** `content = "game"` + `fullscreen_state = 2` (gatilho do scanout) | Hyprland wiki | `~/.config/hypr/config/windowrules.lua` |
| 11 | **Clocksource TSC** (menos overhead que HPET) | [ArchWiki §clock_gettime](https://wiki.archlinux.org/title/Gaming#Improve_clock_gettime_throughput) | `/sys/devices/system/clocksource/...` |
| 12 | **Wayland em todos os jogos** (`PROTON_ENABLE_WAYLAND=1` + `PROTON_USE_NTSYNC=1`) | Proton-EM / CachyOS | `env.conf` + launch options |
| 13 | **VRAM cgroup em todos os jogos** (`systemd-run --user --scope`) | Arquitetura dmemcg | launch options de 36/36 |
| 14 | **Gamescope isolado p/ Valheim** (Smooth Motion compõe só nele) | [ArchWiki §Utilities](https://wiki.archlinux.org/title/Gaming) | perfil `r2modman-valheim` |

**Avisos informativos (NÃO alterados — decisão do dono):**
- `vm.max_map_count` = `1048576` — Proton trata como suficiente (SteamOS usa `2147483642`, opcional)
- `kernel.split_lock_mitigate` — `0` melhora certos jogos Wine (ArchWiki), não aplicado
- V-Sync in-game + SM → conflito; limiter de FPS + SM → trava (ver quirk acima)

**Backup das configs de gaming (ativado 21/09):** `~/.config/hypr`, `~/.config/noctalia`, `~/.config/uwsm` (22/09 — cursor/NVIDIA), `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia` agora são espelhados pelo `config-backup` (05:00) → NAS + git + restic + snapper. O `noctalia config export` roda 04:55 (timer user) gerando `merged-config.toml` na pasta espelhada. Ver [`../backups/config-backup.md`](../backups/config-backup.md).

## 💾 Swap: ZRAM + hibernação (configurado corretamente)

| Swap | Tamanho | Prioridade | Uso |
|---|---|---|---|
| `/dev/zram0` (zstd) | 46.9G (`zram-size = ram`) | **100** | Usado primeiro (compressed RAM) |
| `/swap/swapfile` | 48G | **1** | Só hibernação (`resume=`) |

Confirmação:
- `zram-generator.conf` → `swap-priority = 100` ✅
- `/etc/fstab` → `/swap/swapfile ... pri=1` ✅
- Kernel params: `resume=UUID=ffc60b3e... resume_offset=60761344` → hibernação usa o swapfile ✅

## 📦 Descoberta importante: pacotes CachyOS Hyprland

**`cachyos-hypr-noctalia` e `cachyos-hyprland-settings` são MUTUAMENTE EXCLUSIVOS** — ambos têm `Provides: cachyos-desktop-settings` + `Conflicts With: cachyos-desktop-settings`. Instalar um **remove o outro automaticamente** (por isso o Noctalia virou orphan sem log explícito de remoção).

- ✅ **`cachyos-hypr-noctalia`** — o CORRETO (meta-pacote com deps: noctalia, uwsm, kitty, qt6ct, brightnessctl, grim, slurp, etc.)
- ❌ **`cachyos-hyprland-settings`** — vanilla (waybar/mako/wofi/swaylock), desnecessário p/ Noctalia

**Pacotes hypr* extras NÃO necessários** (Noctalia substitui):
- `hyprlock` → `noctalia msg session lock`
- `hypridle` → serviço Idle embutido
- `hyprsunset` → Night Light embutido
- `hyprpolkitagent` → `polkit_agent = true`
- `hyprlauncher` / `hyprpaper` / `hyprshot` / `grimblast` → embutidos ou usa `swash`
- `nwg-*`, `dms-shell-hyprland` → incompatíveis com Noctalia

**Se os serviços de lock/idle não funcionarem** após remover os extras, verificar o que o Noctalia usa internamente (o package `noctalia` não depende de hyprlock/hypridle).

## 🔎 Buscar pacotes com Shelly (CLI)

O Shelly tem busca CLI útil para conferir disponibilidade:
```bash
shelly search standard -v hypr    # repos oficiais
shelly search aur hypr            # AUR
```
