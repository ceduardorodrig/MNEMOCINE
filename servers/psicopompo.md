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
| **Swap** | 46.9 GB (ZRAM zstd puro, prioridade 100) — sem swap lento em disco |
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
- Workstation de desenvolvimento, IA e gaming (Steam/Wayland/Hyprland com layout nativo scrolling estilo Niri canonizado em 27/09/2026; servidores dedicados de jogos Zomboid, Minecraft e Valheim migrados p/ kavure)
- **GPU workers do Sumænimá** (StênioREC / vision / audio / ollama) + build-node (07/08/2026 — o core `sae-core` migrou para o kavure)
- Sincronização (Syncthing) e Rclone (CLI ativo — off-site Drive + mount; GUI removida 26/08)

## Gerenciamento de Energia e Performance Máxima (03/10/2026)

> **Decisão e Arquitetura Canônica:** 
> - **Performance Máxima PCIe:** Barramento travado em velocidade máxima permanente (`pcie_aspm=off pci=noaer`), eliminando *exit latency* em jogos e tarefas de IA/CUDA, com **Resizable BAR (ReBAR) 100% ativo** (8.192 MiB).
> - **Aposentadoria de Suspend e Hibernate:** Devido a restrições físicas de hardware do Dell Precision 3630 (PCH C246 a 66°C–67°C sob a GPU, bug de ACPI S3/S4 da Dell e watchdog de hardware), os estados S3/S0ix e S4 foram desativados formalmente no systemd (`AllowSuspend=no`, `AllowHibernation=no`). O sistema opera com boot ultrarrápido pelo NVMe (~8s) e desligamento limpo (Shutdown S5) infalível.
> - **Remoção de Swap em Disco (+48 GB Livres):** O subvolume Btrfs `/swap` e o arquivo `/swap/swapfile` de 48 GB foram removidos. O sistema opera exclusivamente com os 46.9 GB de ZRAM comprimido em RAM (zstd, prioridade 100).

### Sumário de Configuração Permanente
| Item | Valor |
|---|---|
| Memória & Swap | 48 GB RAM ECC + 46.9 GB ZRAM (zstd, pri 100) — sem swap em disco |
| Cmdline Limine | `quiet nowatchdog splash rw rootflags=subvol=/@ root=UUID=... nvidia-drm.modeset=1 nvidia.NVreg_EnableResizableBar=1 nvidia.NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100 pcie_aspm=off pci=noaer` |
| Systemd Drop-in | `/etc/systemd/sleep.conf.d/60-freeze.conf` (`AllowSuspend=no`, `AllowHibernation=no`) |
| Wakeup Filter | `/etc/systemd/system/disable-acpi-spurious-wakeup.service` (desativa ruídos ACPI, mantém `GLAN` e trava ASPM disabled via `setpci`) |
| Interface Noctalia | `~/.config/noctalia/config.toml`: `1: Lock`, `2: Logout`, `3: Reboot`, `4: Shutdown` |

## Wake-on-LAN (02/10/2026)

