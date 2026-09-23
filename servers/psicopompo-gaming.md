---
tags: [homelab, service, steam, gaming, server, psicopompo, tutorial]
---

# psicopompo-gaming

See also: [[psicopompo]] · [[hyprland-noctalia-guide]]

---

## 🎮 Stack de gaming (psicopompo)

| Componente | Versão | Função |
|---|---|---|
| GPU | RTX 5050 (driver 615.71.09, nvidia-open) | Ray tracing + DLSS |
| ReBAR | ✅ ON (`NVreg_EnableResizableBar=1`) | Resizable BAR habilitado |
| Proton default | `proton-cachyos-slr` | Proton CachyOS (default do sistema) |
| GE-Proton | `GE-Proton11-7-x86_64` (autoupdate semanal) | Ray tracing pesado (Portal RTX) |
| VRAM boost | `dmemcg-booster` + `hyprland-focused-booster` | VRAM priorizada p/ janela focada via cgroups |
| Wrapper | `game-performance` | Power profile performance + desativa screensaver |
| Monitoramento | `mangohud` (Shift_R+F12) | FPS/temperatura in-game |

> 🔍 **Checklist de saúde GPU/VRAM + parâmetros NVIDIA fixados:** ver
> [[hyprland-noctalia-guide]] (seções 🩺 Verificação de saúde e ⚙️ Parâmetros NVIDIA).

> 🖥️ **Raio-X de Gaming Health:** rodar `stenio --gaming` — auditoria sessão-aware do
> stack completo (VRAM dmemcg, scanout do Hyprland, 36/36 launch options, DLSS,
> kernel/NTSYNC/ReBAR, shader cache 12GB). Deteta Hyprland vs KDE automaticamente.

### 🏗️ Arquitetura global de gaming (canonizada 21/09)

| Camada | Escopo | Estado |
|---|---|---|
| **VRAM boost** (`systemd-run --user --scope` + dmemcg) | **TODOS os 36 jogos** | ✅ Ativo em todos |
| **Wayland** (`PROTON_ENABLE_WAYLAND=1`) | Todos os jogos com Proton | ✅ Ativo |
| **Scanout direto** (`direct_scanout=2`, auto p/ game) | 35 jogos (36 quando Valheim fechado) | ✅ Latência mínima |
| **Smooth Motion** (`with-smooth-motion`) | Valheim (expansível p/ qualquer jogo) | ✅ Nativo sem gamescope |
| **Wrapper adaptativo** (`with-smooth-motion`) | Jogos com Smooth Motion | ✅ Suspende scanout durante o jogo, restaura ao sair |
| **DLSS upgrade** (env global) | Todos os jogos com DLSS | ✅ via environment.d |

**Regra de ouro:** VRAM + Wayland em TUDO; scanout direto ativo globalmente por padrão; jogos com Smooth Motion usam o wrapper adaptativo `with-smooth-motion` — nunca desligar otimização global por causa de 1 jogo.

## 🛠️ steam-launch-options (script CLI, Rust)

Gerenciador **declarativo** de launch options e Proton do Steam.

- **Binário:** `~/.local/bin/steam-launch-options`
- **Fonte:** `~/homelab/steam-launch-options/`
- **Config:** `~/.config/steam-launch-options/{profiles,games}.toml`
- **Autoupdate GE-Proton:** timer systemd semanal (`steam-ge-update.timer`)

> **🖥️ Wayland obrigatório:** política do homelab — TODOS os jogos rodam com
> `PROTON_ENABLE_WAYLAND=1` (winewayland.drv nativo). Xwayland é exceção rara
> (perfil `wayland_fallback`) para jogos que quebram com launchers (ex: white screen).

### Uso

```bash
steam-launch-options list       # jogos + perfil + proton + divergências
steam-launch-options sync       # aplica TODOS os perfis (idempotente, com backup)
steam-launch-options apply 730  # aplica perfil de um jogo
steam-launch-options status     # divergências TOML vs Steam (dry-run)
steam-launch-options backup     # backup manual dos .vdf
steam-launch-options discover [--add]   # detecta jogos novos nas bibliotecas montadas
steam-launch-options ge-update  # atualiza GE-Proton p/ última release
```

> ⚠️ **Steam deve estar FECHADO** para `sync`/`apply` (senão os .vdf são sobrescritos pelo Steam ao sair). Detecção de Steam usa `pgrep -x` (match exato) — não pega o próprio binário.

