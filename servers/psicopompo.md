---
tags: [homelab, server, psicopompo, gaming, docker, storage, power, gpu, nvidia, rebar]
---

# psicopompo

**Papel:** Servidor principal — máquina local física
**Shell padrão:** fish (`/bin/fish`) — zsh e bash também instalados

## Hardware

| Item | Especificação |
|---|---|
| **SO** | CachyOS Linux (Arch-based) |
| **Kernel** | 7.0.11-1-cachyos-bore |
| **CPU** | Intel Xeon E-2246G @ 3.60 GHz — 6C/12T |
| **GPU** | NVIDIA GeForce RTX 5050 |
| **RAM** | 46 GB (ZRAM: 46 GB) |
| **Disco Sistema** | 462 GB NVMe (Kingston NV3) — `/dev/nvme1n1p2` — 49% usado (06/09) |
| **Disco PCIe** | 1.8 TB NVMe (Kingston NV2) — `/mnt/NVME_PCI` — 36% usado, ~1.2TB livres (06/09, após limpeza Docker de ~570GB — ver [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md)). Fusão BTRFS: nvme1n1p5 + nvme1n1p1 de 100GB ex-Windows. Maiores consumidores: SteamLibrary ~550G, containerd-data ~59G, homelab/sumaenimahub ~50G |
| **SSD SATA** | 448 GB (Kingston A400) — `/mnt/SSD_SATA` — 10% usado |
| **SSD SATA — Scryfall Mirror** | `/mnt/SSD_SATA/scryfall-mirror` — cache de imagens/bulk do Arandu, exportado via NFS para o kavure (`/srv/data/scryfall-mirror`). Sync diário 03:00 roda no kavure (`hl-scryfall-mirror.timer`). Ver [`services/scryfall-mirror.md`](../services/scryfall-mirror.md) |
| **HDD SATA** | 932 GB (Seagate 1TB) — `/mnt/HDD_SATA` — Montado permanentemente (BTRFS) |
| **HDD SATA (Backup)** | 932 GB (1TB) — `/mnt/BACKUP` — Montado permanentemente (BTRFS) |
| **MicroSD** | 116 GB — `/dev/sdd1` — exFAT — MICROSDXC |
| **Swap** | 46 GB (ZRAM) + 48 GB swapfile `/swap` (hibernação) |
| **Tailscale IP** | 100.82.51.112 |
| **Tailscale DNS** | psicopompo.chimaera-heptatonic.ts.net |
| **Rede** | Intel I219-LM Gigabit Ethernet |

## GPU / NVIDIA — ReBAR e DDC/CI (25/08/2026)

> **GPU:** NVIDIA GeForce RTX 5050 (driver proprietário 610.x). A **BIOS da Dell do psicopompo não permite ativar ReBAR**, mas com Linux isso se torna possível via parâmetro de kernel.

### ReBAR (Resizable BAR) — como está garantido
- **Ativado via cmdline do kernel**, não pela BIOS: `nvidia.NVreg_EnableResizableBar=1` em `/etc/default/limine` → `KERNEL_CMDLINE[default]` (fonte canônica que regenera o `limine.conf` em todas as entradas — kernel atual, alternativos e snapshots).
- **Verificação em runtime:**
  - `grep EnableResizableBar /proc/driver/nvidia/params` → deve mostrar `1`
  - `lspci -vvv -s 01:00.0` → `Region 1: Memory at ... [size=8G]` (64-bit prefetchable = ReBAR ativo; sem ReBAR o BAR seria menor)
- **Cuidado:** ao restaurar snapshot, conferir que o cmdline da entrada ainda carrega o `EnableResizableBar=1`.

### DDC/CI — controle de brilho de monitor externo
- Fix NVIDIA documentado aplicado via `nvidia.NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100` (mesmo arquivo `/etc/default/limine`). Força I2C por software — requisito para DDC/CI no driver proprietário NVIDIA.
- **Monitor Samsung C24F390 (HDMI):** a comunicação DDC/CI segue **intermitente** mesmo com o fix (leitura VCP funciona ~25% das vezes) — limitação do monitor/HDMI+GPU, **não** do fix. O fix é genérico e beneficia qualquer monitor futuro com DDC.
- Backups criados: `/etc/default/limine.bak-ddc-20260825-032720`, `/boot/limine.conf.bak-ddc-20260825-032934`.

## Áudio — GB207 HDMI desabilitado (01/09/2026)

O driver NVIDIA cria múltiplos sinks HDMI duplicados (6× `alsa_output.pci-0000_01_00.1.hdmi-stereo`, todos apontando para o mesmo monitor Samsung C24F390). Não é bug do Punktfunk — é comportamento do driver NVIDIA + PipeWire.

