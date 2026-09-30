---
tags: [homelab, guia, zomboid, migracao, handoff, psicopompo]
---

# Handoff — Zomboid no psicopompo (migrado p/ kavure) — **CONCLUÍDO**

> **Data:** 06/08/2026 · **Motivo:** servidor PZ migrado para o kavure (Docker). Infra local no psicopompo **desligada e dados destruídos** (com backup validado).

## Contexto

- O servidor de Project Zomboid original rodava no **psicopompo** via LinuxGSM (user `pzserver`).
- Foi migrado para o **kavure** (Docker — `danixu86/project-zomboid-dedicated-server`), doc: [`project-zomboid.md`](project-zomboid.md).
- Os **dados (jogo) ficam quietos** (não foram apagados) — decisão do usuário. Só os **processos, serviços, timers, crons, user e permissões** foram desligados.

## O que foi desligado (06/08/2026)

### 1. Serviço principal
| Item | Estado |
|---|---|
| `zomboid.service` | `stop` + `disable` → **inactive / disabled** |
| Descrição | `Project Zomboid Server - VaiMorreSim [PSICOPOMPO] (LinuxGSM)` — user `pzserver`, `WorkingDirectory=/home/pzserver/server`, `ExecStart=/home/pzserver/server/pzserver start` |

### 2. Timers systemd
| Timer | Antes | Agora |
|---|---|---|
| `pzserver-monitor.timer` (a cada 5min) | enabled | **disabled** + parado |
| `pzserver-backup.timer` (04:00 diário) | enabled | **disabled** + parado |
| `pzserver-restart.timer` (05:00 diário) | enabled | **disabled** + parado |
| `pzserver-update.timer` (a cada 30min) | disabled | disabled (já era) |
| `pzserver-update-lgsm.timer` (dom 00:00) | disabled | disabled (já era) |

Os `.service` (oneshot: `pzserver-backup`, `pzserver-monitor`, `pzserver-restart`, `pzserver-update`, `pzserver-update-lgsm`) são `static` — disparados pelos timers; com timers off, nunca rodam.

### 3. Scripts auxiliares
- `/usr/local/libexec/pzserver-backup` — backup diário (para + restart via LinuxGSM)
- `/usr/local/libexec/pzserver-monitor-health` — monitora tmux session, reinicia se cair
- `/usr/local/libexec/pzserver-restart` — restart diário

> **Removidos na destruição** (06/08/2026).

### 4. User e permissões
| Item | Estado |
|---|---|
| user `pzserver` (uid 888) | shell alterado para **`/usr/sbin/nologin`** + senha bloqueada (`passwd -l`), depois **`userdel -r` (removido)** |
| `/etc/sudoers.d/pzserver` | **removido** (era `edu ALL=(pzserver) NOPASSWD: /home/pzserver/server/pzserver *`) |
| `sudoers` validado | `visudo -c` → **parsed OK** |

### 5. Processos residuais
- Um `ProjectZomboid64` rodando como `edu` (teste do usuário em 02:54) foi morto. Confirmado: **nenhum processo do pzserver/ProjectZomboid64** restante; porta `16261` fechada.

## O que foi removido na destruição (06/08/2026 — backups validados antes)

- ✅ `/home/pzserver/` (5.7G — dados de jogo, config) + user `pzserver`
- ✅ `/mnt/NVME_PCI/zomboidserver [knox-county]/` (22G — LinuxGSM + serverfiles + `lgsm/backup` 13G)
- ✅ Unidades `.service`/`.timer` (11) + scripts `libexec` (3) + lock `/run/pzserver-maintenance.lock` + tmux `/tmp/tmux-888/`
- ✅ `/home/edu/Zomboid` (artefato de teste do jogo local)

## Backup off-box (importante — NÃO quebrar)

- O **kavure** continua enviando backup para cá: `zomboid-update` (no kavure) faz `rsync -aHAX /srv/data/zomboid/data/ → edu@100.82.51.112:/mnt/BACKUP/zomboid-server-kavure/archive/pre-update-<data>/`.
- **`zomboid-backup`** (novo, cron 01:15 no kavure) espelha os zips do painel → `daily/` (rsync `--delete`, retenção herdada = 7). Usa **`edu@`** → não depende de user/service removido. ✅
- Backups preservados: `/mnt/BACKUP/zomboid-server-kavure/daily/` (5.6G, espelho automático 01:15) + `archive/migration-20260805/` (1.2G) — **manter**.

## Verificação final

```bash
systemctl list-timers --all | grep pzserver   # (vazio)
pgrep -af ProjectZomboid64               # (vazio)
ss -lunpt | grep 16261                   # (vazio)
getent passwd pzserver                   # (user removido)
```

## Pendências — CONCLUÍDAS (06/08/2026)

**Destruição definitiva executada** (backups validados antes — ver seção Backup):

1. ✅ **Dados do jogo removidos** — `/home/pzserver` (5.7G) + `/mnt/NVME_PCI/zomboidserver [knox-county]` (22G, incl. `lgsm/backup` 13G de snapshots antigos)
2. ✅ **Units systemd removidas** — `zomboid.service` + 5 `pzserver-*.{service,timer}` + `systemctl daemon-reload`
3. ✅ **User `pzserver` removido** (`userdel -r`, uid 888) + `/home/pzserver`
4. ✅ **Scripts `libexec` removidos** (`pzserver-backup`, `pzserver-monitor-health`, `pzserver-restart`)
5. ✅ **Resíduos removidos** — `/run/pzserver-maintenance.lock`, tmux socket `/tmp/tmux-888/`, `/home/edu/Zomboid` (artefato de teste)
6. ✅ **`verify_infra.py` removido** do repo (e refs em SECURITY/auto-sync/health-endpoints)

**Backups preservados antes da destruição:**
- `/mnt/BACKUP/zomboid-server-kavure/daily/` (5.6G) — espelho do painel (world backup + startup + version), **validado (`zip OK`)**, automático via `zomboid-backup` (cron 01:15 no kavure)
- `/mnt/BACKUP/zomboid-server-kavure/archive/migration-20260805/` (1.2G) — snapshot pré-migração
- kavure segue servindo (`pz-server: Up`, painel healthy)

**Liberação de espaço:** `/mnt/NVME_PCI` 810G → 825G livres (~15G de dados; o resto estava no `/` e `/home`).

## See also
- [[project-zomboid]] — servidor atual no kavure (Docker)
- [[zomboid-control-panel]] — painel de administração
- [[kavure-migration-plan]] — plano de migração
- [[psicopompo]] — servidor de origem
