---
tags: [homelab, server, kuaray, docker, storage, media, home-assistant, automation]
---

# kuaray

> ## 🚀 REATIVADO (04/10/2026)
> Nó **reintegrado à topologia ativa** com conexão Ethernet cabeada (`enp7s0`, 100 Mb/s, 0,28 ms de latência).
> Assume o papel de hospedeiro da **Stack Miracena** (desafogando a RAM do Kavure) e da **Stack Multimídia** (*arr, torrent, Soulseek), com biblioteca montada via NFS do NAS Psicopompo e backups estruturados offbox e de configs.

**Papel:** Servidor da Stack Miracena (Directus, WordPress, Nuxt, n8n, DBs) + Multimídia (*arr stack, streaming, downloads)
**Shell padrão:** bash (`/bin/bash`)
**Swarm role:** `standby` — nó worker do Docker Swarm (stack `sae-edge`, serviços standby com réplicas 0)

> **Config-as-code (04/10/2026):** todos os containers do kuaray têm `compose.yml` em
> `/srv/data/miracena/` (Miracena: postgres, mariadb, redis, directus, wordpress, nuxt, n8n, npm, tunnel) e
> `/home/kuaray/homelab/{serviço}/` (mídia e infra: lidarr, prowlarr, transmission, slskd, soularr, flaresolverr,
> vert, syncthing, glances, dockerproxy, autoheal) — espelhados no NAS via `config-backup` e `miracena-backup`.
> Segredos ficam em `.env` (fora do espelho) / store sops.
> **WoL no Kururu (04/10/2026):** Mapeado no `kururu-wake` e com botão touch no `kururu-display` (`MAC a4:1f:72:fb:9a:36`).
> **Fix ASPM e Rede (04/10/2026):** `pcie_aspm=off` no GRUB e Power Drain destravaram o transceptor Realtek RTL810xE (`enp7s0`). Link estável em 100 Mb/s Full Duplex (`192.168.3.200`).

## Hardware

| Item | Especificação |
|---|---|
| **SO** | Linux Mint 22.3 (Zena) |
| **Kernel** | 7.0.0-38-generic |
| **CPU** | Intel Core i5-4200U @ 1.60 GHz (max 2.60 GHz) — 2C/4T |
| **GPU** | Intel HD Graphics (Haswell) + NVIDIA GeForce GT 740M |
| **RAM** | 5.7 GB (3.4 GB em uso) |
| **Swap** | 5.4 GB (swap on disk) + 3.4 GB ZRAM |
| **Disco Sistema** | 224 GB SSD (Kingston A400) — `/dev/sda2` — 23% usado |
| **Disco Storage** | 932 GB HDD (Seagate 1TB) — `/dev/sdb1` (MBR, início em LBA 2048) — **reformatado 06/08/2026** (bad sectors LBA 8/32/34-39 evitados pela partição). **Degradado 28/08:** pending sectors 3→37, erro de leitura ~464 GB, fs com erros (reparado `e2fsck -fy`); montado com `nofail,errors=continue` |
| **Tailscale IP** | 100.94.209.99 |
| **Tailscale DNS** | kuaray.chimaera-heptatonic.ts.net |
| **Rede** | Ethernet Realtek RTL810xE (`enp7s0`: 192.168.3.200/24 · 100 Mb/s Full Duplex — **ativado 04/10/2026**) + Wi-Fi Qualcomm Atheros QCA9565 (`wlp6s0`: 192.168.3.53/24 metric 600) |
| **Usuário** | kuaray |
| **Acesso** | `tailscale ssh kuaray@kuaray` (usuário `kuaray`, sudo NOPASSWD — `/etc/sudoers.d/kuaray-nopasswd`, 10/09/2026) |

## Papéis

- Servidor multimídia (música, livros, torrent, streaming) — **biblioteca lida via NFS do psicopompo desde 07/08** (`/mnt/storage/data/media/music` = mount NFS; ver [`network/nfs.md`](../network/nfs.md))
- Espelho frio de backup: `/mnt/storage/backup` (folder `backup` do Syncthing, receiveonly) — ver [`services/syncthing.md`](../services/syncthing.md)
- Automação residencial (~~Home Assistant~~ migrado p/ kavure 09/08; ~~MQTT~~ removido 16/08)
- ~~DNS secundário (Pi-hole)~~ — **migrado para o kavure (09/08/2026)**; ver [`network/dns.md`](../network/dns.md)
- Gamificação (Kavita manga/ebook) — **removido 10/08** (não era mais usado)
- Monitoramento (Glances)