> **✅ Validado:** o psicopompo **acorda via rede em 54s** (S5 → magic packet emitido
> pelo kavure; ninguém tocou no power). É ele quem **acorda o kavure** (par a par) e é
> um dos 3 emissores — ver [`services/wol-relay.md`](../services/wol-relay.md).
>
> - **Persistência (F1):** NM `802-3-ethernet.wake-on-lan magic` + `wol@eno1` (enabled)
>   — o `ethtool -s wol g` puro é runtime-only; após o boot das 21:07 o `Wake-on: g`
>   **sobreviveu sozinho**.
> - **Pré-condições confirmadas:** NIC `Supports Wake-on: pumbg` · ACPI `GLAN *enabled`
>   · BIOS com `Wake on LAN` + `AC Recovery`.
> - **Relay local:** `wol-relay` em `127.0.0.1:9096` (target `kavure`), exposto na
>   tailnet via `tailscale serve` (`100.82.51.112:9096`).

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
- [[hyprland-noctalia-guide#Workspace inicial da sessão (fix 29/09/2026)]] — workspace que abre no login (só a 1 tem `default = true`)
- [[zomboid-psicopompo-handoff]] — Desligamento do servidor PZ local (migrado p/ kavure)
- [[plasma-kirigami-applet-bug]] — Workaround do bug dos applets de rede/volume (reset do `appletsrc`, 25/08/2026)

## Tailscale Funnels

Nenhum atualmente (tráfego Sumænimá é roteado via Nginx proxies em ybyra e kuaray).

## Docker Swarm — papel GPU (07/08/2026)

> **Estado (07/08/2026):** o psicopompo virou **worker do Swarm com `role=gpu`** — o core (`sae-core`) migrou para o **kavure** (manager). Aqui ficam apenas os **GPU workers** (vision/audio/ollama) via `gpu.yml` standalone, conectados à overlay `sae-net` do Swarm do kavure. O psicopompo também é o **build-node** (ADR-026: única máquina que builda imagens Docker).

| Container | Imagem | Portas | Função |
|---|---|---|---|
| steniorec | **sumaenima-server:cuda** | `127.0.0.1:9090` / `100.82.51.112:9090` | Whisper daemon (Rust + CUDA) — ver [`services/steniorec.md`](../services/steniorec.md) |
| **registry** | `registry:3` | `100.82.51.112:5000` + `127.0.0.1:5000` | **Registry privado** das imagens do Swarm (TLS + htpasswd) — ver [`guides/docker-registry.md`](../guides/docker-registry.md) |
| promtail | grafana/promtail | — | Coleta de logs → Loki (kavure) |
| node-exporter | prom/node-exporter | — | Métricas do host → Prometheus |
| steniobot_vision | sumaenimahub-steniobot-vision:latest | — | Visão (OCR + SAM 2) — GPU |
| steniobot_audio | sumaenimahub-steniobot-audio:latest | — | Áudio (Whisper) — GPU |
| steniobot_ollama | ollama/ollama:latest | `0.0.0.0:11434` | LLM (qwen3.6) |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoramento |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `0.0.0.0:2375` | Proxy socket Docker (homepage) |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers (24h) |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart de containers |

> **Removidos:** RustDesk hbbs/hbbr (não existem mais), WinBoat (desligado), **crafty-controller + Minecraft** (migrado p/ kavure em 08/08/2026 — Fase F), **portainer** (removido — não aparece em `docker ps -a` desde 29/09/2026).
> **Migrado p/ kavure (07/08):** stack `sae-core` (Sumænimá/StênioBOT) — db, valkey, api, umami-db, backup, asciline.
> **GPU workers:** sobem sob demanda via `sumaenima-ctl start` (auto-exit por idle 180s p/ liberar VRAM).
>
> **StênioREC — boot resiliente (fix 29/09/2026):** o worker de transcrição é hoje
> supervisionado por um binário **Rust** (`gpu-supervisor`, fonte em
> `app/gpu-supervisor/` do hub), rodando na unit `sumaenima-gpu.service` com
> `Type=simple` + `Restart=always` — o `Type=oneshot` anterior **não aceitava
> `Restart=`** no systemd e dependia de um timer bash de 5 min (polling). O supervisor
> espera `tailscale BackendState=Running` + sessão do Swarm pronta, sobe via
> `docker compose up -d` e depois reage a **eventos do Docker** (`die`/`kill`/`oom`)
> em milissegundos. Recuperação medida de um `docker kill`: **~10 s** (antes: até 5 min).
> Ordem de boot: `tailscaled-wait.service` → `docker.service` → `sumaenima-gpu.service`.
> Container com `restart: unless-stopped`.
> **Tag contratual:** este nó usa `sumaenima-server:cuda` (o kavure usa `:cpu`) —
> nunca `:latest`. Ver [`services/steniorec.md`](../services/steniorec.md) §2, §5 e §6.
> **Syncthing: ATIVO** (22/09 — user unit `syncthing.service` canônica; ver `services/syncthing.md` p/ fix das unidades duplicadas). **Rclone:** CLI ativo (backup off-site + mount); **GUI removida 26/08** (nunca usada, RC daemon sem auth — ver `services/rclone.md`).
> **Build node (06/09):** builder padronizado no **`default`** (docker driver) — `default-builder` (container BuildKit) e builder remoto morto `kavure` removidos; GC do BuildKit configurado no `daemon.json` (`defaultKeepStorage=30GB`); timer mensal `docker-prune.timer` (dia 01, 04:00). Snapper padronizado (reconstruível → sem snapshot): config `hdd` removida, `ssd` sem config; `nvme`/`backup` mantêm timeline. Limpeza recuperou ~570GB (`btrfs` Used 1.22TiB→652GB; `containerd-data` ~396G→~59G, `docker-data` ~99G→~1.8G). Ver [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md) e [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md).

### `live-restore` — ✗ REVERTIDO (adicionado 29/09/2026 · removido 02/10/2026)

> ⚠️ **Estado atual: `"live-restore": true` NÃO existe mais** neste host. Backup em
> `/etc/docker/daemon.json.bak-20261002`. A opção é **incompatível com o Swarm** —
> ver [`AGENTS.md`](../AGENTS.md) §`live-restore` PROIBIDO em host Swarm.

**O que se tentou resolver (29/09/2026):** durante um `pacman -Syu` o hook disparou
`systemctl restart docker.service` duas vezes; o `dockerd` estourou o timeout de parada
e levou **SIGKILL** (o CachyOS define `DefaultTimeoutStopSec=10s` **global** em
`/usr/lib/systemd/system.conf.d/00-timeout.conf`) → o container **registry** morreu e
**não voltou** (`Exited (2)`), apesar de `restart: unless-stopped`. A solução adotada na
época foi o `live-restore`, que mantém standalone vivos durante o restart do daemon.

**Por que foi um tiro no pé:** o psicopompo é **nó worker do Swarm**. Com
`live-restore` + Swarm, o Docker **recusa a subir**:

```
failed to start cluster component: --live-restore daemon configuration
is incompatible with swarm mode
```

Como o daemon só lê o `daemon.json` no **start**, o erro ficou latente — e detonou no
reboot de **30/09 00:58**, deixando o psicopompo **2 dias sem daemon** (containers
sobreviveram como órfãos pelo próprio `live-restore`, mascarando o problema) e o Swarm
**sem worker**. O mesmo detonou no kavure (manager) em **02/10 13:08**.

**Recuperação aplicada (02/10/2026):**
1. `cp daemon.json daemon.json.bak-20261002` → remover só `"live-restore": true`
   (mantidos `data-root`, `runtimes.nvidia`, `builder.gc`, `log-driver`/`log-opts`);
2. `systemctl reset-failed docker && systemctl start docker` → daemon **active**,
   8/8 containers, Swarm worker `Ready`;
3. `registry` religado (falhou `Exit(2)` na largada; `docker start registry` → `:5000` OK).

**Problema original permanece em aberto (pendência):** sem `live-restore`, um SIGKILL do
`dockerd` durante upgrade volta a derrubar os standalone. A correção canônica não é
`live-restore`, e sim **aumentar o timeout de parada** do daemon — drop-in com
`TimeoutStopSec=60s` (mesmo padrão já usado no kavure via `nfs-ordering.conf`).
Detalhes em [`guides/docker-registry.md`](../guides/docker-registry.md) §Resiliência.

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
| 5000 | Registry privado de imagens (`registry:3`, TLS + htpasswd) | `100.82.51.112` + `127.0.0.1` |
| 61208 | Glances | `0.0.0.0` |
| 2375 | Docker proxy (homepage) | `0.0.0.0` |
| 27036 | Steam | `0.0.0.0` |
| 5355 | systemd-resolved | `0.0.0.0` |

> **Portas de serviços migrados p/ kavure (não escutam mais aqui):** 9090 (sae-core_api Swarm), 9092 (backup sentinel), 8443/8444 (Crafty Controller Minecraft), 25565 (Minecraft server), 16261 (Project Zomboid). **A reativar:** 8384 (syncthing). **Portainer e rclone GUI removidos.**

## SMART — discos externos (fix 22/09/2026)

`smartd.service` falhava no boot (exit 16) quando o disco externo **SSHD-1TB** estava desconectado: `Unable to register device (no Directive -d removable)`. Fix no `/etc/smartd.conf` (backup `.bak-removable`): linhas do **SSHD-1TB** e **EXPANSION-2TB** (ambos externos) com **`-d removable`** → smartd **ignora se ausente** em vez de sair (ArchWiki S.M.A.R.T. § `-d removable`; man smartd.conf: *"continue instead of exiting if the device does not appear to be present"*). Forma `-d sat,removable` NÃO é aceita pelo smartd 7.5 local (parser rejeita vírgula) — usado `-d removable` puro (autodetect cuida do tipo; validado: EXPANSION aberto, SSHD ausente ignorado, 3 devices monitorados).
