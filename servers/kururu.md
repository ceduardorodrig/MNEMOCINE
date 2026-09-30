---
tags: [homelab, server, kururu]
---

# Kururu — Nó Dedicado Headless

Nó leve e autônomo do homelab Mnemocine construído sobre o hardware reaproveitado do **Samsung Galaxy Tab 3 Lite 7.0 (SM-T110)**. Executa **Alpine Linux v3.20 puro** em modo bare-metal headless (sem Android / sem interface gráfica), operando como servidor de utilidades, relay Tailscale e nó de execução local.

## Especificações de Hardware

| Componente | Especificação |
|---|---|
| **Dispositivo** | Samsung Galaxy Tab 3 Lite 7.0 (`SM-T110` / `samsung-goyawifi`) |
| **SoC / Chipset** | Marvell PXA986 (Dual-Core ARM Cortex-A9 @ 1.2 GHz) |
| **Arquitetura** | `armv7l` (ARM 32-bit com NEON/VFPv3) |
| **Memória RAM** | 1 GB LPDDR2 (~816 MB visíveis pelo kernel, **>770 MB livres**) |
| **Armazenamento Interno** | 8 GB eMMC v4.5 (Partição `/data` ext4 de 5.1 GB para o rootfs) |
| **Wi-Fi** | Marvell SD8777 (802.11 b/g/n, driver `sd8xxx` + `mlan` oficial) |
| **Consumo Elétrico** | < 0.8W em idle (backlight desligado via framebuffer) |
| **Alimentação** | Cabo Micro-USB conectado permanentemente (bateria gerenciada via AXP228 PMIC) |

## Arquitetura de Software

O nó opera em modo **Native Headless Linux**:
1. **Bootloader & Kernel:** Bootloader OEM desbloqueado carrega o kernel Linux 3.4.5 oficial da Samsung/Marvell com calibração de rádio e suporte de baixo nível ao silício.
2. **Eliminação do Android:** Os subsistemas Android (`zygote`, `surfaceflinger`, `system_server`, `media`, `drm`, `bootanim`) foram desativados (`disabled`) na ramdisk de boot (`kururu_headless_boot.img`). O tablet não carrega a JVM, consumindo apenas 43 MB de RAM na inicialização.
3. **Userspace:** Rootfs completo **Alpine Linux v3.20.3 armv7** com `musl libc`, pacote de ferramentas modernas e ambiente de execução de binários compilados em **Rust** estático (`armv7-unknown-linux-musleabihf`).
4. **Rede & Acesso:**
   - **LAN Local:** Wi-Fi associado à rede `Cratos` com IP estático `192.168.3.55/24`.
   - **Tailnet:** Tailscale daemon nativo com interface `tailscale0` via `/dev/tun` nativo do kernel.
   - **SSH:** Dropbear SSH Server ouvindo na porta 22 com autenticação via chaves Ed25519 (`/root/.ssh/authorized_keys`).

## Acesso e Conectividade

```bash
# Acesso direto na LAN
ssh root@192.168.3.55

# Acesso via Tailscale SSH (quando autenticado na Tailnet)
tailscale ssh root@kururu
```

## Estrutura do Sistema de Arquivos

