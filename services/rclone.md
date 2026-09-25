---
tags: [homelab, service, rclone, storage, cloud]
---

# Rclone

Cloud storage client (remotes: Google Drive, etc.) — CLI + mount.

**Server:** psicopompo

> **26/08/2026:** **Rclone Web GUI removed** — never used (only homepage was monitoring the port, and it became an orphan connection). The `rclone-webgui.service` (Rclone Web GUI + RC daemon, `:46295`) was disabled and the unit deleted. The RC daemon ran with `--rc-no-auth` on the Tailnet — removing it also reduces the attack surface. **CLI/backup/mount remain.**

## Components

| Unit (systemd --user) | Role | Status |
|---|---|---|
| `rclone-webgui.service` | Rclone Web GUI + RC daemon | ❌ **removed (26/08)** — unit deleted |
| `rclone-mount.service` | Mount of `gdrive:` at `/home/edu/Google_Drive` | ✅ active |

## Configuration

- Config: `/home/edu/.config/rclone/rclone.conf`
- Remote: `gdrive:` (scope `drive`)
- Mount: `/home/edu/Google_Drive`

## Commands

```bash
# Mount Google Drive
systemctl --user start rclone-mount.service

# Reautenticar o gdrive (token expirado) — exige navegador
rclone config reconnect gdrive:
```

## Pending

- **Re-authenticate the `gdrive:` token** — the mount fails with `couldn't find root directory ID` (token expired). Manual reauth: `rclone config reconnect gdrive:` and then `systemctl --user start rclone-mount.service`.

## See also
- [[psicopompo]] — Server

## Off-site — BACKUP MNEMOCINE (09/08/2026)

- **Daily sync** of `/mnt/BACKUP` (221G) → `gdrive:BACKUP MNEMOCINE` via `/usr/local/bin/rclone-gdrive-backup` (cron `30 6 * * *` root).
- **Scheduler:** systemd timer **`hl-rclone-gdrive-backup.timer`** (daily `06:30`, `Persistent=true` — catch-up after reboot). Migrated from cron on **10/08**; cronie left installed (future use). See `automations/schedules.json`.
- **No encryption** (owner's decision). Deleted files go to `gdrive:_deleted/<data>/` (`--backup-dir`) + `--max-delete 200`.
- Excludes `.stversions/**`, **`.snapshots/**` (10/08)**, `.Trash-1000/**`, `.stfolder`.
- **1st sync** (221G) in the background on 09/08 — takes ~1-2 days at the current upload rate; daily delta afterwards.
- **10/08:** sync interrupted by the **reboot (~15:46)** (log with no final summary, no health) and **resumed manually** as root (15:57) — uploading the remaining delta (`zomboid-server-kavure/archive/migration-20260805`). A reboot leaves the sync unfinished until the timer's next run (06:30); resume with `/usr/local/bin/rclone-gdrive-backup` (root) when needed.
- **Token**: `rclone config reconnect gdrive:` — **expired/revoked on 09/08, 16/08 and 19/08 (~7 days each)**. `rclone.conf` is mirrored on the NAS (psicopompo config-backup) so you can reconnect from any machine.

> **🔴 Cause of the recurring expiry (19/08/2026):** the OAuth app of the own client_id (`127604679023-...apps.googleusercontent.com`) had *publishing status = **Testing*** in the Google Cloud Console → Google **revokes the refresh token every ~7 days** (policy for apps in Testing). **Solution applied:** the app was published as **"In production"** on 19/08 (personal use with <100 users does not require verification; the "app not verified" warning at login is expected and harmless). With the app in production, the refresh token **no longer expires weekly**. Official rclone docs: the shared rclone `client_id` will be retired in 2026 — your own client is the recommended path (already in use).
- **Monitors**: ntfy `/backup` + health `/srv/health/rclone-gdrive-last-ok` + `rclone about gdrive:` (5TB quota) in the ritual.
- Recorded in `automations/schedules.json` and `backups/backup-rituals.md`.

## 🔴 Fix: `.snapshots` must NOT go to Drive (10/08/2026)

The 1st sync **did not exclude `.snapshots`** (the snapper snapshots subvolume in `/mnt/BACKUP`). Each snapshot contains a **full copy of the backup** → the sync blew up from ~221G to **640 GiB** (ETA 4h+). Applied:

1. **`--exclude ".snapshots/**"`** added to `/usr/local/bin/rclone-gdrive-backup` (script fixed).
2. **`purge`** of the remote `.snapshots` (`gdrive:BACKUP MNEMOCINE/.snapshots`) — **297 GiB / 21,685 files** removed (they go to the Drive trash; it empties in ~30 days or manually — it counts against the quota until then).
3. Sync restarted (new PID) without `.snapshots` → transferred the remaining delta (~3.6 GiB of git objects + navidrome cache).
4. **Root guard** added to the script (non-root manual runs abort without a false alert — same as config-backup).

> **Lesson:** snapper + rclone never — the off-site should be a mirror of the CURRENT state, not of historical snapshots (those stay in local btrfs + restic).

## 🟡 Incident: offsite with no sync 16→19/08 (resolved 19/08)

- **Symptom:** invalid gdrive token (`invalid_grant: token expired or revoked`) → the script fails at the fail-fast (step 1) **before** touching log/health → `/srv/health/rclone-gdrive-last-ok` stopped at 16/08 06:40, even though the 06:30 timer was active. ntfy `/backup` alerted "OFFLINE" on days 17 and 18.
- **Cause:** OAuth app in "Testing" (7-day expiry) — see the note above.
- **Fix:** published "In production" + `rclone config reconnect gdrive:` (reauth 19/08 14:09) + manual `sudo /usr/local/bin/rclone-gdrive-backup` (sync of the 16→19/08 delta: **8.86 GiB / 5003 files, 51 min**, 153.5k checks OK, health updated 19/08 14:29). The timer stays active (06:30).
- **Lessons:** (1) monitor the token's `expiry` in `rclone.conf` (early warning via ntfy before it expires); (2) if you run the manual backup with a short timeout, the wrapper may die before the health `touch` (the child rclone keeps running — run it again to finish the health file).