## Tailscale Funnels

| URL | Proxy para | Serviço |
|---|---|---|
| `https://miracena.chimaera-heptatonic.ts.net` | `miracena-nginx-proxy-manager:80` | Stack Miracena (WordPress / Landing / Directus) |

## Containers Docker

> **Estado (04/10/2026):** **21 containers ativos** divididos entre a **Stack Miracena** (`/srv/data/miracena/`) e a **Stack Mídia/Infra** (`/home/kuaray/homelab/`).

### Stack Miracena (`/srv/data/miracena/`)

| Container | Imagem | Portas | Função |
|---|---|---|---|
| miracena-postgres | postgres:16-alpine | `5432` (interno) | Banco PostgreSQL (Directus + n8n) |
| miracena-mariadb | mariadb:11 | `3306` (interno) | Banco MariaDB (WordPress) |
| miracena-redis | redis:7-alpine | `6379` (interno) | Cache Redis para Directus |
| miracena-directus | directus/directus:latest | `100.94.209.99:8055` | Backend Headless CMS Directus |
| miracena-wordpress | wordpress:latest | `100.94.209.99:8085` | CMS WordPress Miracena |
| miracena-nuxt | node:22-alpine | `100.94.209.99:3003` | Frontend Nuxt 3 Miracena |
| miracena-n8n | docker.n8n.io/n8nio/n8n:stable | `100.94.209.99:5678` | Automação e Workflows n8n |
| miracena-nginx-proxy-manager | jc21/nginx-proxy-manager:latest | `100.94.209.99:81, 8180, 8445` | Reverse Proxy / Admin NPM |
| miracena-tunnel | tailscale/tailscale:latest | Funnel HTTPS 443 | Ingress Tailscale Funnel oficial |

### Stack Mídia e Homelab (`/home/kuaray/homelab/`)

| Container | Imagem | Portas | Função |
|---|---|---|---|
| lidarr | lscr.io/linuxserver/lidarr:latest | `0.0.0.0:8686` | Gerenciamento de música (*arr) |
| prowlarr | lscr.io/linuxserver/prowlarr:latest | `0.0.0.0:9696` | Indexer de torrent/usenet |
| transmission | lscr.io/linuxserver/transmission:latest | `0.0.0.0:9091`, `51413` | Cliente BitTorrent |
| slskd | slskd/slskd:latest | `0.0.0.0:5030` | Cliente Soulseek P2P |
| soularr | mrusse08/soularr:latest | `0.0.0.0:8265` | Automação Soulseek ⇄ Lidarr |
| flaresolverr | ghcr.io/flaresolverr/flaresolverr:latest | `0.0.0.0:8191` | Proxy Cloudflare Solver |
| vert | ghcr.io/vert-sh/vert | `0.0.0.0:3030` | Web UI Vert |
| syncthing | linuxserver/syncthing:1.29.7 | `0.0.0.0:8384` | Sincronização Syncthing |
| glances | nicolargo/glances:latest | — | Telemetria Glances |
| dockerproxy | tecnativa/docker-socket-proxy:latest | — | Proxy de socket Docker seguro |
| watchtower | containrrr/watchtower:latest | `8080` (interno) | Atualização de containers |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart de containers não saudáveis |

## Programas Nativos

| Programa | Função |
|---|---|
| tailscaled | Agente Tailscale |
| Samba (nmbd/smbd) | Compartilhamento SMB |
| ~~nginx~~ | **Desativado (04/10/2026)** — liberou a porta 8085 para o WordPress da Miracena |

## Portas Importantes

