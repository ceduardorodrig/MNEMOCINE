---
tags: [homelab, service, zomboid, gaming]
---

# Project Zomboid

Servidor dedicado de **Project Zomboid (Build 42)**.

**Servidor atual:** kavure (**Docker** — `danixu86/project-zomboid-dedicated-server`)
**Servidor anterior:** psicopompo (LinuxGSM) — **DESLIGADO** (service/timers/user desativados em 06/08/2026; dados quietos no disco — ver [[zomboid-psicopompo-handoff]])

## Resumo

- **Versão:** Build 42 (**stable**)
- **Gerenciamento:** **Docker Compose** no kavure (antes: LinuxGSM)
- **Portas:** `16261` (game), `16262` (direct connection) — UDP; `27015` — TCP (RCON)
- **Máx. players:** 15
- **Mods:** **125 Workshop + 148 Mod IDs** (15/08: **coleção completa KI5 B42 MP** adicionada — 39 itens novos; collection ID `3652192243` é inválido em `WorkshopItems=` e foi removido; total inclui packs multi-mod: Mini Mk2 → 4, Jeep YJ → 2, Cadillac Miller-Meteor → `59meteor`+`ECTO1`)
- **Admin/Painel:** Zomboid Control Panel (ver [`zomboid-control-panel`](zomboid-control-panel.md))

## Localização atual (kavure — Docker)

| Item | Caminho |
|---|---|
| Stack | `/srv/data/zomboid/` (docker-compose.yml + .env) |
| Dados (saves/config) | `/srv/data/zomboid/data/` (volume → `/home/steam/Zomboid`) |
| Mods Workshop | `/srv/data/zomboid/workshop-mods/` (volume → `/home/steam/pz-dedicated/steamapps/workshop`) |
| Container | `pz-server` (imagem `danixu86/...`) |

> **⚠️ Mods do Workshop ficam em `linuxgsm/serverfiles/steamapps/workshop/`** no LinuxGSM, **não** em `Zomboid/Workshop/` (que fica vazio). Na migração, esse path foi mapeado para `workshop-mods/`.

> **Instalar novos mods (10/08/2026):** basta adicionar o ID em `WorkshopItems=` + o `id=` do mod.info em `Mods=` no `pzserver.ini` e reiniciar (o jogo baixa do Workshop no boot; pode precisar de 2 restarts). **Staircast e ZombieBuddy foram removidos em 10/08** (Staircast exigia o framework Java ZombieBuddy, que por sua vez exigia instalação manual no cliente de cada jogador — descartado). Ver [`onboarding`](onboarding.md).

> **⚠️ Collections do Workshop NÃO funcionam em `WorkshopItems=`** (só IDs de itens individuais, semicolon-separados). Em 15/08/2026 a collection KI5 (`3652192243`) foi removida e os 39 itens dela que faltavam foram adicionados individualmente (`pzserver.ini.bak-20260815` tem o estado anterior). Para instalar uma collection: extrair os IDs individuais → `WorkshopItems=`, reiniciar (download), ler `mod.info`/`id=` de cada item novo → `Mods=`, reiniciar de novo.

> **Painel e workshop (07/08/2026):** o Zomboid Control Panel lê os mods via bind de `workshop-mods/` em `/pz-server/steamapps/workshop` (overlay no compose do painel). A cópia velha em `pz-dedicated/steamapps/workshop/` — que causava "Mod update available" eterno — foi **removida** (1.3G). Ver [`zomboid-control-panel`](zomboid-control-panel.md).

## Gerenciamento (Docker)

**Comandos rápidos (scripts no kavure):**

```bash
zomboid-start      # inicia o servidor
zomboid-stop       # para o servidor
zomboid-restart    # reinicia o servidor (save RCON + docker restart)
zomboid-status     # mostra status + porta
zomboid-save       # envia comando RCON "save" (client Source RCON em Python)
```

> **`zomboid-restart` é gracioso:** faz `save` via RCON antes do restart, pois o entry.sh do container **não trap SIGTERM** (PID1 = bash → hard-kill do java se usar `docker compose restart` direto). O log fica em `/var/log/zomboid-restart.log`.

Equivalente manual (em `/srv/data/zomboid`):

