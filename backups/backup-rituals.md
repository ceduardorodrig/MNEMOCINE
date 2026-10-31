---
tags: [homelab, backup, ritual, checklist]
pending: [HB-094]
---

# Backup & Verification Rituals

> "A backup that has never been restored does not exist." — Golden operational rule.  
> Primary objective: Detect backup failures BEFORE disaster strikes.

## Standard Backup Window (05:00–06:00 BRT / 08:00 UTC on Cloud VPS)

Documented in `config-backup.md`. To modify schedule times: Edit `/etc/systemd/system/hl-*.timer` on target host and update this document. Cloud VPS nodes (ybytu/ybyra) execute at **08:00 UTC** (= 05:00 BRT) — always synchronize operational windows relative to BRT.

## Daily Rituals (Automated)

- [x] 03:00 `sumaenima-backup` (sentinel sae-core on kavure) → ntfy `/backup`
- [x] 05:00 `config-backup` (all 5 hosts) → ntfy `/backup`
- [x] 05:15 `zomboid-backup` (savegame snapshots → NFS)
- [x] 05:20 `agentic-ai-backup` → `/mnt/BACKUP/agentic-ai-server-psicopompo`
- [x] 05:40 `restic-configs-backup` (configs + agentic-ai; retention: 14d/8w/6m)
- [x] 05:55 `etckeeper-push` + `configs-git-push` (GitHub private mirror `MNEMOCINE-CONFIGS`) — size guard (>95 MB aborts with ntfy `high`) + health stamp (19/10/2026)

**Verification Signals:** Mobile ntfy notifications; mtime freshness on `/srv/health/*` files; **monitored automatically since 28/08** — Grafana (`BackupNotRun` alert) queries health files via node_exporter textfile collector (`homelab_backup_last_ok_seconds`). Rule (read live from Prometheus, 19/10/2026): `(time() - homelab_backup_last_ok_seconds) > 26 * 3600` — it has **no job filter**, so every new stamp is covered the moment it exists (that is how `job="configs-git-push"` joined on 19/10). See [`services/monitoring.md`](../services/monitoring.md).  
**Canonical Source of Schedules:** [`automations/schedules.json`](../automations/schedules.json) + [overview tables](../automations/README.md) — maintain strictly in sync.

## Weekly Rituals

- [ ] **restic repository integrity check** (Sun 06:00, automated via `hl-restic-configs-check.timer`).
- [ ] Spot-check stamp freshness (Grafana already alerts at >26 h; this is the on-demand view):
      `sudo rg -N homelab_backup_age_seconds /var/lib/node-exporter/textfile/health_files.prom | awk '{j=$1; sub(/.*job="/,"",j); sub(/".*/,"",j); printf "%-30s %5.1f h\n", j, $2/3600}'`
      Every row must read `< 24 h`. The file is regenerated every 5 min by `hl-health-metrics.timer` from `/srv/health/*-last-ok` (verified 19/10/2026: `configs-git-push` included).

## Monthly Recovery Drills

- [x] **Docker prune** (1st of each month at 04:00, automated via `hl-docker-prune.timer` on psicopompo) — cleans build cache and dangling layers; complements the 30GB garbage collection threshold in `daemon.json`. See [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md).

1. **Physical Restoration Drill** (dry-run verifications do not suffice):
   - Direct Mirror: Extract 1 configuration directory from `/mnt/BACKUP/configs-homelab/{host}/` to `/tmp` and inspect file integrity.
   - Restic: `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password restore latest --target /tmp/restic-test` and verify extracted contents.
   - Etckeeper: Clone bare repository `/srv/backup-gitrepos/etckeeper-{host}.git` and verify `/etc/fstab`.
2. **Service Spin-Up Drill:** Pick 1 containerized service (e.g. launch a compose stack from restored configuration) and document findings.
3. **Snapper Snapshots:** Inspect `sudo snapper -c nvme list` (confirm weekly snapshots exist); check disk headroom via `df -h`. ⚠️ Snapshots **pin reflink extents** — disk space from pruned Docker layers is only released once older snapshots are deleted (`snapper -c nvme delete --sync <n>`). See [`snapshots-psicopompo.md`](snapshots-psicopompo.md).

## Quarterly / On-Demand Audits

- [ ] `restic check --read-data` (reads entire repository payload) — I/O intensive; execute during off-peak windows.
- [ ] Audit configuration `EXCLUDES` (verify zero secret leakage: `git -C /mnt/BACKUP/configs-homelab ls-files | grep -iE 'shadow|\.env$|passwd'`).
- [ ] Test end-to-end restoration for Zomboid, Minecraft, and sae-core (Borg) into isolated staging environments.
- [ ] Inspect orphaned Btrfs subvolumes: `btrfs subvolume list -o /mnt/NVME_PCI/.snapshots`.

