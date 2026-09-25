---
tags: [homelab, backup, ritual, checklist]
---

# Backup & Verification Rituals

> "A backup that was never restored does not exist." — golden rule.
> The goal: detect failure BEFORE you need it.

## Standard window (05:00–06:00 BRT / 08:00 UTC on the VPS)

Documented in `config-backup.md`. To CHANGE the time: edit `/etc/systemd/system/hl-*.timer` on the corresponding host and update this doc. The VPS (ybytu/ybyra) run at **08:00 UTC** (= 05:00 BRT) — always align by BRT.

## Daily (automatic)

- [x] 03:00 sumaenima-backup (sentinel sae-core, kavure) → ntfy `/backup`
- [x] 05:00 config-backup (5 hosts) → ntfy `/backup`
- [x] 05:15 zomboid-backup
- [x] 05:20 agentic-ai-backup → `/mnt/BACKUP/agentic-ai-server-psicopompo`
- [x] 05:40 restic (configs + agentic-ai; retention 14d/8s/6m)
- [x] 05:55 etckeeper-push + configs-git-push (GitHub `mnemocine`)

**How to know it ran:** ntfy notification; health files in `/srv/health/` (recent mtime); **monitored automatically since 28/08** — Grafana (the `BackupNotRun` alert) reads the health files via the textfile collector (`homelab_backup_last_ok_seconds`), see [`services/monitoring.md`](../services/monitoring.md).
**Source of truth for the schedules:** [`automations/schedules.json`](../automations/schedules.json) + [tables](../automations/README.md) — always keep them updated (canonical rule).

## Weekly

- [ ] **restic check** (Sun 06:00, automatic via timer `hl-restic-configs-check.timer`) — validates repo integrity.
- [ ] Check the health files: `ls -la /srv/health/` (all `< 24h`).

## Monthly (drill)

- [x] **Docker prune** (day 01, 04:00, automatic via `docker-prune.timer` on psicopompo) — prunes the build cache + dangling images; complements the 30GB GC in `daemon.json`. See [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md).

1. **Actually restore** (a check alone does not count):
   - Mirror: copy 1 config from `/mnt/BACKUP/configs-homelab/{host}/` to `/tmp` and check it.
   - Restic: `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password restore latest --target /tmp/restic-test` + check 1 file.
   - Etckeeper: `git -C /tmp/restic-test/... clone /srv/backup-gitrepos/etckeeper-{host}.git` + check `/etc/fstab`.
2. **Project restore drill**: pick 1 service (e.g.: bring a compose back up from the mirror) and document the result.
3. **Snapper**: `sudo snapper -c nvme list` (are this week's snapshots OK?); check space with `df -h`. ⚠️ Snapshots **pin extents** — space from deleted Docker data is only freed once you delete the old snapshots (`snapper -c nvme delete --sync <n>`). See [`snapshots-psicopompo.md`](snapshots-psicopompo.md).

## Quarterly / on demand

- [ ] `restic check --read-data` (reads the whole repo) — I/O heavy, schedule off-peak.
- [ ] Review the `EXCLUDES` in the confs (nothing secret slipping through: `git -C /mnt/BACKUP/configs-homelab ls-files | grep -iE 'shadow|\.env$|passwd'`).
- [ ] Test an end-to-end restore of Zomboid/Minecraft/sae-core (Borg).
- [ ] Check for snapper orphans: `btrfs subvolume list -o /mnt/NVME_PCI/.snapshots`.

## Out of scope (owner's decisions)

- **No encryption** on the central backup (key trauma) — secrets stay in the sops store.
- **Off-site**: ✅ **active** (09/08) — Google Drive 5TB via rclone (`gdrive:BACKUP MNEMOCINE`, mirror of `/mnt/BACKUP`, no encryption). cronie scheduler enabled on 10/08 (see [`services/rclone.md`](../services/rclone.md)).
- **etckeeper**: NAS only (it does not go to GitHub).
- **age key** (`age-keys-backup.txt`) and plaintext `secrets.env`: they do NOT go to the NAS — keep them off-host (KeePassXC/flash drive).

## 28/08 Incident — backups silently stuck (detected by monitoring)

When the health-file monitoring came up (textfile collector), **3 backups had been broken with nobody noticing**:

| Backup | Symptom | Cause | Fix |
|---|---|---|---|
| `restic-configs` (psicopompo) | health stuck for 19 days + daily ntfy "restic FAILED" | `systemd` without `$HOME`/`$XDG_CACHE_HOME` → restic cannot find the cache | `Environment=HOME=/root XDG_CACHE_HOME=/root/.cache` in the `hl-restic-configs-backup.service` unit |
| `rclone-gdrive` (off-site) | health stuck for 4 days | `--max-delete 200` exceeded by the churn of orphan `.git` in `configs-homelab` | exclude `/configs-homelab/**/.git/**` + `--max-delete 5000` (the `--backup-dir` already moves to `_deleted/` = real protection) |
| `config-backup` ybytu/ybyra (VPS) | health stuck for 7 days | NFS `Stale file handle` (old handle after the server re-exported) | remount `/srv/backup-configs` (`umount -l` + `mount`) on the VPS |
| `sumaenima-backup` (kavure) | the container's internal crond broke (**silently** — it would have stalled on the next 03:00) | the image started running as `appuser` (v2.22.0) and crond cannot read `/etc/crontabs/root` (`Permission denied`) | move scheduling to the host: `hl-sumaenima-backup.timer` (03:00) → `/usr/local/bin/sumaenima-backup` → sentinel via `docker exec`; crond removed from the image (29/08) |

**Lesson:** the Grafana `BackupNotRun` alert (>26h) now covers ALL backups (all hosts) — a recurrence would be detected in under 1 day. Legacy health files (`config-backup-Kuaray`, `config-backup-ybytu-vnic`) removed. **29/08:** the sentinel health file was added (`sumaenima-backup-last-ok`) and is covered by the same alert.

## How to change something

1. Edit the corresponding doc (`config-backup.md`, `snapshots-psicopompo.md`) FIRST.
2. Apply the change (cron/script/conf).
3. Validate (dry-run + a real run) and tick it off in the doc.