| Porta | Serviço | Bind |
|---|---|---|
| 3003 | Nuxt 3 Miracena | `100.94.209.99` |
| 3030 | Vert | `0.0.0.0` |
| 5030 | Slskd (Soulseek) | `0.0.0.0` |
| 5678 | n8n Miracena | `100.94.209.99` |
| 8055 | Directus Miracena | `100.94.209.99` |
| 8085 | WordPress Miracena | `100.94.209.99` |
| 81 | NPM Admin Miracena | `100.94.209.99` |
| 8180 | NPM HTTP Miracena | `100.94.209.99` |
| 8191 | Flaresolverr | `0.0.0.0` |
| 8265 | Soularr | `0.0.0.0` |
| 8384 | Syncthing Web UI | `0.0.0.0` |
| 8445 | NPM HTTPS Miracena | `100.94.209.99` |
| 8686 | Lidarr | `0.0.0.0` |
| 9091 | Transmission Web UI | `0.0.0.0` |
| 9696 | Prowlarr | `0.0.0.0` |
| 51413 | Transmission BitTorrent | `0.0.0.0` (TCP/UDP) |

## Observações

### Disco Storage (`/dev/sdb`) — bad sectors no início

> **Situação desde 31/jul/2026:** o disco tem **erros físicos de leitura** (medium error, auto reallocate failed) nos setores **LBA 8, 32 e 34-39** — exatamente onde ficam o header GPT primário e o superblock ext4 primário. SMART segue **PASSED** (0 setores realocados, 3 pending). O **backup GPT** (fim do disco) e o **superblock alternativo** (bloco 32768) estão íntegros.

**Consequências:**
- `/dev/sdb1` não aparece (kernel não lê a GPT primária danificada).
- O superblock primário ext4 (offset 1024, LBA 36-37) é ilegível — `mount` normal falha.
- Containers com bind mount em `/mnt/storage` morrem com exit 127.

**Solução implementada (`mnt-storage.service`):**
- `/etc/systemd/system/mnt-storage.service` monta o HDD com **superblock alternativo** via loop com offset:
  ```bash
  losetup /dev/loop100 /dev/sdb -o 17408   # 17408 = LBA 34 * 512 (início da partição)
  mount -t ext4 -o rw,sb=131072 /dev/loop100 /mnt/storage  # sb em unidades de 1024B
  ```
- Habilitado no boot (`systemctl enable mnt-storage.service`), roda antes do docker.
- Entrada correspondente do `/etc/fstab` foi comentada (backup em `/etc/fstab.bak-20260731`).

### Crise HDD 06/08/2026 (double-mount → corrupção ext4)

**Sintoma:** syncthing reportava `stat /mnt/storage/data/media/music: Bad message` no kuaray.

**Causa raiz:** o HDD estava **montado duas vezes rw simultaneamente** — um `loop0` stale (de ativação antiga do serviço, nunca desmontado) **empilhado** sob o `loop100` do `mnt-storage.service`. Duas montagens rw do mesmo ext4 → **corrupção ampla de metadados** (`iget: checksum invalid`, block bitmap checksum mismatch, milhares de inodes corrompidos). Não era bad sector novo — o disco já convivia com os LBA 8/32/34-39.

**Reparo:**
- Parado syncthing + duplicati (que segurava o bind mount do `/mnt/storage` e travava o loop).
- Desmontado loop0 + loop100, rodado `e2fsck -y -b 32768` (superblock alternativo).
- e2fsck limpou inodes corrompidos e moveu diretórios órfãos para `lost+found` (~24G recuperados). A árvore `/mnt/storage/data` foi **desconectada/perdida** como estrutura.
- Recuperado no `lost+found`: **música parcial** (subconjunto do psicopompo), dados do **Kavita**, e **4 livros EPUB** (Bruzundanga, Torto arado, Um teto todo seu, Dao De Jing).

**Consequências e decisões (06/08):**
- **Música:** integral e SEGURA no psicopompo (`/mnt/BACKUP/media/music/`, 185G). Folder `music` **removido** do syncthing do kuaray (não espelha mais).
- **Livros:** **recuperados → `/mnt/BACKUP/media/books/`** no psicopompo (única cópia). **Não havia backup** — o Duplicati cobria só `/DATA/AppData` (lição: dados de valor ficam no psicopompo, não em HDD local sem backup).
- **Duplicati removido** (06/08): o job `CASAOS FILES [KUARAY]` não cobria `/mnt/storage` nem volumes Docker. Backup de configs será resolvido futuramente de forma estruturada.
- **`mnt-storage.service`:** atualizado com `norecovery` no mount (journal tem setores ruins — sem `norecovery` o boot falharia) + drop-in `prevent-double-mount.conf` (`ConditionPathIsMountPoint=!/mnt/storage` + limpeza de loops stale sobre `/dev/sdb`).
- **Recuperação completa salva em** `/mnt/BACKUP/kuaray-hdd-recovery-20260806/` (psicopompo).

