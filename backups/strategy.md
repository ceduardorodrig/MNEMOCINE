---
tags: [homelab, backup, storage]
---

# Estratégia de Backup

## Estado Atual (09/08/2026)

| Servidor | Backup ativo | Ferramenta | Destino |
|---|---|---|---|
| psicopompo | ✅ **configs + snapshots + histórico** | `config-backup` + snapper (nvme/backup/hdd) + restic + etckeeper | `/mnt/BACKUP/` (NAS próprio) |
| ybytu | ✅ configs (05:00→08:00 UTC) | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/ybytu` |
| ybyra | ✅ configs | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/ybyra` |
| kuaray | ✅ configs (reconstruídas 08/08) | `config-backup` + etckeeper | `/mnt/BACKUP/configs-homelab/kuaray` |
| kavure | ✅ jogos (off-box) + configs + **n8n (28/08)** + **monitoring (13/09)** | NFS off-box (zomboid/minecraft/valheim/sumaenima borg) + `config-backup` + etckeeper | `/mnt/BACKUP/*-server-kavure` + `/configs-homelab/kavure` + `/mnt/BACKUP/n8n-server-kavure` + `/mnt/BACKUP/monitoring-server-kavure` |

> **Backup canônico de configs** (criado 09/08/2026): todos os hosts espelham as configs no NAS
> (`/mnt/BACKUP/configs-homelab/`) via `config-backup` (janela 05:00–06:00), versionado com
> **git → GitHub privado `mnemocine`**, **restic** (14d/8s/6m) e **snapper**. Ver [`config-backup.md`](config-backup.md).
> O vault `agentic-ai` tem cópia noturna em `/mnt/BACKUP/agentic-ai-server-psicopompo`.

## Padrão off-box via NFS (NAS psicopompo) — padronizado 07/08/2026

**Arquitetura:** psicopompo é o **NAS da tailnet (NFSv4)**. Serviços com dados críticos **não fazem backup via SSH** — escrevem **direto num mount NFS** (espelho local → NAS). Sem SSH → sem o `check` de 12h do Tailscale SSH (footgun que derrubou o backup do Zomboid em 07/08).

### Componentes do padrão

| Camada | Padrão |
|---|---|
| **Pasta no NAS** | `/mnt/BACKUP/{servico}-server-{host}/` (ex.: `zomboid-server-kavure/`, `sumaenima-server-kavure/`) |
| **Export (NFSv4)** | `/etc/exports` do psicopompo: `rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000`, restrito ao IP tailnet do cliente |
| **Mount no cliente** | `/srv/data/{servico}/offbox` — fstab `nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,nofail` |
| **Cópia** | `rsync -a --delete <fonte>/ <offbox>/daily/` (espelho real; `archive/` p/ snapshots pré-update) |
| **Failsafe** | reachability TCP 2049 → **fail-fast**; **retry 3×**/backoff 2min; `timeout` (rsync 15min / cron 30min); **log de erro**; **ntfy** (`/backup`) no fail final |
| **Agendamento** | cron `15 1 * * * timeout 1800 /usr/local/bin/zomboid-backup` |

### Referências de implementação
- **Zomboid:** `/usr/local/bin/zomboid-backup` (script failsafe de referência) — ver [`services/zomboid/project-zomboid.md`](../services/zomboid/project-zomboid.md).
- **Sumænimá:** mount `/srv/data/sumaenimahub/backup` → `/mnt/BACKUP/sumaenima-server-kavure`.

### Como adicionar um novo serviço ao padrão
1. Criar a pasta no NAS + linha no `/etc/exports` (psicopompo) + `exportfs -arv` + liberar `2049/111` (ufw) pro IP do cliente.
2. No cliente: pasta `offbox` + entrada no `/etc/fstab` (mesmas opções) + `mount`.
3. Adaptar o script failsafe (base: `zomboid-backup`) ao serviço (fonte + destino).
4. Cron com `timeout` + ntfy no tópico `backup` em falha.
5. Documentar em `backups/strategy.md` + [`network/nfs.md`](../network/nfs.md) + a doc do serviço.

## O que precisa de backup

### Psicopompo
- Volumes Docker (Crafty — **até migrar** p/ kavure; StênioBOT/Umami já migrados para o kavure)
- Configs do Docker (compose files, env vars)
- Vault Obsidian (já sincronizado via Syncthing)
- **Desktop configs (21/09/2026):** `~/.config/hypr` (15 .lua + scripts), `~/.config/noctalia` (config.toml + merged-config.toml via `noctalia config export`), `~/.config/environment.d` (gaming/kwin/env), `~/.config/steam-launch-options` (profiles/games.toml + backups VDF), `~/.local/state/noctalia` (settings.toml = overrides GUI). Espelhados pelo `config-backup` → `/mnt/BACKUP/configs-homelab/psicopompo/` (git + restic + snapper). Estado Noctalia re-fetchable (plugins/community/clipboard) excluído do espelho.

### Ybytu
- Config do AdGuard Home (`/opt/adguardhome/conf/`)
- DB do Filebrowser (`/home/ubuntu/filebrowser.db`)
- Config do Homepage (volumes Docker)

### Ybyra
- Nenhum serviço crítico ainda (servidor novo, futuro SPA host)

### Kuaray
- Bibliotecas multimídia (Navidrome, Lidarr, etc.) — mídia consolidada no psicopompo desde 06/08 (`/mnt/BACKUP/media/`)
- DB do Home Assistant
- MQTT config
- **Duplicati removido (06/08/2026)** — o job cobria apenas `/DATA/AppData`; backup de configs será estruturado futuramente.