```bash
cd /srv/data/zomboid
docker compose up -d            # start
docker compose down             # stop
docker compose restart pz-server # restart
docker compose logs -f          # console
docker compose ps               # status
```

> **⚠️ O painel (Zomboid Control Panel) NÃO controla start/stop** — PZ roda em container separado, e o painel não vê processos de outros containers (status sempre "stopped" é falso negativo). O lifecycle é gerenciado pelo Docker via `zomboid-*`. O painel serve para RCON/console/players/mods/backup.

## Limitações da Arquitetura (PZ em container separado)

> **Contexto:** o painel controla o servidor spawnando `start-server.sh` como processo do host. Com o PZ em container Docker separado, há uma divisão de responsabilidades:

| Capacidade | Painel | Docker | Como fazer |
|---|---|---|---|
| RCON / console / comandos admin | ✅ | — | painel (RCON conectado) |
| Players online / mapa / mods / config / backup | ✅ | — | painel (RCON + PanelBridge) |
| **Start / Stop / Restart** | ❌ | ✅ | `zomboid-start/stop/restart` |
| **Status real (running/stopped)** | ❌ (falso "stopped") | ✅ | `zomboid-status` |
| **Update do jogo (Build)** | ❌ | ✅ | `zomboid-update` |
| **Restart agendado (Scheduler)** | ❌ | ✅ | systemd timer `hl-zomboid-restart.timer` (kavure) |
| **Install novo servidor (wizard)** | ❌ | ✅ | via Docker |

**Leitura:** o painel administra **o jogo** (players, mapa, mods, config, backups, comandos); o **Docker gerencia o processo** (start/stop/status/update). O indicador "stopped" do painel é esperado e não indica falha.

**Para atualizar mods:** basta `zomboid-restart` (o PZ baixa updates do Workshop no startup — confirmado na doc do LinuxGSM original e no container Danixu).

## Configuração (`.env` — LOCAL, não versionar)

| Variável | Valor | Nota |
|---|---|---|
| `STEAMAPPBRANCH` | `public` | Build 42 (estável — renomeada de `stable` para `public` pela Valve em 08/2026) |
| `SERVERNAME` | `pzserver` | Deve casar com o `pzserver.ini` migrado |
| `PUBLIC` | `true` | Visível no browser |
| `MAX_MEMORY` | `6144m` | Teto do heap (Xmx) |
| `MIN_MEMORY` | `1024m` | Heap inicial (Xms) — **crescimento dinâmico** (1G→6G sob demanda) |
| `RCONPASSWORD` | (gerada) | RCON p/ painel + `zomboid-save` |
| `SELF_MANAGED_MODS` | `true` | Não sobrescreve `Mods=`/`WorkshopItems=` |

### Memória (JVM)

- `-Xms${MIN_MEMORY} -Xmx${MAX_MEMORY}` aplicados pelo entry.sh → `-Xms1024m -Xmx6144m` (confirmado no `ps`).
- **Dinâmico:** o JVM começa em ~1 GB e só "comita" RAM conforme o heap cresce — não reserva 6 GB em idle.
- **Flags ZGC** (no `ProjectZomboid64.json`, volume do host `/srv/data/zomboid/pz-dedicated/`):
  - `-XX:+ZUncommit` — devolve RAM ao SO (default ON, explícito por clareza)
  - `-XX:ZUncommitDelay=60` — acelera a devolução (default 300s)
  - `-XX:SoftMaxHeapSize=4g` — **alvo "soft" de 4 GB**: o ZGC tenta manter o heap ≤ 4 GB (GC mais ativo), crescendo até 6 GB (Xmx) só se necessário para não travar. É o knob nativo do ZGC para "usar o mínimo com teto de segurança".
  - ⚠️ **`-XX:Min/MaxHeapFreeRatio` NÃO são knobs do ZGC** (são de Parallel/G1) — não têm efeito comprovado aqui (fonte: doc Oracle ZGC + análise openjdk/zgc).
  - ⚠️ **`zomboid-update` (steamcmd `validate`) sobrescreve o JSON** → **reaplicar as flags após qualquer update**. O backup do estado sem flags fica em `ProjectZomboid64.json.bak`.