**Resolução (noite de 06/08/2026):**
- **HDD reformatado** de forma saudável: tabela **MBR** (LBA 0 fora dos bad) + partição `/dev/sdb1` iniciando em **LBA 2048** (evita LBA 8/32/34-39 de vez) + `mkfs.ext4` limpo (superblock primário válido).
- **`mnt-storage.service` REMOVIDO** (loop/offset/backup-superblock/norecovery/drop-in — tudo obsoleto). `/dev/sdb1` monta **normal** via `/etc/fstab` (UUID `c3a9e8fe-5842-4398-bfc0-e499f0102685`).
- **Música restaurada no kuaray:** folder `music` (`gtuwj-mspep`) recriado no syncthing do kuaray → `/mnt/storage/data/media/music` (mesma estrutura que o stack espera). Re-sync **177,5 GiB** do psicopompo em andamento (background). Prompt "adicionar pasta música" resolvido.
- **⚠️ Storm de deleção (noite 06/08):** recriar o folder `music` do kuaray **vazio** fez o índice do kuaray reportar a biblioteca como deletada → psicopompo (espelho) aplicou deleções, **perdendo ~18 arquivos reais (~465MB)** antes dos erros "directory not empty" protegerem (restaurados de `/mnt/HDD_SATA/Music`, intacto). **Correção:** folder `music` do kuaray → **`receiveonly`** (recebe tudo, nunca envia estado → HD defeituoso não dispara storm). Vale até migrar o Lidarr/arr-stack do kuaray.
- **Arr stack reativado:** Lidarr, Navidrome, Transmission, slskd, Soularr voltaram a rodar (navidrome lê `/music` = `/mnt/storage/data/media/music`).
- **Kavita + Calibre-web** permanecem parados — biblioteca de livros será restaurada posteriormente a partir de backup (decisão do usuário).

**Recomendações:**
- **Trocar o HDD a médio prazo** — disco de 2014 (ST1000LM024) com 3 pending sectors; embora a partição nova evite os bad atuais, o disco segue envelhecendo. Monitorar SMART.
- Mídia (música + livros) vive em `/mnt/BACKUP/media/` no psicopompo (fonte).

### Degradação do HDD (28/08/2026) — fsck de boot falhou

- **Sintoma:** após reboot (kernel 7.0.0-30), `systemd-fsck@...sdb1` falhou → `mnt-storage.mount` `dead` → HDD não montou. O Syncthing `backup` entrou em erro "folder path missing" e o NFS de música (aninhado sob `/mnt/storage`) caiu junto (Lidarr sem biblioteca).
- **Estado do disco:** SMART overall **PASSED**, mas `Current_Pending_Sector` **3 → 37**, `Multi_Zone_Error_Rate` 15742, ATA Error Count 1299 (log: UNC em LBA 32 — região conhecida), **novo erro de leitura em ~464 GB** (sector 973545360, dmesg) e `e2fsck -fn` com erros (inode 7, "Illegal block", bitmaps).
- **Reparo (28/08):** `e2fsck -fy /dev/sdb1` (corrigiu dirs/bitmaps/inodes órfãos — não bateu de novo no setor ruim); `/etc/fstab` do `/mnt/storage` com **`nofail,errors=continue`** (backup `/etc/fstab.bak-20260828`); `mount` OK. Detalhes e consequências no Syncthing: [`services/syncthing.md`](../services/syncthing.md).
- **NFS de música desacoplado do HDD (28/08):** mount movido para `/mnt/nas/media/music` (fora de `/mnt/storage`); bind do Lidarr ajustado no compose (`/mnt/nas/media/music:/data/media/music`). A biblioteca não depende mais do HDD. Ver [`network/nfs.md`](../network/nfs.md).
- **Monitorar SMART** — pending sectors crescentes + novo bad area indicam evolução da falha; reforça a recomendação de troca.

