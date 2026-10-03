---
tags: [homelab, server, kavure, docker, storage, gaming, todo, miracena]
---

# kavure

**Papel:** Servidor de serviços dedicado — Sumænimá (sae-core), Minecraft, Project Zomboid, Valheim, monitoramento.
**Shell padrão:** bash (`/bin/bash`)

> **Status:** ✅ **No ar** — Ubuntu instalado, Tailscale + SSH funcionando. **Project Zomboid migrado e ativo (Docker, 06/08/2026)**; **stack de infra `ops` ativa** (autoheal, watchtower, glances) e **host em `America/Sao_Paulo`** (07/08/2026); **Sumænimá sae-core MIGRADO E ATIVO (07/08/2026)** — kavure é o manager do Swarm (role=core) com db, valkey, api (9090), umami-db, backup (NFS → psicopompo) e asciline.
> **Atualizado 28/08/2026:** `apt dist-upgrade` completo (51 pacotes) + reboot. Kernel **6.8.0-137 → 6.8.0-138**. Swarm (3 nós), jogos e serviços OK pós-reboot.
> **Home Assistant reconfigurado no kavure (16/08):** container com `cap_add: [NET_ADMIN, NET_RAW]`; **HACS 2.0.5 instalado e configurado** (OAuth GitHub OK); Tuya (nuvem) e backup automático pendentes de config. **Kavure NÃO tem hardware Bluetooth** (integração removida). Ver [`services/home-assistant.md`](../services/home-assistant.md).
> **Fix NFS shutdown race (10/09/2026):** 4 entries `hard` → `soft` no fstab (configs, repos, music, books). Todos os mounts agora usam `soft,nofail,mount-timeout=10s`. Removido `idle-timeout` dos mounts Docker (evita "device is busy" no shutdown). Criado drop-in `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). Backup fstab: `/etc/fstab.bak.20260910`. Kernel **6.8.0-138 → 6.8.0-139**. Ver [`network/nfs.md`](../network/nfs.md).
> **Fix Boot-Race Tailscale + NFS (25/09/2026):** (1) Atualizado `/etc/systemd/system/docker.service.d/nfs-ordering.conf` com `After=tailscaled.service remote-fs.target` e `Wants=tailscaled.service remote-fs.target`. Previne que o Docker inicie antes dos mounts NFS estarem prontos (o que causava `ExitCode=128` no `calibre` e `navidrome`). (2) Ativado `net.ipv4.ip_nonlocal_bind = 1` via `/etc/sysctl.d/99-tailscale-bind.conf` (kavure e psicopompo), permitindo que processos como HAProxy e Docker daemon bindem nas portas com IP específico da Tailnet antes mesmo da atribuição do IP ser concluída na interface.
> Ver [`kavure-migration-plan`](../network/kavure-migration-plan.md) para o plano completo.
> **Tag da API corrigida (29/09/2026):** o serviço `sae-core_api` passou de `sumaenima-server:latest`
> para **`sumaenima-server:cpu`** — build com `app/server/Dockerfile.cpu` (este nó é Intel i3-8100,
> sem GPU). A tag `:latest` era compartilhada com o psicopompo e a construção da imagem do kavure
> sobrescrevia/apagava a imagem CUDA do worker GPU. Ver [`services/steniorec.md`](../services/steniorec.md) §6.
> **Deploy no boot desabilitado (29/09/2026):** o `sumaenima-swarm.service` fazia
> `stack deploy` no boot a partir de uma cópia **local e desatualizada** do repo
> (`/srv/data/sumaenimahub/SUMAENIMA-HUB`). Como a unit tem `Requires=docker.service`,
> **reiniciar o Docker re-executava o deploy** — e ela reverteu silenciosamente uma
> migração de rede. Foi **desabilitada** (script → `.disabled`, cópia dos stacks →
> `stacks.desativado/`). Deploy agora tem **caminho único**: `scripts/deploy-swarm.sh`
> a partir do repo do psicopompo. Reboot não precisa de `stack deploy` — o Swarm
> persiste os serviços no Raft e reagenda as tarefas. Ver
> `docs/swarm-tailscale-troubleshooting.md` §8 no hub.
> **Pendência conhecida:** este nó não tem `tailscaled-wait.service` (só o drop-in do Docker) —
> avaliar replicar o padrão canônico.
> **Link físico novo + validação do switch (02/10/2026):** o kavure saiu do
> **extensor/repetidor Wi-Fi** e passou a ser **cabeado** no switch gigabit
> `IT-BLUE LE-4203` (8p · 16 Gbps · 11,52 Mpps · não administrável). Interface
> `enp1s0` negocia **1000 Mb/s full-duplex**, latência LAN **0,17–0,28 ms**, vazão
> medida **912 Mbps up / 858 Mbps down** (93% da linha). Ficha e método reproduzível em
> [`network/topology.md`](../network/topology.md) §Link Físico.
> **Incidente Docker (02/10/2026):** o `"live-restore": true` adicionado ao
> `daemon.json` em 29/09 é **incompatível com Swarm** → no boot das 13:08 o `dockerd`
> subiu, **carregou os containers e abortou**:
> `failed to start cluster component: --live-restore ... incompatible with swarm mode`
> → 3 tentativas → `start-limit-hit` → **daemon morto**. O `live-restore` mantinha os 33
> containers já iniciados **vivos como órfãos** (falso "tudo rodando" enquanto
> `docker ps` respondia `Cannot connect`). **Fix:** remover `live-restore` (backup
> `daemon.json.bak-20261002`) → `systemctl reset-failed docker && start` → religar os 24
> containers `unless-stopped` que o daemon parou no takeover → Swarm voltou **Leader**
> (3/3 nós Ready), sae-core 1/1. Regra nova e runbook: [`AGENTS.md`](../AGENTS.md)
> §`live-restore` PROIBIDO em host Swarm.
> **Pendência cosmética:** 13 entradas-fantasma (`12 dead` + `1 exited`) ainda aparecem
> no `docker ps -a` — são registros de **tasks antigas do Swarm** (29/09 e anteriores)
> cujas camadas já não existiam; os diretórios foram removidos do disco (37 = 37) e a
> lista em memória **limpa sozinha no próximo restart do daemon** (sem downtime imediato
> — não reiniciar o core só por isso).
> **✅ WoL RESOLVIDO (02/10/2026):** o teste das 14:07 falhou por causa da **BIOS** —
> `Deep Sleep Control` (**default** `Enabled in S4 and S5` no OptiPlex 3060) desligava a
> NIC em S5; **desabilitado pelo usuário na BIOS**. Na noite do mesmo dia o host
> **acordou via rede em 29s** (5 magic packets do psicopompo) e o boot provou a nova
> **persistência**: `Wake-on: g` sozinho (`wol@enp1s0` + netplan `wakeonlan: true` — o
> `ethtool -s` puro é runtime-only e foi zerado pelo reboot das 13:08). Pós-boot:
> Swarm 3/3 e 37/37 containers. Runbook, tempos medidos e diagnóstico físico da LED:
> [`services/wol-relay.md`](../services/wol-relay.md) §Validação de ponta a ponta.

## Hardware (confirmado em 05/08/2026)

| Item | Especificação real |
|---|---|
| **Máquina** | Dell OptiPlex 3060 SFF |
| **CPU** | Intel Core i3-8100 4C/4T @ 3.6 GHz |
| **RAM** | 12 GB (11 GiB) — 2 slots DIMM DDR4, upgrade p/ 32 GB possível |
| **Disco Sistema** | **Kingston SA400S3 223 GB SATA 2.5"** (LVM: 100 GB em `/`, 120 GB livres no VG) |
| **Disco Futuro (comprar)** | **M.2 SATA 2280 1 TB** (SO/Docker) + **HDD 3.5" 4–8 TB** (storage) |
| **GPU** | Quadro P1000 — **FORA DO PLANO: capacitor solto no repaste**, aguardando reparo |
| **Rede** | Gigabit Ethernet (`enp1s0`, **cabeada no switch**) + Wi-Fi (legada) |
| **SO** | **Ubuntu 24.04.4 LTS** (kernel **6.8.0-142**, conferido em 02/10/2026) |
| **Filesystem** | **LVM + ext4** (subiquity) |
| **Tailscale** | `100.124.146.77` — `kavure` |
| **Acesso** | `tailscale ssh kavure@kavure` (usuário `kavure`, sudo NOPASSWD — `/etc/sudoers.d/kavure-nopasswd`, 10/09/2026) |
| **LAN** | `192.168.3.41/24` **via switch gigabit `IT-BLUE LE-4203` (cabo, desde 02/10/2026)** — antes era extensor Wi-Fi. IP fixo segue desnecessário: acesso é pela tailnet |

> **SSD é SATA 2.5"** — o **slot M.2 2280 está livre** (aceita SATA M.2 ou NVMe). O Kingston 2.5" vira **reserva** quando o M.2 1 TB chegar.

## Limitações de Hardware

- **RAM 12 GB:** sae-core (~1,5 GB) + Minecraft (G1, `Xmx8G`/soft `5G`) + Zomboid B42 (ZGC, `-Xmx8g`/soft `4g`) **convivem via soft-max heap** (cada JVM só sobe até o soft quando precisa; G1/ZGC devolvem memória ociosa). Validado em 08/08/2026 (6,8G usados / 4,7G livres; swap ~1-3G a monitorar). Jogos simultâneos a 100% dos dois ainda apertam — upgrade 32 GB é a evolução.
- **SSD 223 GB:** ~80 GB usados na migração; M.2 1 TB resolverá.
- **Slot M.2:** aceita **SATA M.2** (550 MB/s) ou NVMe (limite PCIe 2.0 x4 ~1,5 GB/s) — decisão: **M.2 SATA 1 TB**.
- **HDD >4 TB:** validado sem limite de tamanho (UEFI + GPT) — expert comunidade Dell.
- **PSU 200 W:** M.2 (sem cabo) + HDD 3.5" (~25 W pico) + i3-8100 → **~120 W pico, folga grande** ✅ (sem GPU no momento).

## Diagnóstico de Saúde (06/08/2026)

| Item | Resultado | Status |
|---|---|---|
| **CPU (repaste Kryonaut)** | idle **34°C** → carga total **46°C** (limite 80°C) | ✅ Excelente |
| **RAM** | 4 GB + 8 GB @ 2400 MT/s; stress 4G sem erro; 10 GiB livres | ✅ Saudável |
| **SSD Kingston SA400** | SMART **PASSED**; 11.125 h ligado; 0 reallocated; 0 uncorrect; 30°C | ✅ Saudável |
| **SSD velocidade** | 350 MB/s leitura (normal SATA p/ esse modelo) | ✅ Normal |
| **dmesg** | ACPI `AE_NOT_FOUND` em `\_SB.PCI0.GLAN.GPEH` — bug da Dell, inofensivo (aparece em todo boot) | ✅ Limpo |

## Papéis (planejados)

- **Manager do Docker Swarm** (role=core) — sae-core (db, valkey, api, umami-db, backup, asciline)
- **Standby edge Sumænimá (29/08/2026)** — assumiu o papel que era do kuaray: `sae-edge_{proxy,tunnel,umami}-standby` (replicas=0, escala manual em failover) com constraint **`node.labels.edge_backup == true`** (kavure **mantém** `role=core`). Frontend estático em `/var/www/sumaenima` (sync via `deploy-swarm.sh`). Nginx do standby usa **docker config** (`sae-edge_nginx-conf-standby`, gerado de `templates/nginx.conf.edge.j2`) — o bind `/srv/data/sumaenimahub/nginx-backup/nginx.conf` (que estava corrompido, 63 B, dir root-owned) foi **removido em 29/08**; validado com scale-test `proxy-standby=1` (`nginx -t` OK) e revertido a 0/0.
- **backup-sentinel health `:9092`** — responde **GET e HEAD 200** desde **29/08/2026** (`do_HEAD` adicionado; antes HEAD → 501 e o widget Homepage/Uptime Kuma mostrava erro). Código em `/srv/data/sumaenimahub/SUMAENIMA-HUB/scripts/backup/backup_health_server.py` (mount `ro` no container).
- **Agendamento do backup Sumænimá (29/08/2026)** — padrão homelab: **systemd timer `hl-sumaenima-backup.timer` (03:00, `Persistent=true`)** → `/usr/local/bin/sumaenima-backup` (failsafe + ntfy `/backup`) → `docker exec sae-core_backup python3 /app/scripts/backup/sentinel.py` (Borg + pg_dump → NFS psicopompo). O crond dentro do container **foi removido** (29/08): a imagem passou a rodar como `appuser` e o crond não lia `/etc/crontabs/root` (Permission denied) — o run diário teria parado silenciosamente. Marcador `.backup_last_run` é tocado pelo host (root); health file `/srv/health/sumaenima-backup-last-ok`. `.env` do repo lido pelo sentinel como grupo `appuser` (640, gid 1001).
- Servidor de jogos — **Project Zomboid** (Docker — `danixu86/project-zomboid-dedicated-server`, **ativo** desde 06/08/2026) + **Minecraft Dominium** (Crafty, **ativo** desde 08/08/2026 — ver [`crafty`](../services/crafty.md)) + **Valheim** (Docker — `mbround18/valheim:3`, **ativo** desde 09/09/2026 — ver [`valheim-server`](../services/valheim/valheim-server.md))
- Painel de gestão do Zomboid (Zomboid Control Panel)
- Monitoramento — **Glances ativo** (`:61208`, 07/08/2026); **watchtower** (auto-update, schedule 03:00 BRT) e **autoheal** ativos; portainer planejado
- Streaming — **aiostreams** (`:3000`, funnel `kavure.chimaera-heptatonic.ts.net:8443`) e **comet** (`:8000`), migrados do kuaray em **09/08/2026** (ver [`aiostreams`](../services/aiostreams.md) e [`comet`](../services/comet.md))
- **Miracena Stack** (10/09/2026) — CMS + Automatização + Sites: Directus (`:8055`), WordPress (`:8085`), n8n (`:5678`), Nginx Proxy Manager (`:81` admin, `:8180` HTTP, `:8445` HTTPS), PostgreSQL (compartilhado: Directus + n8n), Redis, MariaDB. Deployed em `/srv/data/miracena/` com resource limits (~5.6 GB RAM total). **Tailscale Funnel** ativo em `miracena.chimaera-heptatonic.ts.net` (HTTPS público → NPM → WordPress). Ver [`miracena-stack`](../services/miracena-stack.md)

## Layout de Storage

```
Atual (após merge LVM em 06/08/2026):
  sda  Kingston SA400S3 223 GB SATA 2.5"  → LVM ubuntu-vg (LV único expandido)
  sda1 1GB vfat  /boot/efi
  sda2 2GB ext4  /boot
  sda3 ~220 GB   LVM  → ubuntu-lv (217 GB) → /   ← LV único, todo o espaço