**Fix:** regra WirePlumber que desabilita a placa de áudio GB207 inteira:
- Arquivo: `~/.config/wireplumber/wireplumber.conf.d/51-disable-gb207.conf`
- Regra: `device.disabled = true` para `alsa_card.pci-0000_01_00.1`
- Efeito: remove os 6 sinks HDMI; restam apenas `Built-in Audio` + dispositivos virtuais do Punktfunk
- Áudio do monitor HDMI deixa de existir (áudio usa JBL Tune 770NC via Bluetooth; streaming usa `punktfunk-speaker-*` virtual)
- Reverter: remover o arquivo e `systemctl --user restart wireplumber`

## Papéis

- **NAS da Tailnet** (07/08): exporta via NFSv4 `/mnt/BACKUP/media/music` e `/media/books` (biblioteca canônica) + `/mnt/BACKUP/sumaenima-server-kavure` (backup do core) para kuaray/kavure — ver [`network/nfs.md`](../network/nfs.md)
- Workstation de desenvolvimento, IA e gaming (Steam/Wayland/Hyprland; servidores dedicados de jogos Zomboid, Minecraft e Valheim migrados p/ kavure)
- **GPU workers do Sumænimá** (StênioREC / vision / audio / ollama) + build-node (07/08/2026 — o core `sae-core` migrou para o kavure)
- Sincronização (Syncthing) e Rclone (CLI ativo — off-site Drive + mount; GUI removida 26/08)

## Hibernação (21/08/2026)

> **Estado:** ativa e testada (desligamento S4 + resume completo). A opção "Hibernar" aparece no KDE Plasma (PowerDevil) porque `logind` responde `CanHibernate=yes`.

Configuração "swap file for hibernation with zram" (padrão ArchWiki): o **zram (pri 100)** continua como swap ativo para uso normal; o **swapfile em disco (pri 1)** fica ocioso e é usado apenas como destino da imagem de hibernação (`logind` ignora zram na hora de hibernar).

| Item | Valor |
|---|---|
| Subvolume `/swap` | btrfs, **irmão de `/@`** (top-level id=5) → fora dos snapshots snapper |
| Swapfile | `/swap/swapfile` — 48 GB, NOCOW, `btrfs filesystem mkswapfile --size 48g --uuid clear` |
| `resume=` | `UUID=ffc60b3e-2f31-47bb-b51e-4eb785af8647` (btrfs root) |
| `resume_offset=` | `17188552` (`btrfs inspect-internal map-swapfile -r /swap/swapfile`) |
| Cmdline fonte | `/etc/default/limine` → `KERNEL_CMDLINE[default]+=... resume=... resume_offset=...` |
| Initramfs | systemd-based (`base systemd ...`) → resume nativo, sem hook extra |
| fstab | `UUID=ffc60b3e... /swap btrfs subvol=/swap,noatime 0 0` + `/swap/swapfile none swap defaults,pri=1 0 0` |

**Manutenção / cuidados:**
- **Após restaurar snapshot:** o `resume_offset` pode mudar se o swapfile for recriado → rodar `limine-update` (recalcula e regenera cmdline/initramfs).
- **Backups:** `/swap` (48 GB) fica fora dos snapshots snapper do `/@` e deve ser **excluído** das rotinas de backup que varrem `/` (senão infla os backups).
- **Segurança:** root sem LUKS → a imagem de hibernação fica **sem criptografia** no disco (aceito — homelab local).
- **Wake imediato:** teclado/mouse continuarem ligados durante S4 é normal (USB powered da Dell). Para hibernar de fato, aguardar os LEDs do gabinete apagarem antes de religar.
- Backups de config criados na implementação: `/etc/fstab.bak-hibernacao`, `/etc/default/limine.bak-hibernacao`.

## Suspend / Sleep (22/09/2026)

> **Estado:** ✅ funcionando — **2 testes completos**: (1) runtime `mem_sleep=s2idle` → resume OK; (2) **caminho permanente do drop-in** → journal prova `PM: suspend entry (s2idle)` + `nvidia-resume` OK + mesma sessão continuou (21:49). Pronto para qualquer reboot.

**Sintoma original (madrugada 22/09):** suspend via menu Noctalia → tela apagou, máquina "desligou sozinha" e depois **cold boot** — o resume **nunca executou** (0 logs de `Waking up from S3`; `nvidia-resume.service` nunca rodou).