- **Expectativa realista:** o mundo carregado + 65 mods puxam ~5–7 GB RSS em pico; o `SoftMaxHeapSize=4g` incentiva usar menos em idle, mas com `PauseEmpty=true` o mundo fica pausado porém **residente** — o ganho em idle é modesto (a memória é live set, não desperdício). Para zerar RAM em idle, `zomboid-stop` é a única forma real.
- **⚠️ A memória só muda via `.env` + `docker compose up -d`** (recreate) p/ Xms/Xmx; flags JVM no `ProjectZomboid64.json` + `zomboid-restart`. `docker compose restart` **não relê** o `.env`. O campo de memória do painel **não afeta o container**.

## Manutenção agendada (restart 4x/dia)

Restart **05:00, 11:00, 17:00 e 23:00** (6h exatos — 4x/dia, mais oportunidades de checar/atualizar mods) via systemd timer **`hl-zomboid-restart.timer`** (4× `OnCalendar`, `Persistent=true`):

```ini
# /etc/systemd/system/hl-zomboid-restart.timer
[Timer]
OnCalendar=*-*-* 05:00:00
OnCalendar=*-*-* 11:00:00
OnCalendar=*-*-* 17:00:00
OnCalendar=*-*-* 23:00:00
Persistent=true
```

> **Fuso (07/08/2026):** o host kavure está em **`America/Sao_Paulo`** — o timer dispara em horário de Brasília. Antes disso o host estava em **UTC** e os restarts rodavam 3h mais cedo (04:00/16:00 BRT), o que parecia "restart perdido" às 19h. O `zomboid-backup` (05:15) também segue o fuso.

**Efeitos:**
- **Mods atualizados:** cada restart re-executa o entry.sh → o PZ re-baixa/atualiza Workshop items no startup.
- **Mundo fresco + RAM:** reinicia o heap e limpa o estado acumulado.
- **Aviso aos players:** ~20s antes, um `servermsg` (banner) avisa `"[SERVER] Reinício em ~20s - servidor fica fora ~1 min para salvar o mundo e atualizar os mods"` (⚠️ sempre com **aspas** — sem aspas o PZ mostra só o primeiro token; fix 10/08/2026). Mesmo padrão em `zomboid-stop` (10s) e `zomboid-update`.
- **Respeita players (10/08/2026):** o `hl-zomboid-restart.service` roda com `Environment=RESPECT_PLAYERS=1` — se houver player online no horário, o restart é **pulado** ("players online - restart ADIADO"). Contagem via helper `zomboid-playercount` (+ sudoers NOPASSWD, lê `performance_history.playerCount` do painel, ~1 min de atraso).
- **Seguro:** `PauseEmpty=true` já pausa o mundo sem players; o `zomboid-restart` faz `save` RCON antes.
- **Build do jogo não muda** no restart normal (só com `zomboid-update`/`FORCEUPDATE` **ou** quando o watchtower puxa imagem nova — ver abaixo).

## Auto-update de imagens (watchtower)

> Desde **07/08/2026** o watchtower (`/srv/data/ops/`) checa imagens **diariamente às 03:00 (BRT)** e atualiza **todos** os containers — **incluindo `pz-server`** (decisão do usuário: servidor sempre atualizado).

- Quando a imagem `danixu86/project-zomboid-dedicated-server` tiver build novo, o container é recriado **sem save RCON** (stop-timeout 30s) — o mundo fica protegido por autosave + backup do painel (00:00) + off-box (05:15).
- O `STEAMAPPBRANCH=stable` do `.env` é respeitado → mesmo com imagem nova, o build instalado é o **stable**, não unstable.
- O `.env` **é relido** na recriação do container (diferente de `docker compose restart`), e o volume `pz-dedicated/` persiste (flags ZGC no `ProjectZomboid64.json` não são apagadas pelo watchtower).

## zram (swap comprimido em RAM)

Kavure usa **zram** como único swap (sem swapfile lento):

| Item | Valor |
|---|---|
| Dispositivo | `/dev/zram0` (zram-tools) |
| Tamanho | 11.5 GB (**100% da RAM** física) |
| Algoritmo | `zstd` |
| Prioridade | 100 |
| Config | `/etc/default/zramswap` (`ALGO=zstd`, `PERCENT=100`, `PRIORITY=100`) |
| Serviço | `zramswap.service` (enabled) |

