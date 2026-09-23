---
tags: [homelab, network, storage, gaming, todo]
---

# kavure — Plano de Migração

Plano completo para o **kavure** (Dell OptiPlex 3060 SFF) assumir como servidor de serviços do homelab, tirando a carga do **psicopompo** (que vira ambiente de dev + GPU workers).

## Objetivo

- **kavure** vira o servidor dedicado: Sumænimá (sae-core), Minecraft, Project Zomboid, monitoramento.
- **psicopompo** deixa de ser servidor → vira **ambiente de desenvolvimento + GPU workers** (vision/audio/ollama).
- **Migração com integridade total** dos dados (Minecraft + Zomboid) — nenhum dado pode ser perdido.
- Ambos os servidores de jogo **nascem down** e sobem sob demanda.

## Decisões aprovadas

| Decisão | Valor |
|---|---|
| Hostname | kavure |
| **Distro** | **Ubuntu Server 24.04 LTS** |
| **Filesystem** | **LVM + ext4** (padrão do instalador subiquity, sem gambiarras) |
| **Snapshots de SO** | Nenhum (fora do padrão; proteção real via backup off-box) |
| RAM | Apertar com 12 GB — Zomboid `-Xmx6g` + ZGC; jogos nunca simultâneos; upgrade 32 GB como evolução |
| Orquestração | Docker Swarm — kavure = manager (role=core), psicopompo = worker (role=gpu) |
| Zomboid | **Docker** (`danixu86/project-zomboid-dedicated-server`) + Zomboid Control Panel (RCON habilitado); ✅ **CONCLUÍDO 06/08/2026** |
| Minecraft | Crafty (bind mounts idênticos) |
| Storage até HD novo | SSD local do kavure (~80 GB) + backup off-box no psicopompo `/mnt/BACKUP` |
| **Storage futuro** | **M.2 SATA 2280 1 TB** (SO/Docker) + **HDD 3.5" 4–8 TB** (`/mnt/storage`) — comprar |
| **GPU** | **Quadro P1000 FORA do plano** — capacitor solto no repaste, aguardando reparo |
| psicopompo | Remover **somente containers mapeados**; portainer/dockerproxy/resto intocados |

## ✅ Fase A0 — CONCLUÍDA (05/08/2026)

> **Status:** Ubuntu 24.04.4 instalado, Tailscale + SSH funcionando, specs reais registradas em `kavure.md`.

1. ✅ **Windows 11 bootado** e specs validadas.
2. ⏳ **Repaste do CPU (i3-8100)** — pendente (fazer na 1ª abertura da máquina).
3. ✅ **Ubuntu Server 24.04.4 LTS** instalado com layout LVM + ext4 (100 GB em `/`, 120 GB livres no VG).
4. ✅ **SSH** habilitado.
5. ✅ **`tailscale up`** → hostname `kavure`, IP `100.124.146.77`.
6. ✅ **Acesso:** `tailscale ssh kavure@kavure` (usuário `kavure`, sudo).
7. ✅ **Specs reais registradas** em `kavure.md`.

### GPU P1000 — ❌ FORA DO PLANO

- Durante o repaste, **um capacitor foi solto da P1000**. Placa **aguardando reparo** (técnico de micro-solda/reflow) — sem previsão.
- **Impacto no plano: NENHUM** — kavure roda tudo (Sumænimá, Minecraft, Zomboid) sem GPU; iGPU Intel UHD 630 basta para headless. GPU era offload futuro.
- Quando/SE a placa for reparada, retomar: instalar no PCIe x16 + `gpu-burn` p/ verificar temperatura.

### Storage — Plano de compras (validado)

| Item | Especificação | Status |
|---|---|---|
| **M.2 SATA 2280 1 TB** | slot livre (aceita SATA); SO + Docker + jogos | Comprar |
| **HDD 3.5" 4–8 TB** | porta SATA (única alimentação); sem limite de tamanho (UEFI+GPT) | Comprar |
| Kingston SA400 223 GB | 2.5" SATA atual | Reserva |

## Fase A — Provisionamento

- Instalar: `docker.io`, `docker-compose-v2`, `tailscale` (✅ já), `openssh-server` (✅ já), `rsync`.
- **NVIDIA driver + container-toolkit:** ⏸️ adiado — P1000 fora do plano (aguardando reparo).

## ✅ Fase B — Migração Sumænimá (sae-core) — CONCLUÍDA (07/08/2026)

