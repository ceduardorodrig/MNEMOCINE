---
tags: [homelab, backup, ritual, checklist]
---

# Rituais de Backup & Verificação

> "Backup que nunca foi restaurado não existe." — regra de ouro.
> O objetivo: detectar falha ANTES de precisar.

## Janela padrão (05:00–06:00 BRT / 08:00 UTC nos VPS)

Documentado em `config-backup.md`. Para MUDAR o horário: editar `/etc/systemd/system/hl-*.timer` no host correspondente e atualizar este doc. Os VPS (ybytu/ybyra) rodam **08:00 UTC** (= 05:00 BRT) — sempre alinhar pelo BRT.

## Diário (automático)

- [x] 03:00 sumaenima-backup (sentinel sae-core, kavure) → ntfy `/backup`
- [x] 05:00 config-backup (5 hosts) → ntfy `/backup`
- [x] 05:15 zomboid-backup
- [x] 05:20 agentic-ai-backup → `/mnt/BACKUP/agentic-ai-server-psicopompo`
- [x] 05:40 restic (configs + agentic-ai; retenção 14d/8s/6m)
- [x] 05:55 etckeeper-push + configs-git-push (GitHub `mnemocine`)

**Como saber que rodou:** notificação ntfy; health files em `/srv/health/` (mtime recente); **monitorado automaticamente desde 28/08** — o Grafana (alerta `BackupNotRun`) usa os health files via textfile collector (`homelab_backup_last_ok_seconds`), ver [`services/monitoring.md`](../services/monitoring.md).
**Fonte da verdade dos agendamentos:** [`automations/schedules.json`](../automations/schedules.json) + [tabelas](../automations/README.md) — manter sempre atualizados (regra canônica).

## Semanal

- [ ] **restic check** (dom 06:00, automático via timer `hl-restic-configs-check.timer`) — valida integridade do repo.
- [ ] Conferir health files: `ls -la /srv/health/` (todos `< 24h`).

## Mensal (drill)

- [x] **Docker prune** (dia 01, 04:00, automático via `docker-prune.timer` no psicopompo) — poda cache de build + imagens pendentes; complemento do GC de 30GB do `daemon.json`. Ver [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md).

1. **Restaurar de verdade** (não vale só o check):
   - Espelho: copiar 1 config de `/mnt/BACKUP/configs-homelab/{host}/` para `/tmp` e conferir.
   - Restic: `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password restore latest --target /tmp/restic-test` + conferir 1 arquivo.
   - Etckeeper: `git -C /tmp/restic-test/... clone /srv/backup-gitrepos/etckeeper-{host}.git` + conferir `/etc/fstab`.
2. **Restore drill do projeto**: escolher 1 serviço (ex: re-subir um compose a partir do espelho) e documentar o resultado.
3. **Snapper**: `sudo snapper -c nvme list` (snapshots da semana OK?); conferir espaço `df -h`. ⚠️ Snapshots **pinnam extents** — espaço de dados Docker deletados só é liberado ao apagar os snapshots antigos (`snapper -c nvme delete --sync <n>`). Ver [`snapshots-psicopompo.md`](snapshots-psicopompo.md).

## Trimestral / sob demanda

- [ ] `restic check --read-data` (lê todo o repo) — caro em I/O, agendar fora do pico.
- [ ] Revisar `EXCLUDES` dos confs (nada de segredo escapando: `git -C /mnt/BACKUP/configs-homelab ls-files | grep -iE 'shadow|\.env$|passwd'`).
- [ ] Testar restore do Zomboid/Minecraft/sae-core (Borg) de ponta a ponta.
- [ ] Verificar órfãos snapper: `btrfs subvolume list -o /mnt/NVME_PCI/.snapshots`.

## Fora de escopo (decisões do dono)

- **Sem criptografia** no backup central (trauma com chaves) — segredos ficam no store sops.
- **Off-site**: ✅ **ativo** (09/08) — Google Drive 5TB via rclone (`gdrive:BACKUP MNEMOCINE`, espelho do `/mnt/BACKUP`, sem criptografia). Scheduler cronie ativado em 10/08 (ver [`services/rclone.md`](../services/rclone.md)).
- **etckeeper**: só NAS (não vai pro GitHub).
- **Chave age** (`age-keys-backup.txt`) e `secrets.env` plaintext: NÃO vão pro NAS — manter off-host (KeePassXC/pendrive).

## Incidente 28/08 — backups parados em silêncio (detectados pelo monitoramento)

Ao subir o monitoramento dos health files (textfile collector), **3 backups estavam quebrados sem ninguém perceber**:

| Backup | Sintoma | Causa | Fix |
|---|---|---|---|
| `restic-configs` (psicopompo) | health 19 dias parado + ntfy "restic FALHOU" diário | `systemd` sem `$HOME`/`$XDG_CACHE_HOME` → restic não acha o cache | `Environment=HOME=/root XDG_CACHE_HOME=/root/.cache` na unit `hl-restic-configs-backup.service` |
| `rclone-gdrive` (off-site) | health 4 dias parado | `--max-delete 200` estourado pelo churn de `.git` órfãos do `configs-homelab` | exclude `/configs-homelab/**/.git/**` + `--max-delete 5000` (o `--backup-dir` já move p/ `_deleted/` = proteção real) |
| `config-backup` ybytu/ybyra (VPS) | health 7 dias parado | NFS `Stale file handle` (handle velho após re-export do servidor) | remontar `/srv/backup-configs` (`umount -l` + `mount`) nos VPS |
| `sumaenima-backup` (kavure) | crond interno do container quebrado (**silencioso** — teria parado no 03:00 seguinte) | imagem passa a rodar como `appuser` (v2.22.0) e crond não lê `/etc/crontabs/root` (`Permission denied`) | mover scheduling p/ host: `hl-sumaenima-backup.timer` (03:00) → `/usr/local/bin/sumaenima-backup` → `docker exec` sentinel; crond removido da imagem (29/08) |

**Lição:** o alerta `BackupNotRun` (>26h) do Grafana agora cobre TODOS os backups (todos os hosts) — recorrência seria detectada em <1 dia. Health files legados (`config-backup-Kuaray`, `config-backup-ybytu-vnic`) removidos. **29/08:** health file do sentinel adicionado (`sumaenima-backup-last-ok`) e coberto pelo mesmo alerta.

## Como mudar algo

1. Editar o doc correspondente (`config-backup.md`, `snapshots-psicopompo.md`) PRIMEIRO.
2. Aplicar a mudança (cron/script/conf).
3. Validar (dry-run + rodada real) e marcar no doc.