- **Partição de Boot (`mmcblk0p10`):** `kururu_headless_boot.img` com ramdisk customizada para inicialização direta do hook Linux.
- **Partição Recovery (`mmcblk0p9`):** TWRP 3.6.2-9.0 (`samsung-goyawifi`) mantido intacto para manutenção emergencial.
- **Rootfs Alpine (`/data/alpine`):** Sistema Linux completo com árvore de pacotes apk Alpine v3.20.
- **Daemon de Display & Telemetria:** `kururu-display` (Rust v3.0) renderiza 3 dashboards (Kururu, Homelab/WoL e Relógio Retrô) no framebuffer (`/dev/graphics/fb0`), com **refresh vivo de 1s**, engine de sprites pixel-art (sapo mascote + ícones) e status de bateria/UPS ao vivo. **Sistema de design pixel único** (`src/kit.rs`): topbar, footer, cards, gauges, listas, sapo e teclado são compartilhados por **todas** as telas (dashboards **e** app shell Menu/About/Settings/Terminal) — desenho e hit-test usam os **mesmos retângulos**, com tokens únicos (`MARGIN/GUTTER/PAD=16/16/12`, gutter de 16px também na vertical). O `ratatui` foi **removido** (o shell era um segundo renderizador com escala/altura de header/tokens diferentes, o que causava inconsistência de identidade e sobreposições). **Alvos de toque ≥56px** (teclas 54×56) com **≥8px** de gap, seguindo Material (≥48×48dp) e Apple (≥44pt); teclado com margens laterais simétricas, tecla **Hide** e **feedback de toque** (invertida ~140ms). Formulário de Wi-Fi é tela própria (SSID + senha + revelar/ocultar + indicador conectado) — o teclado **nunca** cobre o campo. Temas monocromáticos derivam **todas** as cores do foreground (títulos/seções trocam junto). **Botões:** **HOME** = OK/ação primária (Settings: reescanear/conectar) · **MENU** = abrir o Menu · **BACK** = voltar/cancelar · **VOL±** = mover · **POWER** = dormir/acordar.
- **Settings:** seção **DISPLAY** (brilho e auto-sleep), **AUDIO** (volume) e **WI-FI**: ao entrar, roda `wpa_cli scan` e **lista as redes disponíveis** (sinal + marcador da conectada); **VOL±** percorre; selecionar uma rede preenche o SSID e abre o teclado para a senha; **Connect** roda `wpa_cli`. **Volume** é best-effort (mapeia 0–100 para o registrador de amp do codec 88pm805 — experimental; não há mixer ALSA padrão). Tudo persistido em `/etc/kururu-display.conf`.
- **Terminal:** tela com emulação **`alacritty_terminal`** (+`vte`) sobre um **PTY** (`portable-pty`) rodando `/bin/sh`. Renderiza o grid no tema atual (fósforo monocromático; INVERSE e cursor tratados). O teclado on-screen envia para o PTY (chars, **Ctrl/Alt/Shift**, setas como sequências CSI, Tab/Esc/Enter/Backspace); **VOL±** rolam o viewport.
- **Temas & efeitos CRT:** **15 temas** — o **`Kururu`** (multicor, **padrão**) + os 14 esquemas do cool-retro-term (Amber, Monochrome Green, Deep Blue, Commodore 64, PET, Apple ][, Atari 400, IBM VGA/3278, Neon Cyan, Ghost, Plasma, Boring, E-Ink). Derivados por `mix()`/`pal()` (fósforo monocromático). Efeitos **scanlines + vignette** (toggle ON/OFF). Header **unificado** em todas as telas (`[acento] TÍTULO`); o **sapo + KURURU** têm bloco de marca em destaque na tela **Menu**. Config em `/etc/kururu-display.conf` (theme/scanlines/vignette/brightness/sleep); env `KURURU_THEME` como override; alternável em runtime pelos itens **Theme**/**Effects** no Menu.
- **Repositório do Projeto:** [github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX](https://github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX)
- **Roadmap & 20 Possibilidades:** [[kururu-possibilidades]] — Catálogo de ideias, expansões de hardware e casos de uso estratégicos.
- **Logs de Inicialização:** `/data/kururu_boot.log` e `/data/tailscaled.log`.

## Boot & Persistência

- **Hook canônico:** `/system/etc/install-recovery.sh` (serviço `flash_recovery` do `init.rc`, partição `/system` ext4 **ro**). A cada boot sobe, na ordem: Wi-Fi (`wpa_supplicant`), Dropbear (22), `kururu-display`, `kururu-wake` (9096) e `tailscaled` + `tailscale up`. Os binários vivem em `/data/alpine/usr/local/bin/` (persistente no `/data` ext4).
- **Reboot remoto:** usar `/sbin/reboot -f`. O `reboot` sem `-f` apenas sinaliza o `init` do Android, que **ignora** — não reinicia.
- **Relógio no boot (sem RTC):** o RTC deste tablet é inoperante (reporta **2014**). O hook seta uma data provisória (`2026-01-01`) e faz um **sync NTP limitado ANTES de subir display/wake** (com retry em background), para que os logs já nasçam com o horário correto. Sem isso, o `kururu-wake` logava com o horário provisório (ex.: `19:30`).
- **Fix 27/09/2026 (WoL no boot):** o hook redirecionava o `kururu-wake` para `/var/log/kururu-wol-daemon.log`, inexistente no contexto do init Android → o daemon era abortado silenciosamente a cada boot (o `kururu-display` não, porque já usava `/data`). Corrigido para `/data/kururu-wol-daemon.log`. Backup do hook pré-fix: `/data/install-recovery.sh.bak-20260927`.
- **Fix PATH do daemon:** o hook inicia o display com o PATH do Android (sem `/bin`, `/usr/bin`, `/usr/local/bin`), fazendo `dmesg`, `ip`, `wpa_cli` e `tailscale` falharem silenciosamente no boot. Corrigido no código — `kururu-display` seta o PATH no startup (v1.6+).
- **Calibração de touch:** `/etc/kururu-touch.conf` — o controlador `sec_touchscreen` reporta em retrato (598×1022) sobre painel landscape (1024×600), então usa `swap_xy=true` e `invert_y=true`. Ajustável sem recompilar.
- **Logs pós-boot:** o hook escreve em `/data/kururu-display.log`, `/data/kururu-wol-daemon.log`, `/data/tailscaled.log` e `/data/kururu_boot.log` (contexto Android, acessíveis via `/proc/1/root/data/` de dentro do chroot).