1. ✅ `pg_dump` do DB principal + Umami; volumes, `.env`, migrations copiados (rsync via Tailscale + tar via docker).
2. ✅ `SUMAENIMA-HUB` no kavure (`/srv/data/sumaenimahub/`); bind mounts do `core.yml` ajustados p/ paths do kavure + porta 9090 publicada.
3. ✅ Swarm: `docker swarm init` no kavure → join de psicopompo (role=gpu), ybyra (primary), kuaray (standby); labels aplicados; `docker stack deploy -c core.yml sae-core`.
4. ✅ GPU workers (vision/audio/ollama) continuam no psicopompo via `gpu.yml` (overlay `sumaenima_sumaenima-net` → api/valkey/ollama no kavure).
5. ✅ Nginx do ybyra (e standby kuaray) → proxy `api:9090` (kavure); `hosts.ini`/`deploy.yml` atualizados.
6. ✅ `sumaenima-ctl` gerencia o Swarm via SSH ao kavure (GPU local no psicopompo).
7. ✅ Validado: health `kavure:9090/api/health` 200, ybyra `/api/health` 200, Funnel público 200, backup NFS ativo.

## Fase C — Jogos (migração com integridade)

### C1 — Minecraft Dominium (38 GB) — ✅ CONCLUÍDA (08/08/2026)

> **Execução real (08/08/2026):** Crafty + servidor migrados com rsync `--checksum` (0 diferenças). **Backup (AdvancedBackups) redirecionado para o NAS via NFS** (decisão do usuário — padrão off-box): `/srv/data/minecraft/offbox` → `/mnt/BACKUP/minecraft-server-kavure/` (histórico de 25GB do HDD copiado para o NAS; o purge do plugin limpa o antigo). **JVM flags G1** aplicadas no Crafty (`execution_command`): piso 2G / teto 8G / soft 5G + Aikar + `G1PeriodicGCInterval` (coexistência com o Zomboid). Correção necessária: `chown -R 1000:1000` no folder do servidor (o crafty roda o java como uid 1000; o `latest.log` root-owned impedia o log).

1. ✅ Conferir que o AdvancedBackups (25 GB no HDD) está íntegro → **copiado para o NAS** `/mnt/BACKUP/minecraft-server-kavure/`.
2. ✅ Parar `crafty-controller` no psicopompo (mundo consistente) — servidor já estava parado desde 22/07.
3. ✅ `rsync -aHAX --checksum --info=progress2` de `/mnt/NVME_PCI/minecraftserver [dominium]` → `/srv/data/minecraft/minecraftserver [dominium]`.
4. ✅ **Verificação:** `rsync -n --checksum` (0 diferenças) + `du` 38G=38G.
5. ✅ Container recriado com os mesmos binds (compose), mount do backup → `offbox` NFS; servidor nasce down (liga na web UI do Crafty `kavure:8443`).
6. ✅ Validado: boot `Done (~15s)`, RCON, Voice Chat, **jogador entrou** (08/08/2026). RAM coexistindo com Zomboid (6,8G usados / 4,7G livres; swap ~1-3G a monitorar).

### C2 — Project Zomboid (27 GB) — ✅ CONCLUÍDA (06/08/2026)

> **Nota:** o plano original previa LinuxGSM, mas a execução usou **Docker** (`danixu86/project-zomboid-dedicated-server`) com Compose em `/srv/data/zomboid/` — ver [`services/zomboid/project-zomboid.md`](../services/zomboid/project-zomboid.md). Passos reais:

1. ✅ Parar `zomboid.service` + backup do save (`/home/pzserver/Zomboid`) → `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/`.
2. ✅ `rsync -aHAX` do `Zomboid/` → `data/` e do `workshop/` → `workshop-mods/` + verificação `rsync -n --checksum` (0 diferenças).
3. ✅ Deploy via **Docker Compose** (`/srv/data/zomboid/docker-compose.yml` + `.env`), volumes: `data/` → `/home/steam/Zomboid`, `pz-dedicated/` → `/home/steam/pz-dedicated`, `workshop-mods/` → `.../steamapps/workshop`.
4. ✅ **Habilitar RCON** no `pzserver.ini` (`RCONPort=27015` + senha) — corrigido no painel (`rconHost=pz-server`).
5. ✅ **Zomboid Control Panel** instalado (Docker, `fpsacha/zomboid-panel`) + auto-scan + autobackup; acesso via Tailscale `:3001`.
6. ✅ Serviço **nasce down** e sobe on-demand via scripts `zomboid-*` (cron restart 4x/dia: 05/11/17/23).
7. ✅ Testado boot do mundo (`SERVER STARTED`, `isNewGame=false`) + validação dos ~65 mods.
8. ✅ **JVM B42:** `-Xms1024m -Xmx6144m` + flags ZGC (`ZUncommit`, `ZUncommitDelay=60`, `SoftMaxHeapSize=4g`) no `ProjectZomboid64.json`.
9. ✅ **Backup pré-update** obrigatório (`zomboid-update` → `archive/pre-update-<data>/`) + backup off-box diário 01:15 (`zomboid-backup` → `daily/`).

