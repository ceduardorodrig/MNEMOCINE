---
tags: [homelab, automation, backup, ritual]
---

# Automações do Homelab — Registro

Fonte da verdade: [`schedules.json`](schedules.json) (JSON). Estas tabelas são a visão humana.
Regra: **todo job novo/alterado/removido = atualizar `schedules.json` e estas tabelas no mesmo passo** (AGENTS.md canônico).

> **Scheduler (10/08/2026):** todos os jobs **customizados** do homelab migraram de cron para **systemd timers** `hl-*.timer` (`Persistent=true` — se a máquina estiver off no horário, o job roda no próximo boot). O **cron nativo** (Ubuntu/Mint) e o **cronie** (psicopompo, mantido p/ uso futuro) seguem ativos apenas p/ jobs do SO (`e2scrub_all`, `sysstat`, `anacron`, `0hourly`). Fonte: `schedules.json` (`type=systemd-timer`) e units em `/etc/systemd/system/hl-*.{service,timer}`.

## Janela de backup (padrão)

- **Local (psicopompo/kavure/kuaray):** 05:00–06:00 BRT (`America/Sao_Paulo`).
- **VPS (ybytu/ybyra):** 08:00 UTC (= 05:00 BRT).

| Hora | Job |
|---|---|
| 05:00 | config-backup (todos os hosts) + zomboid-restart (kavure) |
| 05:15 | zomboid-backup (kavure) + **monitoring-backup (kavure, 13/09)** |
| 05:20 | agentic-ai-backup (psicopompo) |
| 05:25 | n8n-backup (kavure) |
| 05:30 | valheim-backup (kavure) |
| 05:35 | miracena-backup (kavure, timer ativado 13/09) |
| 05:40 | restic-configs-backup (psicopompo) |
| 05:55 | etckeeper-push + configs-git-push |
| dom 06:00 | restic-configs-check |

## Tabela por host

### psicopompo
| Job | Agendamento | Propósito |
|---|---|---|
| config-backup | 05:00 BRT | Espelho das configs no NAS |
| agentic-ai-backup | 05:20 BRT | Cópia do vault |
| restic-configs-backup | 05:40 BRT | Histórico versionado (14d/8s/6m) |
| restic-configs-check | dom 06:00 | Integridade do repo |
| rclone-gdrive-backup | 06:30 BRT | Off-site → Google Drive |
| configs-git-push | 05:55 BRT | Push GitHub `mnemocine` |
| etckeeper-push | 05:55 BRT | Push /etc → NAS |
| **hl-health-metrics** | **a cada 5 min** | Textfile: health files + units systemd (28/08) |
| **hl-container-metrics** | **a cada 2 min** | Textfile: estado dos containers (28/08) |
| **hl-smart-metrics** | **a cada 15 min** | Textfile: SMART dos discos (28/08) |
| snapper-timeline | horário | Snapshots dos discos |
| snapper-cleanup | diário | Cleanup de snapshots |
| snap-pac hooks | a cada pacman | Snapshot pre/post update |
| watchtower | polling 24h | Auto-update |

### kavure
| Job | Agendamento | Propósito |
|---|---|---|
| config-backup | 05:00 BRT | Espelho das configs |
| etckeeper-push | 05:55 BRT | Push /etc |
| zomboid-restart | 05/11/17/23 | Restart gracioso do PZ |
| zomboid-backup | 05:15 BRT | Saves → NFS |
| **monitoring-backup** | **05:15 BRT** | Snapshot Prometheus + Loki/Grafana → NFS (13/09) |
| **n8n-backup** | **05:25 BRT** | Dump Postgres do n8n → NFS (28/08) |
| **valheim-backup** | **05:30 BRT** | Mundo `worlds_local` → NFS (corrigido 13/09) |
| **miracena-backup** | **05:35 BRT** | Dump PG/MariaDB + uploads → NFS (timer ativado 13/09) |
| sae-core_backup (borg) | 03:00 | Dumps SQL → NFS |
| **hl-health-metrics** | **a cada 5 min** | Textfile: health files + units systemd (28/08) |
| **hl-container-metrics** | **a cada 2 min** | Textfile: estado dos containers (28/08) |
| **hl-smart-metrics** | **a cada 15 min** | Textfile: SMART dos discos físicos (28/08) |
| watchtower | 03:00 BRT | Auto-update (único ativo p/ updates) |
| AdvancedBackups | interno | Mundo Minecraft → NFS |
| painel zomboid autobackup | interno | Saves (retenção 7) |

### kuaray
| Job | Agendamento | Propósito |
|---|---|---|
| config-backup | 05:00 BRT | Espelho das configs (reconstruídas 08/08) |
| etckeeper-push | 05:55 BRT | Push /etc |
| timeshift-hourly | 05:00 | Verificação timeshift (SEM snapshots ativos — reavaliar) |
| **hl-health-metrics** | **a cada 5 min** | Textfile: health files + units systemd (28/08) |
| **hl-container-metrics** | **a cada 2 min** | Textfile: estado dos containers (28/08) |
| **hl-smart-metrics** | **a cada 15 min** | Textfile: SMART do HDD (28/08 — pegou pending=37) |
| watchtower | **PAUSADO** | Auto-update (decisão pendente) |

### ybytu (UTC)
| Job | Agendamento | Propósito |
|---|---|---|
| config-backup | 08:00 UTC | Espelho das configs |
| etckeeper-push | 08:55 UTC | Push /etc |
| **hl-health-metrics** | **a cada 5 min** | Textfile: health files + units systemd (28/08) |
| **hl-container-metrics** | **a cada 2 min** | Textfile: estado dos containers (28/08) |
| watchtower | polling 24h | Auto-update |

### ybyra (UTC)
| Job | Agendamento | Propósito |
|---|---|---|
| config-backup | 08:00 UTC | Espelho das configs |
| etckeeper-push | 08:55 UTC | Push /etc |
| **hl-health-metrics** | **a cada 5 min** | Textfile: health files + units systemd (28/08) |
| **hl-container-metrics** | **a cada 2 min** | Textfile: estado dos containers (28/08) |
| watchtower | polling 24h | Auto-update |

## Schema (`schedules.json`)

```json
{
  "id": "exemplo-job",
  "host": "kavure",
  "name": "nome-curto",
  "type": "cron | systemd-timer | hook | docker | swarm-service | docker-internal",
  "schedule_cron": "0 5 * * *",
  "tz": "America/Sao_Paulo | UTC | null",
  "command": "comando completo",
  "purpose": "o que faz",
  "enabled": true,
  "notify": "ntfy /backup | logger | null",
  "health_file": "/srv/health/... | null",
  "doc": "caminho da doc no vault"
}
```

## Runbook — adicionar/alterar/remover um job

1. **Criar/editar o job** (cron, systemd timer, etc.) no host.
2. **Atualizar `schedules.json`** + as tabelas deste README.
3. Atualizar a doc do serviço correspondente (se afetar backup, citar `backups/config-backup.md`).
4. Validar: rodar o job manualmente e conferir health/ntfy.
5. Se mudar a janela de backup: atualizar a tabela "Janela" acima e os `/etc/cron.d/*`.

## OS-default (não gerenciar)

fstrim, logrotate, apt-daily*, sysstat, e2scrub, dpkg-db-backup, man-db, fwupd-refresh, motd-news, mintupdate-automation (kuaray), anacron (kuaray), shadow, plocate, cachyos-rate-mirrors. Listados no JSON como referência; não devem ser alterados pelos agentes.
