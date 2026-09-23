---
tags: [homelab, server, kuaray, docker, storage, media, home-assistant, automation]
---

# kuaray

> ## ⚠️ DEPRECIADO (28/08/2026)
> Nó **retirado da topologia ativa** — fora de qualquer papel operacional no homelab e no Sumænimá.
> Deploys de Sumænimá (frontend/edge) **não** incluem mais kuaray (ver `deploy.py` / `deploy-sync.yml` no repo).
> O conteúdo abaixo fica como **referência histórica/config-as-code** (serviços podem estar desligados a qualquer momento).

**Papel:** Servidor multimídia — *arr stack, streaming, automação residencial
**Shell padrão:** bash (`/bin/bash`)
**Swarm role:** `standby` — nó worker do Docker Swarm (stack `sae-edge`, serviços standby com réplicas 0)

> **Config-as-code (09/08/2026):** todos os containers do kuaray agora têm `compose.yml` em
> `/home/kuaray/homelab/{serviço}/` (lidarr, prowlarr, transmission, slskd, soularr, flaresolverr,
> vert, mosquitto, syncthing, glances, dockerproxy, autoheal) — espelhados no NAS via `config-backup`.
> Segredos (ex: `TRANS_PASS`) ficam em `.env` (fora do espelho) / store sops.
> **Atualizado 28/08/2026:** `apt dist-upgrade` + **repo Docker corrigido trixie→noble** + reboot. Kernel **7.0.0-28 → 7.0.0-30**. Stack Docker alinhada ao repo noble (Docker 29.7.2, containerd.io 2.3.3). watchtower permanece pausado.
> **Migrados p/ kavure (09/08):** Home Assistant, Pi-hole, Navidrome, Calibre Web. **Kavita removido 10/08**.
> **Mosquitto removido (16/08)** — sem dispositivos MQTT em uso; leftovers do HA antigo (`/home/kuaray/docker/homeassistant`) limpos (espelho no NAS preservado).
> **Fix NFS (10/09/2026):** Corrigido `nofail,nofail` duplicado no fstab. Entries já usam `soft` (padrão homelab). Ver [`network/nfs.md`](../network/nfs.md).

**Papel:** Servidor multimídia — *arr stack, streaming, automação residencial
**Swarm role:** `standby` — nó worker do Docker Swarm (stack `sae-edge`, serviços standby com réplicas 0)

## Hardware

| Item | Especificação |
|---|---|
| **SO** | Linux Mint 22.3 (Zena) |
| **Kernel** | 7.0.0-30-generic |
| **CPU** | Intel Core i5-4200U @ 1.60 GHz (max 2.60 GHz) — 2C/4T |
| **GPU** | Intel HD Graphics (Haswell) + NVIDIA GeForce GT 740M |
| **RAM** | 5.7 GB (3.4 GB em uso) |
| **Swap** | 5.4 GB (swap on disk) + 3.4 GB ZRAM |
| **Disco Sistema** | 224 GB SSD (Kingston A400) — `/dev/sda2` — 23% usado |
| **Disco Storage** | 932 GB HDD (Seagate 1TB) — `/dev/sdb1` (MBR, início em LBA 2048) — **reformatado 06/08/2026** (bad sectors LBA 8/32/34-39 evitados pela partição). **Degradado 28/08:** pending sectors 3→37, erro de leitura ~464 GB, fs com erros (reparado `e2fsck -fy`); montado com `nofail,errors=continue` |
| **Tailscale IP** | 100.94.209.99 |
| **Tailscale DNS** | kuaray.chimaera-heptatonic.ts.net |
| **Rede** | Wi-Fi Qualcomm Atheros QCA9565 (`wlp6s0`: 192.168.3.53) + Ethernet Realtek RTL810xE |
| **Usuário** | kuaray |
| **Acesso** | `tailscale ssh kuaray@kuaray` (usuário `kuaray`, sudo NOPASSWD — `/etc/sudoers.d/kuaray-nopasswd`, 10/09/2026) |

## Papéis