## Fase D — Backup off-box

- **rsync incremental** (via Tailscale) → **psicopompo `/mnt/BACKUP`** (930 GB livres), com retenção de múltiplos pontos no tempo via `--link-dest`.
- Cobre: mundos de jogo (retenção 7+ dias), código, configs.
- psicopompo = redundância, **não dependência**.

## Fase E — Docs do repo infra

- **Criar:** `servers/kavure.md` ✅, `recovery/disaster-recovery.md` ✅ (unificado 09/08), `services/zomboid/project-zomboid.md` ✅, `services/zomboid/zomboid-control-panel.md` ✅.
- **Infra `ops` (07/08):** **autoheal**, **watchtower** (schedule 03:00 BRT, cleanup, atualiza tudo incluindo `pz-server`) e **glances** (`:61208`) instalados em `/srv/data/ops/`. **Host em `America/Sao_Paulo`** — agendamento do Zomboid via systemd timers (restart 4x/dia 05/11/17/23 com `RESPECT_PLAYERS=1` + backup 05:15) em horário de Brasília.
- **Atualizar:** `README.md` ✅, `_tags.md` (+`#kavure`, `#zomboid`, `#zomboid-panel`), `network/topology.md`, `network/service-topology.md`, `network/tailscale.md` (corrigir funnel/exit node inexistentes), `network/dns.md`, `services/steniobot.md`, `services/crafty.md`, `servers/psicopompo.md` (papel dev+GPU), `recovery/disaster-recovery.md` (unificado), `backups/strategy.md`.

## Fase F — Finalizar psicopompo — ✅ CONCLUÍDA (08/08/2026)

- ✅ Remover **somente containers mapeados** (sae-core stack, crafty). **Portainer, dockerproxy e demais permanecem intocados** até novo inventário.
- ✅ Removido do psicopompo (após validação da migração no kavure): `crafty-controller` (container), rede `minecraftserver_default`, `/mnt/HDD_SATA/minecraftserver [dominium-backup]` (25 GB — histórico no NAS) e `/mnt/NVME_PCI/minecraftserver [dominium]` (38 GB — fonte migrada). Backup íntegro em `/mnt/BACKUP/minecraft-server-kavure/`.
- Deixar: GPU workers (vision/audio/ollama) + Steam + ambiente dev.

## Riscos / Gargalos

- **RAM 12 GB:** sae-core (~4,5 GB) + Minecraft (4–6 GB) + Zomboid B42 (`-Xmx6g`) **não rodam juntos** → jogos on-demand + limites de memória + upgrade p/ 32 GB como evolução.
- **Zomboid B42 pede `-Xmx12g` na doc** — com 12 GB de RAM precisamos apertar para `-Xmx6g` + ZGC (menos players/possível stutter).
- **Patches B42 podem quebrar saves** → backup obrigatório pré-update (rsync, retenção 7+ dias).
- **SSD 223 GB:** ~80 GB usados; **M.2 SATA 1 TB + HDD 4–8 TB** resolvem (comprar).
- **M.2 PCIe 2.0 x4** (~1,5 GB/s) — metade da velocidade NVMe, irrelevante (opção escolhida: M.2 SATA).
- **PSU 200 W:** sem GPU → M.2 (sem cabo) + HDD 3.5" 4-8 TB (~25 W pico) + i3-8100 → **~120 W pico, folga grande** ✅. Se a P1000 for reparada no futuro: +47 W → ~170 W, ainda ok com 1 HDD.
- **P1000 (aguardando reparo):** capacitor solto — fora do caminho ativo; zero impacto nas Fases B–D.
- **Node labels do Swarm** não configuradas hoje → aplicar antes do deploy.
- **Docs divergem da realidade** (funnel, roles, nós Down) → corrigidos na Fase E.
- **RCON** do Zomboid precisa ser habilitado (requisito do painel).
- **Crafty** roda non-root no container — ok no Ubuntu (AppArmor default, sem fricção).

## Referências

- `servers/kavure.md` — documentação do servidor
- `network/topology.md` — IPs e rede
- `network/tailscale.md` — tailnet
- `backups/strategy.md` — estratégia de backup