- O `/swap.img` (4 GB em disco) foi **removido** (swapoff + fstab + delete) em 06/08/2026 — decidido p/ não usar swap lento em disco.
- O zram é comprimido: 11.5 GB de swap físico ocupam menos RAM de verdade (compressão zstd).

## Migração (concluída 06/08/2026)

1. ✅ Backup de segurança em psicopompo `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/`
2. ✅ Servidor local parado (`zomboid.service` inactive — world consistente)
3. ✅ `rsync -aHAX` do `Zomboid/` → `data/` e do `workshop/` → `workshop-mods/`
4. ✅ **Verificação de integridade:** `rsync -n --checksum` → 0 diferenças
5. ✅ Container `pz-server` up — **`SERVER STARTED`**, mundo carregado (`isNewGame=false`), portas 16261/16262/27015
6. ✅ RCON habilitado + **corrigido no painel** (`rconHost=pz-server`)
7. ✅ **PanelBridge ativo** (`PanelBridge.lua` instalado, `Mod connected`)
8. ✅ Zomboid Control Panel configurado (auto-scan) + autobackup ativado
9. ✅ Scripts de operação `zomboid-{start,stop,restart,status,update}` + `zomboid-save`
10. ✅ **Ajustes pós-migração (06/08):** `STEAMAPPBRANCH=stable` (prevenir upgrade p/ unstable), `MIN_MEMORY=1024m` (heap dinâmico), `zomboid-restart` gracioso (RCON save), timer restart (desde 07/08: **4x/dia** 05/11/17/23, `hl-zomboid-restart.timer`) + **backup off-box 01:15** (`zomboid-backup`), **zram 100% RAM** (swapfile removido), **flags ZGC** (`ZUncommit`, `ZUncommitDelay=60`, `SoftMaxHeapSize=4g`), build `42.20.2` em paridade com o original

### Players após a migração

- **Nada se perde:** personagens, inventário, base, `players.db` (contas e **permissões de admin**), config — tudo migrado com checksum 0 diferenças.
- **O que os players precisam fazer (só):** aceitar o kavure no Tailscale + atualizar o IP do servidor no jogo para `100.124.146.77` (ou achar pelo browser).
- **Admins:** status vinculado à conta no `players.db` (migrado) — **continuam admins** sem reconfiguração.
- **Limpeza do psicopompo:** pode apagar o `zomboid.service`/serverfiles **mantendo o backup** `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/` + o espelho `daily/` como rede de segurança.

## Backup

**Padrão de nomenclatura (AGENTS.md):** `/mnt/BACKUP/{servico}-server-{host}/` → `zomboid-server-kavure/`.

- **Off-box (principal):** **`zomboid-backup`** (timer **05:15** no kavure, `hl-zomboid-backup.timer`) espelha os zips do painel → **NAS via NFS**: `/srv/data/zomboid/offbox/` = psicopompo `/mnt/BACKUP/zomboid-server-kavure/` (mount NFSv4 via `autofs`/systemd — ver [`network/nfs`](../../network/nfs.md)).
  - ⚠️ **Checagem de montagem NFS:** no kavure o ponto `/srv/data/zomboid/offbox` usa `autofs`. `findmnt -n -o FSTYPE` retorna `autofs` e `nfs4`. Scripts devem usar `findmnt -n -o FSTYPE "$MNT" | grep -q "nfs"` para evitar falso-positivo de desmontado e erro de permissão ao tentar `mount` manual sem root.
  - `rsync -a --delete` (local → NFS) = **espelho real**: novos zips chegam, mais antigos caem (retenção herdada = 7).
  - **Failsafe (07/08/2026):** reachability check (TCP 2049) → **fail-fast** se o NAS estiver off; **3 tentativas** com backoff 2 min; `timeout` (rsync 15 min / service 30 min) p/ nunca pendurar; **ntfy** (`/backup`) no fail final; erros logados em `/var/log/zomboid-backup.log`.
  - Protege contra perda total do disco do kavure.
- **Antes de updates:** `zomboid-update` faz backup comprimido automático do save via `tar` + `zstd -3 -T0` (~15s) → `offbox/archive/pre-update-<data>.tar.zst` (NFS).
- **Backup do painel (autobackup):** **diário à meia-noite** (`backupSchedule: 0 0 * * *`), **retenção 7** (`backupMaxCount: 7`), local `/srv/data/zomboid/data/backups/*.zip`.
  - ⚠️ É **local** (mesmo disco do servidor) → é proteção contra *erro humano/rollback*, não contra *falha de disco*. A proteção real de disco é o off-box.
  - Nota: `backups/` também contém `startup/` (snapshot completo a cada boot, ~921 MB × 5 rotativo) e `version/` (configs) — espelhados junto no off-box.