## Architectural Decisions & Exclusions

- **Known exposure (HB-094, accepted 2026-10-31):** the client's dumps with third-party personal data are also mirrored unencrypted to Google Drive.
- **Unencrypted Local Backups:** Primary NAS backup storage is unencrypted by explicit user preference (preventing key-loss lockouts) — secrets are encrypted upstream via SOPS/age.
- **Off-Site Storage:** ✅ **Active** (09/08) — Google Drive 5TB mirrored via rclone (`gdrive:BACKUP MNEMOCINE`, unencrypted remote mirror). See [`services/rclone.md`](../services/rclone.md).
- **etckeeper Bare Repositories:** Replicated strictly to internal NAS (never pushed to GitHub).
- **Age Encryption Keys & Master Secrets:** `age-keys-backup.txt` and plaintext `secrets.env` are NEVER stored on the NAS. ⚠️ **The off-host cold copy is pending** — the key is **not** in KeePassXC/USB today. Since 2026-10-13 the store also decrypts with the **kavure** age key (2nd recipient), so a **single-host** loss is covered; the cold copy is what covers losing **both** hosts — see [`../recovery/psicopompo-loss.md`](../recovery/psicopompo-loss.md) §2 G1 · HB-064.

## Incident: Silent Backup Outages (28/08 — Caught by Observability)

Upon deploying Prometheus textfile health file monitoring, **3 backups were found silently failing**:

| Backup Pipeline | Symptom | Root Cause | Remediation |
|---|---|---|---|
| `restic-configs` (psicopompo) | Stale for 19 days + daily ntfy "restic FAILED" | Missing `$HOME`/`$XDG_CACHE_HOME` in systemd unit environment | Injected `Environment=HOME=/root XDG_CACHE_HOME=/root/.cache` into `hl-restic-configs-backup.service` |
| `rclone-gdrive` (Off-site) | Stale for 4 days | `--max-delete 200` tripped by excessive churn of `.git` files | Added exclusion `/configs-homelab/**/.git/**` + raised `--max-delete 5000` |
| `config-backup` ybytu/ybyra (VPS) | Stale for 7 days | NFS `Stale file handle` after server reboot | Remounted `/srv/backup-configs` on VPS nodes |
| `sumaenima-backup` (kavure) | Internal container crond broken | Image started executing as non-root `appuser` (v2.22.0) | Migrated scheduling to host systemd timer `hl-sumaenima-backup.timer` (03:00) |

**Key Takeaway:** The Grafana alert `BackupNotRun` (>26h) now covers all backup jobs across all hosts. It reads the **health stamps** (`/srv/health/*-last-ok` → `homelab_backup_last_ok_seconds`); the stamps were **not** removed — they are the indicator. What was removed in 2026-08 were the *legacy* stamps of jobs already covered elsewhere. A job without a stamp is invisible to the alert: that is exactly how the GitHub push failed quietly from 16 to 19/10/2026 (see below).

## Incident: Silent Off-Site Push Failure (16–19/10/2026 — psicopompo)

Not a "backup outage" but its worst cousin: the **GitHub off-site copy was frozen for 3 days with zero signal**. Every run of `configs-git-push` exited `status=1` ("push FALHOU") while Grafana stayed green and ntfy stayed mute — the job had **no health stamp** and **no `OnFailure=`**, and the script discarded git's error output.

| Item | Detail |
|---|---|
| Trigger | 17/10 commit picked up `ybytu/homelab/uptime-kuma/kuma.snapshot` (**106 → 134 MB**); GitHub rejects the **whole push** for any file >100 MB |
| Detected by | manual audit of the backup chain (19/10) — **not** by monitoring |
| Impact | none on data: the NAS mirror, restic and Google Drive were all current; only the 2nd off-site copy (GitHub) was stale |
| Fix | `.gitignore` rule for the snapshot; the 3 never-pushed commits folded into one and pushed; **size guard** (>95 MB → abort + ntfy `high`); **health stamp**; **`OnFailure=`**; git diagnostics to journald |
| Verified | guard tested live (100 MB probe file → aborted, no push, both alerts fired); happy path re-run (`OK`, stamp touched); `ls-remote` == local HEAD |

**Rule extracted:** a backup job without (a) a freshness stamp and (b) an `OnFailure` alert is a silent-failure candidate. Audit any new job against both. Full detail: [`config-backup.md`](config-backup.md) §Incident.

## Change Management Procedure

1. Edit the relevant runbook (`config-backup.md`, `snapshots-psicopompo.md`) FIRST.
2. Apply operational changes (systemd timer, script, config).
3. Validate with dry-run and live execution, then update task checkboxes in documentation.