```

**Estrutura de pastas (FHS):**

```
/srv/data/zomboid/    ← Docker Zomboid (danixu86/project-zomboid-dedicated-server)
/srv/data/ops/        ← stack de infra (autoheal, watchtower, glances)
/srv/data/sumaenimahub/ ← código + volumes + backup do Sumænimá sae-core (07/08/2026)
/srv/data/sumaenimahub/SUMAENIMA-HUB  ← repo de deploy
/srv/data/sumaenimahub/volumes/       ← dados PostgreSQL/Valkey/Umami
/srv/data/sumaenimahub/backup         ← mount NFS → psicopompo /mnt/BACKUP/sumaenima-server-kavure
/srv/data/minecraft/   ← Crafty/Minecraft Dominium (08/08/2026 — migrado do psicopompo)
/srv/data/minecraft/minecraftserver [dominium]  ← servidor 1.21.1/Fabric (38 GB)
/srv/data/minecraft/offbox  ← mount NFS → psicopompo /mnt/BACKUP/minecraft-server-kavure (backup AdvancedBackups)
/srv/data/valheim/     ← Valheim Dedicated Server (09/09/2026 — mbround18/valheim:3)
/srv/data/valheim/offbox  ← mount NFS → psicopompo /mnt/BACKUP/valheim-server-kavure (backup)
/srv/data/miracena/    ← Miracena Stack (10/09/2026 — Directus, WordPress, NPM, PostgreSQL, Redis, MariaDB)
/srv/data/           ← dados de jogo (mundos, saves)
/var/lib/docker/     ← volumes Docker
```

> **Decisão:** LV único de 217 GB (merge com `lvextend -r -l +100%FREE`), organização por pastas FHS. Mais simples e todo o espaço utilizável; risco de `/` cheio mitigado com monitoramento.

Plano (compras):
  Slot M.2 2280  → M.2 SATA 1 TB  (SO + Docker + jogos)
  Porta SATA     → HDD 3.5" 4-8 TB (/srv/data, storage massivo)
  Kingston 2.5"  → reserva

- **Sem snapshots de SO** — fora do padrão Ubuntu; proteção real vem do backup off-box.

## Backup

### Backups Automáticos (systemd timers)

| Timer | Horário | Serviço | Método |
|-------|---------|---------|--------|
| `hl-config-backup.timer` | 05:00 | Configs do host | rsync → NAS |
| `hl-zomboid-backup.timer` | 05:15 | Project Zomboid | rsync → NAS |
| `hl-n8n-backup.timer` | 05:25 | n8n (PostgreSQL) | pg_dump → NAS |
| `hl-miracena-backup.timer` | 05:35 | Miracena Stack | pg_dump + mysqldump + rsync → NAS |
| `hl-sumaenima-backup.timer` | 03:00 | Sumænimá | Borg + pg_dump → NAS |
| `hl-valheim-backup.timer` | 05:30 | Valheim | rsync → NAS |

### Mount NFS para backups

```bash
# Todos os mounts usam soft (nunca hard) para evitar deadlock no shutdown
# Padrão: /etc/fstab com x-systemd.automount,x-systemd.mount-timeout=10s,nofail
```

- **psicopompo** = NAS da tailnet (NFSv4, 930 GB livres)
- **rsync incremental** → `--link-dest` para retenção de múltiplos pontos no tempo

## Docker (Ubuntu 24.04)

- Instalação: `docker.io` + `docker-compose-v2` (repo Ubuntu) — trivial.
- Storage driver: **overlay2** (padrão).
- AppArmor default (sem fricção com containers, ao contrário do SELinux do openSUSE).

### Auto-start no boot (07/08/2026)

- **`sumaenima-swarm.service`** (systemd, habilitado) → `/usr/local/bin/sumaenima-boot.sh`: deploy do Swarm `sae-core` + `sae-edge` no boot (exporta `.env`, espera docker).
- **GPU workers** (no psicopompo): `sumaenima-gpu.service` (systemd user, linger ativo) sobe via `sumaenima-ctl start`.
- Demais serviços do kavure (pz-server, ops, dockerproxy, zomboid-panel) usam `restart: unless-stopped` — sobem com o Docker.

## See also
- [[kavure-migration-plan]] — Plano completo de migração
- [[project-zomboid]] — Servidor Project Zomboid
- [[zomboid-control-panel]] — Painel web do Zomboid
- [[crafty]] — Servidor Minecraft (Crafty)
- [[steniobot]] — Sumænimá (sae-core)