### Kavure
- **Project Zomboid (ativo):**
  - Off-box diário (05:15, `zomboid-backup` via `hl-zomboid-backup.timer`): espelha os zips do painel via **NFS** (`/srv/data/zomboid/offbox/daily/`) → psicopompo `/mnt/BACKUP/zomboid-server-kavure/daily/` (rsync `--delete` local→NFS; failsafe/retry/ntfy)
  - Pré-update (`zomboid-update`): snapshot do save → `offbox/archive/pre-update-<data>/` (NFS)
  - Snapshot pré-migração: `archive/migration-20260805/` (1.2G) — manter
  - Fonte local: `/srv/data/zomboid/data/backups/` (autobackup do painel, retenção 7)
- **Valheim (ativo desde 09/09/2026; backup corrigido 13/09):**
  - Off-box (05:30, `valheim-backup` via `hl-valheim-backup.timer`): espelha `saves/worlds_local/` (mundo ativo `Fimbulvetr` + auto-backups nativos do jogo) → NFS psicopompo `/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`
  - **Correção 13/09:** script apontava p/ `config/backups/` (não existe) → off-box nunca rodou. Corrigido p/ `saves/worlds_local/` + adicionado mount `./backups:/home/steam/backups` no compose (AUTO_BACKUP do Odin passou a persistir). Health file `/srv/health/valheim-backup-last-ok`.
  - Container: `AUTO_BACKUP` a cada 30 min → `./backups/` (retenção 7 dias) + auto-backup nativo do jogo em `saves/worlds_local/Fimbulvetr_backup_auto-*`
- Sumænimá (sae-core) — ✅ **ativo desde 07/08/2026**: sentinel (Borg) no kavure → NFS `/mnt/BACKUP/sumaenima-server-kavure/` (dumps SQL stenio_db + umami + `.env`). **Scheduling (29/08/2026):** trocado de crond-in-container (quebrado desde v2.22.0 — imagem roda como `appuser` e o crond não lia `/etc/crontabs/root`) para o padrão do homelab: `hl-sumaenima-backup.timer` (03:00, `Persistent=true`) → `/usr/local/bin/sumaenima-backup` → `docker exec` sentinel. Health file `/srv/health/sumaenima-backup-last-ok` (alerta `BackupNotRun` coberto automaticamente — glob `/srv/health/*-last-ok`). Imagem do sentinel sem crond (29/08).
- **Monitoring (ativo desde 13/09/2026):**
  - Off-box (05:15, `monitoring-backup` via `hl-monitoring-backup.timer`): snapshot do TSDB do Prometheus (`POST /api/v1/admin/tsdb/snapshot` — requer `--web.enable-admin-api`) + rsync `--delete` de Loki/Grafana → NFS psicopompo `/mnt/BACKUP/monitoring-server-kavure/daily/` (Prometheus em `daily/prometheus/`, Loki `daily/loki/`, Grafana `daily/grafana/`)
  - **Storage ativo fica LOCAL no kavure** (volume Docker) — a doc oficial do Prometheus **NÃO suporta TSDB em NFS** (corrupção irreversível; ver issue #5342). O NFS é só para o backup diário.
  - Health file `/srv/health/monitoring-backup-last-ok` (alerta `BackupNotRun` cobre automaticamente).
- **Cobertura geral do kavure (revisado 13/09):** o `config-backup` espelha **todo o `/srv/data`** no NAS (git + restic) — cobre configs de Home Assistant, Pihole, Comet, Searxng, AIOStreams (exceto `anime-database`, reconstruível), Calibre, Navidrome, monitoring, n8n, Valheim. Exclusões deliberadas: `zomboid/data`, `minecraft`, `sumaenimahub` dados (têm backup próprio/off-box). **Miracena:** `hl-miracena-backup.timer` ativado 13/09 (05:35) — estava desativado (health file era manual).

## Recomendação

### Feito (09/08/2026)
1. ✅ **Backup canônico de configs** no NAS (config-backup, 5 hosts) — `config-backup.md`
2. ✅ **Snapshots btrfs** de todos os discos do psicopompo (snapper: root/nvme/backup/hdd) — `snapshots-psicopompo.md`
3. ✅ **restic** histórico dos configs+vault (retenção 14d/8s/6m, check semanal) — sem criptografia (decisão do dono)
4. ✅ **etckeeper** `/etc` versionado em todos os hosts (git → bare repos no NAS)
5. ✅ **Git/GitHub** privado `mnemocine` (espelho dos configs)
6. ✅ **Segredos** centralizados no store sops/age (ver `guides/secrets-centralizados.md`); removidos em claro do vault

### Pendente
1. **Off-site (3-2-1)**: Google Drive 5TB via rclone (configs + agentic-ai + repos) ou Backblaze B2. Sem criptografia no destino (decisão do dono) — revisitar trade-off.
2. **Drill de restore mensal** e `restic check --read-data` trimestral — ver `backup-rituals.md`
3. **Cópia off-host da chave age** (`age-keys-backup.txt`) e `secrets.env` → KeePassXC/pendrive (NUNCA no NAS plaintext)
4. **Push monitor no uptime-kuma** para os health files dos backups
5. **Playbook de recovery**: testar restore de ponta a ponta (Zomboid, Minecraft, sae-core, configs)

## Comandos Úteis

```bash
# Backup de volume Docker
docker run --rm -v steniobot_valkey:/volume -v /backup:/backup alpine \
  tar czf /backup/valkey-$(date +%F).tar.gz -C /volume .

# Restore de volume Docker
docker run --rm -v steniobot_valkey:/volume -v /backup:/backup alpine \
  tar xzf /backup/valkey-2026-06-01.tar.gz -C /volume
```