### Outras notas

- **Repo Docker corrigido trixie→noble (28/08/2026):** `/etc/apt/sources.list.d/docker.list` apontava para `https://download.docker.com/linux/debian trixie` — atualização do containerd.io exigia `libseccomp2 >= 2.6.0` (não disponível no Mint). Corrigido para `https://download.docker.com/linux/ubuntu noble` (base do Mint 22.x) + `apt update` + atualização completa do stack Docker para builds noble: **Docker 29.7.2**, **containerd.io 2.3.3** (`-1~ubuntu.24.04~noble`), docker-ce-cli/buildx/compose-plugin/model-plugin alinhados. Backup da config antiga em `/var/tmp/docker.list.bak`.

- **Home Assistant**: migrado para o **kavure** (09/08) — funnel `kavure...:10000`; **reconfigurado no kavure 16/08** (caps Bluetooth + HACS instalado).
- **CasaOS**: **removido (08/08/2026)** — containers agora via `docker compose` (`/home/kuaray/homelab/*/compose.yml`).
- Servidor multimídia — arr-stack + infra (config-as-code).
- **Pi-hole**: migrado para o **kavure** (09/08) — resolver global da tailnet.
- **Navidrome / Calibre / Kavita**: migrados para o **kavure** (09/08, bibliotecas via NFS).
- **Samba** (nmbd/smbd) roda como nativo para compartilhamento de arquivos na LAN.
- **go2rtc** nativo (inativo desde a migração) — o HA no kavure usa o **go2rtc embutido** (porta `18554`); câmeras não configuradas.
- **Duplicati removido (06/08/2026)** — o job cobria apenas `/DATA/AppData`; dados de valor (livros) não eram protegidos. Decisão: mídia consolidada no psicopompo; backup de configs estruturado (09/08).
- Kernel atualizado para 7.0.0-38-generic.
- Swap ativo: 5.4 GB em disco + 3.4 GB ZRAM (zram0).

### Ativação da Rede Cabeada e Fix Realtek RTL810xE (04/10/2026)

- **Contexto:** Kuaray foi cabeado ao switch gigabit `IT-BLUE LE-4203` (junto ao psicopompo e kavure).
- **Problema no boot:** A interface `enp7s0` subia com `NO-CARRIER` / `Link detected: no`, e o kernel registrava timeouts recorrentes:
  ```text
  Generic FE-GE Realtek PHY r8169-0-700:00: r8169_apply_firmware failed: -110
  Generic FE-GE Realtek PHY r8169-0-700:00: phy_poll_reset failed: -110
  r8169 0000:07:00.0 enp7s0: Link is Down
  ```
- **Causas e Soluções aplicadas:**
  1. **ASPM BIOS Conflict:** A BIOS Dell não cede controle de ASPM ao kernel Linux (`can't disable ASPM; OS doesn't have ASPM control`). Adicionado `pcie_aspm=off` em `/etc/default/grub` (`GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pcie_aspm=off"`) + `update-grub` (backup `/etc/default/grub.bak-20261004`).
  2. **Travamento elétrico do PHY (Auxiliary Power):** O chip PHY permaneceu travado em standby após semanas de uptime. Resolvido com **Power Drain (Cold Boot)**: desligamento total, fonte removida e botão power pressionado por 30s.
  3. **NetworkManager autonegotiate:** Perfil `Wired connection 1` estava com `auto-negotiate: no`; ajustado para `yes` com prioridade 10.
- **Resultado:** Link estabelecido em **100 Mb/s Full Duplex** (limite da placa Realtek RTL810xE Fast Ethernet). IP DHCP recebido: `192.168.3.200/24` (métrica 100 — rota default preferencial sobre o Wi-Fi `wlp6s0`, métrica 600). Latência LAN psicopompo ⇄ kuaray caiu de **~22 ms (Wi-Fi) para 0,28 ms (cabo)**.

## 07/10/2026 — Healthchecks

- Todos os containers **standalone** deste host receberam `healthcheck` (padrão: ver [`guides/docker-healthchecks.md`](../guides/docker-healthchecks.md)), habilitando o `autoheal`. Containers que eram `docker run` ganharam `compose.yml`.