**Causa raiz (case documentado):** a firmware anuncia **deep (S3)** mas não acorda → ArchWiki *Power management* §Changing suspend method: *"faulty firmware advertises support for deep sleep, while only `s2idle` is supported"*.

**Diagnóstico que foi descartado (verificado antes de concluir):**
- Preservação de VRAM NVIDIA **correta** (`UseKernelSuspendNotifiers: 1` + `TemporaryFilePath: /var/tmp` — verificação oficial ArchWiki §Preserve video memory; driver 615.71.09 usa o mecanismo 595+)
- Wake sources OK (`XHC` USB enabled) · inhibitors normais (4× delay) · `MODULES=()` (sem early KMS → ressalva de hibernação da doc não aplica)
- Erro AER RxErr (correctable) recorrente no port `0000:00:01.0` (**PEG0 = GPU**) — **monitorar** se causar problemas futuros

**Fix aplicado (ArchWiki §Changing suspend method):**
1. Teste runtime (provou): `echo s2idle | sudo tee /sys/power/mem_sleep` → suspend OK
2. **Persistente:** `/etc/systemd/sleep.conf.d/60-freeze.conf`:
   ```ini
   [Sleep]
   SuspendState=freeze   # systemd-suspend.service escreve "freeze" em /sys/power/state
   ```

**Hibernação NÃO afetada (separação por design):** `SuspendState=` (suspend → `/sys/power/state`) e `HibernateMode=` (hibernação → `/sys/power/disk`) são opções independentes de serviços distintos — `systemd-sleep.conf(5)`. Config de hibernação (21/08) intocada.

**Cuidados:** evitar suspender com CPU quente (aviso `intel_pch_thermal: S0ix might fail` ≥66C no journal); AER RxErr na GPU para observar.

## Política de idle do desktop Hyprland/Noctalia (24/09/2026)

O desktop usa o **Idle Behavior nativo do Noctalia**, sem `hypridle` ou `swayidle` adicionais. A política persistida em `~/.local/state/noctalia/settings.toml` é:

- **screen off:** `timeout = 0` desbloqueado; `locked_timeout = 60 s` (1 min após o lock);
- **lock:** `900 s` (15 min de idle);
- **lock + suspend:** desativado (`timeout = 0`, `enabled = false`);
- **fade pré-ação:** `2 s`;
- **lock antes de suspensão manual:** habilitado (`lock_before_suspend = true`).

Quando a sessão entra no estado bloqueado, o Noctalia rearma o timer `screen-off` com `60 s`; ao desbloquear, o monitor é religado e o comportamento fica desativado novamente (`timeout = 0`). A ordem é `lock` → `screen-off`, para que a tela não seja apagada antes de a sessão travar. O `systemd-logind` continua com `IdleAction=ignore`; logo, o PC não suspende automaticamente por inatividade. A ação `lock_and_suspend` do menu de sessão e `SUPER+H` permanecem manuais.

Durante reprodução de mídia, players que enviam idle inhibitors suspendem os dois timers. O log do Noctalia deve ser consultado em `~/.cache/noctalia/noctalia.log`; Firefox pode não sinalizar de forma consistente. O guia operacional completo está em [[hyprland-noctalia-guide]].

O `settings.toml` é um override de Settings, tem prioridade sobre TOML declarativos e é incluído no espelho `config-backup`. O `merged-config.toml` é gerado diariamente e não deve ser editado.

## See also
- [[psicopompo-gaming]] — Guia de jogos Steam no Linux
- [[zomboid-psicopompo-handoff]] — Desligamento do servidor PZ local (migrado p/ kavure)
- [[plasma-kirigami-applet-bug]] — Workaround do bug dos applets de rede/volume (reset do `appletsrc`, 25/08/2026)

## Tailscale Funnels

Nenhum atualmente (tráfego Sumænimá é roteado via Nginx proxies em ybyra e kuaray).

## Docker Swarm — papel GPU (07/08/2026)

> **Estado (07/08/2026):** o psicopompo virou **worker do Swarm com `role=gpu`** — o core (`sae-core`) migrou para o **kavure** (manager). Aqui ficam apenas os **GPU workers** (vision/audio/ollama) via `gpu.yml` standalone, conectados à overlay `sumaenima_sumaenima-net` do Swarm do kavure. O psicopompo também é o **build-node** (ADR-026: única máquina que builda imagens Docker).