- Servidor multimídia (música, livros, torrent, streaming) — **biblioteca lida via NFS do psicopompo desde 07/08** (`/mnt/storage/data/media/music` = mount NFS; ver [`network/nfs.md`](../network/nfs.md))
- Espelho frio de backup: `/mnt/storage/backup` (folder `backup` do Syncthing, receiveonly) — ver [`services/syncthing.md`](../services/syncthing.md)
- Automação residencial (~~Home Assistant~~ migrado p/ kavure 09/08; ~~MQTT~~ removido 16/08)
- DNS secundário (Pi-hole)
- Gamificação (Kavita manga/ebook) — **removido 10/08** (não era mais usado)
- Monitoramento (Glances)

## Tailscale Funnels

| URL | Proxy para | Serviço |
|---|---|---|
| ~~`kuaray.chimaera-heptatonic.ts.net:10000`~~ | — | Home Assistant (**funnel movido p/ kavure 09/08**) |

## Containers Docker

> **Estado (06/08/2026, noite):** **19 containers ativos** — o stack de música (Lidarr, Navidrome, Transmission, slskd, Soularr) foi **reativado** após o HDD ser reformatado. **Duplicati removido** (06/08 — não cobria os dados de valor). Apenas **Kavita** e **Calibre-web** seguem parados (biblioteca de livros perdida; ver [Crise HDD 06/08](#crise-hdd-06082026)).

### Ativos

| Container | Imagem | Portas | Função |
|---|---|---|---|
| pihole | pihole/pihole:latest | `0.0.0.0:53`, `0.0.0.0:8080` | DNS ad-blocking (Docker) |
| prowlarr | lscr.io/linuxserver/prowlarr:latest | `0.0.0.0:9696` | Indexer de torrent/usenet |
| flaresolverr | ghcr.io/flaresolverr/flaresolverr:latest | `0.0.0.0:8191` | Proxy Cloudflare |
| vert | ghcr.io/vert-sh/vert | `0.0.0.0:3030` | Proxy/content |
| syncthing | linuxserver/syncthing:1.29.7 | `0.0.0.0:8384` | Sincronização |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoramento |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `0.0.0.0:2375` | Proxy socket Docker |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| lidarr | — | `0.0.0.0:8686` | Gerenciamento de música |
| navidrome | — | `0.0.0.0:4533` | Streaming de música |
| transmission | — | `0.0.0.0:9091`, `51413` | Cliente Torrent |
| slskd | — | `0.0.0.0:5030` | Cliente Soulseek |
| soularr | — | `0.0.0.0:8265` | Download Soulseek |

### Exited (parados — livros ainda não restaurados)

| Container | Portas | Função |
|---|---|---|
| calibre-web (cwa) | `0.0.0.0:8083` | Servidor de ebooks |

## Programas Nativos

| Programa | Função |
|---|---|
| go2rtc | Proxy WebRTC/RTSP (câmeras) |
| Samba (nmbd/smbd) | Compartilhamento de arquivos (SMB) |
| tailscaled | Agente Tailscale |
| nginx | Borda Secundária (Serviço de backup, React static frontend, proxy reverso) |

## Portas Importantes

| Porta | Serviço | Bind |
|---|---|---|
| 53 | Pi-hole (DNS) | `0.0.0.0` |
| 139, 445 | Samba | `0.0.0.0` |
| 3030 | Vert | `0.0.0.0` |
| 8080 | Pi-hole (admin) | `0.0.0.0` |
| 8085 | Nginx (Borda Secundária) | `0.0.0.0` |
| 8191 | Flaresolverr | `0.0.0.0` |
| 8384 | Syncthing | `0.0.0.0` |
| 9696 | Prowlarr | `0.0.0.0` |
| 61208 | Glances | `0.0.0.0` |
| 2375 | Docker proxy | `0.0.0.0` |
| 22000 | Syncthing transfer | `0.0.0.0` |
| 3389 | RDP (provavelmente xrdp) | `0.0.0.0` |
| 18555 | Desconhecido | `0.0.0.0` |
| 631 | CUPS (impressão) | `127.0.0.1` |

> **Portas de serviços Exited** (não escutam, aguardando migração): 4533 (navidrome), 5030 (slskd), 8265 (soularr), 8083 (calibre-web), 8686 (lidarr), 9091/51413 (transmission).

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
- Kernel atualizado para 6.17.0-23-generic.
- Swap ativo: 5.4 GB em disco + 3.4 GB ZRAM (zram0).