- **Snapshot pré-migração:** `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/` (1.2G) — arquivado, manter.
- Saves ficam em `/srv/data/zomboid/data/Saves/Multiplayer/pzserver`

## Decisões

### Sem painel web de controle do container (07/08/2026)

Avaliado criar um painel web (`zomboid-ctl`) com botões para ligar/desligar/reiniciar/atualizar o container — em Rust + systemd, Portainer, ou container dedicado. **REJEITADA** (canhão para matar mosca).

- O controle real já existe: scripts `zomboid-{start,stop,restart,update,save,status}` (SSH) + restart agendado (4x/dia: 05:00/11:00/17:00/23:00) + **Zomboid Control Panel** (RCON, players, mods, backup, scheduler de saves/broadcast).
- Único gap real do painel: **não faz start/stop do container** (falso "stopped" — ver "Limitações da Arquitetura") — decisão: aceitar, controlando via scripts/SSH.
- Custo de uma UI extra: manter código/imagem/unit + token + superfície de segurança — para repetir o que o timer já faz.
- Se no futuro precisar de controle web, avaliar primeiro opções simples (Portainer genérico ou scheduler do painel) antes de construir UI própria.

## Observações

- **Warning `tsarslib` (não-bloqueante):** o log mostra `PZXmlParserException: FileNotFoundException` de um XML de animação ausente do mod `tsarslib` (`mods/tsarslib/common/media/animsets/...`). Não impede o servidor de subir (`SERVER STARTED` OK) — é um mod que referencia anims não baixadas/desatualizadas. Monitorar se causar problema.

- **Soft-lock em 15/08/2026 (resolvido com restart):** servidor travou às 21:35:55 UTC (log parou; RCON aceitava TCP mas abandonava o handshake de auth → painel mostrava "host unreachable"/"connection closed"). Processo Java vivo mas sem processar (soft-lock), sem OOM/hs_err. **Causa provável: bug vanilla do jogo** — ao construir/reparar moldura de parede (`MOWoodenWallFrame.lua`, arquivo base `media/lua/server/Map/MapObjects/`, não sobrescrito por mod), o servidor dispara 43× `replacing isoObject` + 206× `ERROR: IsoThumpable not found on square` (conhecido em MP dedicado). Não foi causado pelos 39 mods KI5 novos (que estavam ativos). Recuperação: `zomboid-restart` (RCON falha por timeout — ok, mundo salvo). Boot novo sem erros, RCON/painel OK. Se repetir, testar subir sem os 39 mods novos para isolar; mitigação para o bug: evitar reconstruir molduras de parede em MP.

- **"Joining Game" infinito / Build Mismatch (resolvido 18/08/2026):**
  - **Sintoma:** Jogador fica travado indefinidamente na tela *"Joining game"*. No log do cliente (`console.txt`), aparece `java.nio.BufferUnderflowException` em `ChunkNotReadyPacket.parse`.
  - **Causa Raiz:** Mismatch entre a versão/build dos binários Java do cliente Steam (`psicopompo` na 42.20.3) e os arquivos do servidor no volume montado (`kavure` na 42.20.2). As permissões `root:root` do bind mount `/srv/data/zomboid/pz-dedicated/` impediam a atualização direta e a variável `ADMINPASSWORD` vazia no `.env` causava `NoSuchElementException` no `entry.sh`.
  - **Resolução:**
    1. Garantir `ADMINPASSWORD=adminpz123` e `STEAMAPPBRANCH=public` (ou `stable`) em `/srv/data/zomboid/.env`.
    2. Rodar `zomboid-update` ou atualizar os binários (`projectzomboid.jar`) com permissão adequada.
    3. Validar checksum MD5 entre cliente e servidor (`md5sum projectzomboid.jar`).

## See also
- [[kavure]] — Servidor de destino
- [[zomboid-control-panel]] — Painel web de administração
- [[kavure-migration-plan]] — Plano de migração