| Container | Imagem | Portas | Função |
|---|---|---|---|
| steniobot_vision | sumaenimahub-steniobot-vision:latest | — | Visão (OCR + SAM 2) — GPU |
| steniobot_audio | sumaenimahub-steniobot-audio:latest | — | Áudio (Whisper) — GPU |
| steniobot_ollama | ollama/ollama:latest | `0.0.0.0:11434` | LLM (qwen3.6) |
| portainer | portainer/portainer-ce:latest | `0.0.0.0:9000` | Gerenciamento Docker |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoramento |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `0.0.0.0:2375` | Proxy socket Docker (homepage) |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers (24h) |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart de containers |

> **Removidos:** RustDesk hbbs/hbbr (não existem mais), WinBoat (desligado), **crafty-controller + Minecraft** (migrado p/ kavure em 08/08/2026 — Fase F).
> **Migrado p/ kavure (07/08):** stack `sae-core` (Sumænimá/StênioBOT) — db, valkey, api, umami-db, backup, asciline.
> **GPU workers:** sobem sob demanda via `sumaenima-ctl start` (auto-exit por idle 180s p/ liberar VRAM).
> **Syncthing: ATIVO** (22/09 — user unit `syncthing.service` canônica; ver `services/syncthing.md` p/ fix das unidades duplicadas). **Rclone:** CLI ativo (backup off-site + mount); **GUI removida 26/08** (nunca usada, RC daemon sem auth — ver `services/rclone.md`).
> **Build node (06/09):** builder padronizado no **`default`** (docker driver) — `default-builder` (container BuildKit) e builder remoto morto `kavure` removidos; GC do BuildKit configurado no `daemon.json` (`defaultKeepStorage=30GB`); timer mensal `docker-prune.timer` (dia 01, 04:00). Snapper padronizado (reconstruível → sem snapshot): config `hdd` removida, `ssd` sem config; `nvme`/`backup` mantêm timeline. Limpeza recuperou ~570GB (`btrfs` Used 1.22TiB→652GB; `containerd-data` ~396G→~59G, `docker-data` ~99G→~1.8G). Ver [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md) e [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md).

## Programas Nativos

| Programa | Função |
|---|---|
| syncthing | Sincronização de arquivos (vault Obsidian) — **ativo** (user unit canônica `syncthing.service`; config `~/.local/state/syncthing/config.xml`) |
| greetd + noctalia-greeter | Display manager (login gráfico) — **22/09**: substituiu plasmalogin; `display-manager` → greetd; sessões: Hyprland/UWSM + Plasma. Config: `/var/lib/noctalia-greeter/greeter.toml` (72Hz, cursor McMojave system-wide, Sync passwordless p/ edu) |
| rclone | CLI + remotes (off-site Drive, mount) — **ativo**; GUI web removida 26/08 (nunca usada) |
| systemd timers `hl-*` | Agendamento dos backups (05:00–06:30, `Persistent=true` — catch-up pós-reboot) — **10/08** |
| cronie | Cron mantido instalado p/ uso futuro (sem jobs próprios) |
| tailscaled | Agente Tailscale |
| steam | Gaming |

## Portas Importantes

| Porta | Serviço | Bind |
|---|---|---|
| 11434 | Ollama (GPU worker) | `0.0.0.0` |
| 9090 | StênioREC (Whisper daemon local GPU) | `127.0.0.1` / Tailscale |
| 61208 | Glances | `0.0.0.0` |
| 2375 | Docker proxy (homepage) | `0.0.0.0` |
| 27036 | Steam | `0.0.0.0` |
| 5355 | systemd-resolved | `0.0.0.0` |

> **Portas de serviços migrados p/ kavure (não escutam mais aqui):** 9090 (sae-core_api Swarm), 9092 (backup sentinel), 8443/8444 (Crafty Controller Minecraft), 25565 (Minecraft server), 16261 (Project Zomboid). **A reativar:** 8384 (syncthing). **Portainer e rclone GUI removidos.**

## SMART — discos externos (fix 22/09/2026)

`smartd.service` falhava no boot (exit 16) quando o disco externo **SSHD-1TB** estava desconectado: `Unable to register device (no Directive -d removable)`. Fix no `/etc/smartd.conf` (backup `.bak-removable`): linhas do **SSHD-1TB** e **EXPANSION-2TB** (ambos externos) com **`-d removable`** → smartd **ignora se ausente** em vez de sair (ArchWiki S.M.A.R.T. § `-d removable`; man smartd.conf: *"continue instead of exiting if the device does not appear to be present"*). Forma `-d sat,removable` NÃO é aceita pelo smartd 7.5 local (parser rejeita vírgula) — usado `-d removable` puro (autodetect cuida do tipo; validado: EXPANSION aberto, SSHD ausente ignorado, 3 devices monitorados).