### 🎯 Política de Proton (canonizada 2026-09-21)

| Categoria | Proton | Perfil |
|---|---|---|
| **Multiplayer online / anti-cheat** | `proton_experimental` | `vram` |
| **Triple A / RTX** | `GE-Proton` (autoupdate) | `vram`/`dx12`/`rtx` |
| **Indie / leve / estável** | default (`proton-cachyos-slr`) | `vram` |
| Single player com coop opcional | GE (single é o foco) | `vram` |

Bom senso: jogos com modo multiplayer mas que você joga single → pode ficar GE. Regra rígida para jogos multiplayer por natureza (Sea of Thieves, MK1, RDR2 online, Valheim, L4D2, RoR2, Civ V) → experimental.

> **⚙️ Darktide (GE, não experimental — pareceria erro):** é multiplayer co-op online,
> MAS o **Easy Anti-Cheat foi removido em jun/2024** (Fatshark, PCGamingWiki). Sem
> anti-cheat, GE é seguro e melhor p/ DX12 + RTX (a regra "multiplayer → experimental"
> existe por causa do anti-cheat; sem ele, GE vence).
>
> **💎 DLSS — GLOBAL (não é por jogo):** `PROTON_DLSS_UPGRADE=1` em
> `~/.config/environment.d/gaming.conf` — CachyOS wiki best practice. Aplica a
> **todo jogo/proton** (default, GE, experimental), sem launch options por-jogo:
> qualquer jogo baixado já usa o DLSS mais atualizado automaticamente.
>
> **💾 Shader cache — GLOBAL (12GB, 21/09/2026):** `__GL_SHADER_DISK_CACHE_SIZE=12000000000`
> no mesmo `gaming.conf` (valor canônico da CachyOS wiki §Increase shader cache size) —
> evita recompilar shaders toda hora (stutter no 1º launch de jogos grandes).
> Aplicado junto com o **Shader Pre-caching do Steam DESLIGADO** (Settings → Downloads):
> a wiki recomenda desligar quando se usa Proton CachyOS/GE (já trazem os codecs).
>
> **🎮 Valheim + r2modman (quirk conhecido):** o jogo tem build nativa Linux E
> Proton, mas os mods rodam via wrapper do r2modman
> (`web_start_wrapper.sh` inserido no meio da launch command, perfil `r2modman-valheim`).
> **Proton usado: `proton_experimental`** — escolha deliberada: por ser da Valve,
> o prefixo é mantido em-place pelo Steam (sem o quirk de reabrir vanilla a cada
> mudança de tool). Com GE (tool separada) seria preciso abrir 1x vanilla a cada
> release nova — desnecessário aqui.
> **Smooth Motion (`NVPRESENT_ENABLE_SMOOTH_MOTION=1`):** ligado no Valheim.
> **⚠️ CAUSA RAIZ do 30fps (canonizado 21/09):** o Hyprland com
> `render.direct_scanout = 2` mandava a swapchain DIRETA ao display em fullscreen,
> pulando a composição → o layer `NVPRESENT` (Smooth Motion) não conseguia injetar
> frames → frame pacing ABAB (GPU ~15%, trava em metade do refresh = 30fps num
> monitor 60Hz). Sintoma confirmado: **pausa sobe / rodando trava; windowed
> funciona / fullscreen trava**.
> **SOLUÇÃO DEFINITIVA (Opção C — with-smooth-motion, canonizada 23/09/2026):**
> Em 21/09 testou-se gamescope (Opção B), mas gerou trade-offs indesejados:
> com VSync o SM congelava, e sem VSync surgia "efeito de elástico" no frametime.
> A solução definitiva, escalável e open-source é o utilitário Rust **`with-smooth-motion`**
> ([GitHub: ceduardorodrig/WITH-SMOOTH-MOTION](https://github.com/ceduardorodrig/WITH-SMOOTH-MOTION) · `/usr/local/bin/with-smooth-motion`), que:
> 1. Suspende temporariamente o direct scanout no Hyprland (`hyprctl eval 'hl.config({ render = { direct_scanout = 0 } })'`)
> 2. Mantém uma **thread watchdog ativa** a cada 2s para recuperar o scanout caso Alt+Tab ou troca de desktop o resetem
> 3. Seta `NVPRESENT_ENABLE_SMOOTH_MOTION=1` nativamente no processo filho
> 4. Roda o jogo de forma nativa e pura (sem o overhead nem o jitter do gamescope)
> 5. Repassa sinais graciosos (`SIGINT`, `SIGTERM`) ao filho e restaura `direct_scanout = 2` via RAII (`ScanoutGuard::drop`)
> 6. Se rodar em outro compositor (ex: KWin de fallback), não mexe em nada e roda limpo.
> Dessa forma, os 36 jogos usam direct scanout e baixa latência, e qualquer jogo
> que desejar Smooth Motion roda com composição ativa sob demanda.
> Regras importantes:
> - **V-Sync do jogo deve ficar OFF** — com V-Sync ligado, o Smooth Motion
>   conflita e trava em metades do refresh.
> - **Sem limitador de FPS** — preferência do usuário (limiter também trava
>   o SM; caso Fallout76: cap 120 + SM = 30fps).
> - **`dxvk.latencySleep=True` / `dxvk.maxFrameLatency=1` NÃO combinam com SM**
>   — causam o lock de 30fps em jogos Unity (DXVK #5507 + Smooth Motion FAQ).
> - **`PROTON_ENABLE_NVAPI=1` é LEGADO/desnecessário** — desde o Proton 9 o
>   DXVK-NVAPI já é ativado por padrão para todos os títulos; a flag não faz
>   mais nada. Removida.
> - **`DXVK_NVAPI_REFLEX_LOW_LATENCY=2` NÃO EXISTE** — env var desconhecida é
>   ignorada (a linha antiga funcionava apesar dela). Não usar.
> **Flawless flow:**
> 1. Abrir pelo **r2modman → Start Modded** (preenche `wrapper_args.txt`
>    com o BepInEx wrapper; o arquivo é limpo a cada execução, então vanilla
>    direto pelo Steam roda sem mods — comportamento anti-injeção do r2modman)
> 2. O wrapper é criado/atualizado pelo próprio r2modman quando você usa o
>    botão Start Modded.
> ⚠️ O Steam precisa ser **reiniciado** para detectar compat tools novas —
> relevante para o GE (não para o experimental, que o Steam gerencia).

### 🪄 Playbook: Como Habilitar Smooth Motion em Novos Jogos (Replicabilidade)

O Smooth Motion da NVIDIA (`VK_LAYER_NV_present`) gera frames interpolados via IA. Para replicar a mesma fluidez perfeita do Valheim em qualquer outro jogo da biblioteca:

1. **Jogos Vanilla (sem mods / padrão Steam):**
   Basta associar o jogo ao perfil **`smooth_motion`** em `~/.config/steam-launch-options/games.toml`:
   ```toml
   [[games]]
   appid = <APPID_DO_JOGO>
   profile = "smooth_motion"
   proton = "proton_experimental" # ou GE-Proton conforme a categoria
   note = "Jogo com Smooth Motion nativo via with-smooth-motion"
   ```
   E aplicar (com Steam fechado):
   ```bash
   steam-launch-options apply <APPID_DO_JOGO>
   ```

2. **Jogos com Mods / Wrappers (ex: r2modman, BepInEx):**
   Adicione o `/usr/local/bin/with-smooth-motion` antes do script do wrapper no `profiles.toml`:
   ```toml
   [[profiles]]
   name = "r2modman-<jogo>"
   description = "Mods + Smooth Motion nativo com scanout adaptativo"
   options = "PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance /usr/local/bin/with-smooth-motion \"/path/to/wrapper.sh\" %command%"
   ```

3. **Regras In-Game Obrigatórias (para qualquer jogo com SM):**
   - **V-Sync in-game:** sempre **OFF** (o VSync FIFO in-game faz o frame generator descartar quadros).
   - **Limitador de FPS in-game:** sempre **OFF / Ilimitado**.
   - O wrapper em Rust (`with-smooth-motion`, código-fonte em `~/homelab/with-smooth-motion/`) suspende o direct scanout do Hyprland automaticamente durante a partida e restaura `direct_scanout = 2` no momento em que você fecha o jogo. Zero intervenção manual.

### 📦 Descoberta automática de bibliotecas (HD removível)

O `discover` lê o `libraryfolders.vdf` do Steam (que registra todas as bibliotecas, montadas ou não):

- **HD desconectado** → bibliotecas ausentes são ignoradas, jogos não quebram
- **Mount mudou** → o path atual é lido dinamicamente (ex: `/run/media/edu/EXPANSION-2TB`)
- **Jogo novo instalado** → `discover` sugere perfil por tamanho (`SizeOnDisk`):
  - `≥ 20G` → `vram`
  - `< 5G` → `vram` (indie leve, mas VRAM ativo)
- `discover --add` gera as entradas no `games.toml` automaticamente

### 📐 Governança de Perfis (canonizada 21/09)

Regras claras para decidir quando criar/manter um perfil:

| Categoria | Padrão de nome | Quando usar |
|---|---|---|
| **Base** | `vram` | Qualquer jogo sem necessidade especial (o default) |
| **Por API/render** | `dx12`, `rtx`, `low_latency` | Flags específicas de API/render (DX12, RTX, competição) |
| **Exceção por-jogo** | `ferramenta-jogo` (ex: `r2modman-valheim`) | SÓ quando um jogo é o único que usa (wrapper de mod, flag de um jogo) |
| **Global (env)** | `environment.d/gaming.conf` | Flags que valem p/ TODO jogo/proton (DLSS upgrade) — NÃO viram perfil |

**Regras práticas:**
1. **Perfis base/API** precisam de razão técnica real (descriptor_heap, Reflex, etc.)
2. **Perfis de exceção** = nome `ferramenta-jogo` — nunca genérico (`r2modman` vira `r2modman-valheim` quando o wrapper é de um jogo só)
3. **Flags on-demand** (ex: `NVPRESENT_ENABLE_SMOOTH_MOTION`): adicionar **conforme necessidade** (regra do usuário) — não aplicar em tudo sem um sintoma
4. **Jogo novo** → rotina: `discover --add` → ajustar proton (multiplayer→experimental, AAA→GE) → `sync`
5. **Mods (r2modman etc.)** → wrapper é **por-jogo** (path do `web_start_wrapper.sh`): cada jogo com mods ganha seu perfil `r2modman-<jogo>`

### Perfis (profiles.toml)

| Perfil | Launch options | Uso |
|---|---|---|
| `vram` | `PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command%` | Padrão (22 jogos: indie/AAA sem flags especiais) |
| `gta4` | `WINEDLLOVERRIDES="dinput8=n,b" PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command% -nomemrestrict -norestrictions` | GTA IV legacy (dinput8 override) |
| `rtx` | `DXVK_NVAPI_VKREFLEX=1 PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command%` | Ray tracing + Reflex Vulkan (Portal RTX) |
| `dx12` | `VKD3D_CONFIG=descriptor_heap PROTON_VKD3D_LOWLATENCY=1 PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance %command%` | **DX12**: descriptor_heap (+5-8% FPS) + vkd3d low-latency (Reflex DX12) |
| `low_latency` | `PROTON_ENABLE_WAYLAND=1 PROTON_DXVK_LOWLATENCY=1 systemd-run --user --scope game-performance %command%` | Competitivo DX11 (CS2) |
| `smooth_motion` | `PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance with-smooth-motion %command%` | Jogos genéricos com Smooth Motion nativo (desativa direct_scanout durante a sessão) |
| `r2modman-valheim` | `WINEDLLOVERRIDES="winhttp,version=n,b" PROTON_ENABLE_WAYLAND=1 systemd-run --user --scope game-performance with-smooth-motion "<wrapper r2modman Valheim>" %command%` | Valheim mods + Smooth Motion nativo com scanout adaptativo (sem gamescope, sem vsync, sem lock) |
| `wayland_fallback` | `systemd-run --user --scope game-performance %command%` | SEM Wayland (Xwayland) p/ jogos que quebram no winewayland |

> **💾 Política VRAM (canonizada 21/09):** TODOS os perfis incluem
> `systemd-run --user --scope` (VRAM boost) — inclusive indie/leve.
> **🖥️ Wayland:** em todos os perfis (exceto `wayland_fallback`, exceção rara).
> **💎 DLSS — GLOBAL (CachyOS wiki best practice):** `PROTON_DLSS_UPGRADE=1`
> definido em `~/.config/environment.d/gaming.conf` → aplica a TODO jogo/Proton
> (default, GE, experimental) sem launch options per-jogo. Qualquer jogo baixado
> já usa DLSS atualizado automaticamente.
> **⚡ Perfil `dx12`:** 11 jogos (Control, Cyberpunk, RDR2, RE4, Returnal, MK1,
> Darktide, Scorn, Midnight Walk, Viewfinder, Teardown) — descriptor heap +
> vkd3d low-latency (Reflex DX12 nativo, Proton-CachyOS 11+). DLSS upgrade fica
> o global (env), não repete no perfil.
> **🐛 GTA IV:** `WINEDLLOVERRIDES="dinput8=n,b"` (dinput8 override p/ FusionFix/modding)
> + `-nomemrestrict -norestrictions` (remove limite de memória — ProtonDB Gold).

### Proton por jogo (games.toml)

**NVMe PCI (12 jogos):**

| Jogo (AppID) | Perfil | Proton |
|---|---|---|
| GTA IV (12210) | gta4 | default |
| **Expedition 33 (1903340)** | vram | **GE-Proton** |
| CS2 (730) | low_latency | default* |
| Enshrouded (1203620) | vram | default |
| Ghostrunner (1139900) | vram | default |
| **Hellblade (414340)** | vram | **GE-Proton** |
| Out of Action (1670780) | vram | default |
| **Portal RTX (2012840)** | **rtx** | **GE-Proton (autoupdate)** |
| **Project Zomboid (108600)** | vram | **proton_experimental (FIXO — saves)** |
| **Scorn (698670)** | **dx12** | default |
| **The Midnight Walk (2863640)** | **dx12** | default |
| **Valheim (892970)** | **r2modman-valheim** | **experimental (r2modman mods)** |
| **Darktide (1361210)** | **dx12** | **GE-Proton (EAC removido 2024)** |

*\*CS2 é nativo Linux (não usa Proton) — só o perfil low_latency se aplica.*

**SSD SATA (6 jogos):**

| Jogo (AppID) | Perfil | Proton |
|---|---|---|
| Incredibox (1545450) | vram | default |
| **L4D2 (550)** | vram | **experimental (coop)** |
| Noita (881100) | vram | default |
| The Long Dark (305620) | vram | default |
| **Viewfinder (1382070)** | **dx12** | **GE-Proton (DLSS)** |
| I Am Your Beast (1876590) | vram | default |

**HD 2TB EXPANSION (17 jogos):**

| Jogo (AppID) | Perfil | Proton |
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

> ⚠️ **NÃO mudar o Proton do Zomboid** (`proton_experimental`) — os saves dependem desse prefix/ferramenta.

> ⚠️ NÃO adicionar `PROTON_ENABLE_NVAPI=1` — o Proton 11 já habilita NVAPI por padrão.

> 💾 **HD EXPANSION-2TB é removível** — quando desconectado, os jogos dele ficam "ausentes" mas o script não quebra (lê `libraryfolders.vdf` dinamicamente).

## 🐛 Aprendizado: Portal RTX apontava para GE-Proton11-6 removido

O `config.vdf` mapeava o Portal RTX para `GE-Proton11-6-x86_64`, mas essa versão foi **deletada** pelo usuário (só existe `GE-Proton11-7`). O Steam mostrava a tool como inválida — jogo podia falhar ao iniciar.

**Fix:** `steam-launch-options sync` (com Steam fechado) atualiza o mapping para a versão instalada. O `ge-update` mantém o mapping sincronizado com a última release automaticamente (timer semanal).

## 📦 GE-Proton autoupdate (timer semanal)

```bash
systemctl --user status steam-ge-update.timer   # ver timer
systemctl --user list-timers steam-ge-update    # próxima execução
steam-launch-options ge-update                  # forçar agora
```

O `ge-update`:
1. Consulta a última release do GitHub (`GloriousEggroll/proton-ge-custom`)
2. Se nova → baixa, extrai em `compatibilitytools.d/`, remove versão antiga
3. Atualiza `games.toml` para a nova versão
4. Atualiza o mapping no `config.vdf` (só se Steam fechado — senão avisa)

## 📝 Rotina ao instalar jogo novo

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

### Resumo Visual da sua Área de Trabalho

- **Barra/Widgets:** System Monitor na barra (GPU temp/RAM) — ver [[hyprland-noctalia-guide]].
- **Shift_R + F12:** MangoHud (FPS/temp) — "botão de pânico" p/ ver se a GPU está trabalhando.