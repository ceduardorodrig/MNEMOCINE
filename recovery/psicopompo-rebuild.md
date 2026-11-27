---
tags: [homelab, recovery, checklist, backup, psicopompo, sops, swarm, docker, tailscale, storage, server]
pending: [HB-065]
---

# psicopompo — From-Zero Rebuild Runbook

> **Scope.** Step-by-step rebuild of `psicopompo` after a total host loss. It is the executable
> counterpart of the dependency matrix in [`psicopompo-loss.md`](psicopompo-loss.md) (the *what stops,
> what survives* analysis) and fills the §3 sketch of [`disaster-recovery.md`](disaster-recovery.md).
> Drafted **2026-10-30** (closes the documentation half of HB-065). Both documented gaps were closed
> **2026-11-03** with live data: the storage/`fstab` layout (§2.1) and the systemd units (§2.6 — installed by
> the same installer with `--units` since MNEMOCINE-OPS PR #24/#25).
>
> **Paper verification 2026-11-26 (read-only on the live host, not a rebuild):** the §2.1 UUIDs match
> `/etc/fstab`; the five §3 health stamps are dated 2026-11-26; the SOPS store decrypts; `nfs-server`, `docker`
> and `hl-infer` are enabled; `daemon.json` has no `live-restore`. Two defects found: the §2.3 export list was
> incomplete (fixed) and `inject-secrets.sh` had no backup (fixed 2026-11-27, §2.4).
>
> **Status of this document: written from the documented design and read-only inspection of the
> live host; it has never been executed end to end.** Steps marked **⚠️ unverified** have not been
> proven in a drill. A runbook that has not been rehearsed is a hypothesis — run it in the
> monthly recovery drill ([`../backups/backup-rituals.md`](../backups/backup-rituals.md)) and
> correct this file with what actually happened.

## 0. Before you start

| Check | Why |
|---|---|
| You can decrypt the SOPS store from a surviving key: **kavure** (`/home/kavure/.config/sops/age/keys.txt`, 2nd recipient since 2026-10-13) **or** the cold copy (KeePass entry `Mnemocine · SOPS age key (cold)`, DB mirrored to `ybytu`) | Without an age key the master secrets cannot be recovered — see [`psicopompo-loss.md`](psicopompo-loss.md) §2 G1 (resolved). |
| `rclone about gdrive:` works from a live host, **or** the NAS disks survived | Decides which restore source in §3 you use. |
| You know whether `/mnt/BACKUP` (the NAS disk) survived | Branch point in §3. |

**Never** put a secret value in this file, in a chat, or in a shell history. Secrets move only through
the SOPS store ([`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md)).

## 1. What psicopompo is (so you know what you are rebuilding)

Facts from [`../servers/psicopompo.md`](../servers/psicopompo.md) and the live host (2026-10-30):

- **OS:** CachyOS (Arch), shell `fish`; user `edu` (uid 1000) with `NOPASSWD` sudoers (`/etc/sudoers.d/99-edu-homelab`).
- **Storage:** `/mnt/NVME_PCI` (Btrfs, work disk), `/mnt/HDD_SATA` (Btrfs), **`/mnt/BACKUP`** (Btrfs, the NAS root).
- **NAS:** native `nfsd` exporting `/mnt/BACKUP/*` over the **tailnet** to kuaray (`100.94.209.99`) and kavure (`100.124.146.77`), `all_squash` to uid/gid 1000. Source of truth: `/etc/exports`.
- **Swarm:** a **worker** (`role=gpu`) of the swarm managed by **kavure**. Nothing structural is lost with the worker.
- **GPU:** RTX 5050, proprietary driver, ReBAR via kernel command line.
- **Operational layer:** ~49 `hl-*` systemd units and the scripts in `/usr/local/bin`, all sourced from the `MNEMOCINE-OPS` repository (`provisioning/`).

## 2. Rebuild order

```
OS + disks ─▶ Tailscale ─▶ restore source ─▶ NFS exports ─▶ Docker/Swarm ─▶
secrets ─▶ ops layer (MNEMOCINE-OPS) ─▶ backup circuit (in order) ─▶ verify
```

### 2.1 OS, disks and Tailscale

1. Install CachyOS; create the user `edu` (uid 1000, same as the NFS `anonuid`) and the sudoers rule.
2. Recreate the three data filesystems and the Btrfs subvolume layout. **Verified 2026-11-03** from the live `/etc/fstab` and `findmnt`; if a disk survived, reuse it as-is and take the UUID from `blkid` (do not reformat):
3. Join the tailnet **by account login** (`tailscale up`); the control plane is Tailscale's. If tags are needed, re-tag the device per [`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md). The ACL is GitOps in `MNEMOCINE-ACL` and is **not** touched by a host rebuild.
4. Confirm `tailscale status` shows kavure and kuaray before continuing — every later step reaches them over the tailnet.

#### Verified storage layout (2026-11-03, live host)

Root filesystem is one partition with Btrfs subvolumes; the three data disks are **single-partition
Btrfs mounted at the top level** (`subvolid 5`), so a rebuild only needs the mount, not subvolume
creation. `nofail` on every data mount is deliberate: a missing disk must not block boot.

| Mount | Device | UUID | Subvolume | Options |
|---|---|---|---|---|
| `/boot` | ESP | `0D9A-9026` | — | `vfat umask=0077` |
| `/` | `nvme0n1p2` | `ffc60b3e-2f31-47bb-b51e-4eb785af8647` | `@` | `noatime,compress=zstd:1` |
| `/home` | same | same | `@home` | same |
| `/root` | same | same | `@root` | same |
| `/srv` | same | same | `@srv` | same |
| `/var/cache` | same | same | `@cache` | same |
| `/var/tmp` | same | same | `@tmp` | same |
| `/var/log` | same | same | `@log` | same |
| `/tmp` | tmpfs | — | — | `mode=1777` |
| `/mnt/NVME_PCI` | `nvme1n1p5` | `315290c7-7556-4a5f-ac6c-cc4d79d56c20` | top level | `nofail,noatime,compress=zstd` |
| `/mnt/BACKUP` | `sda1` | `3cccdf84-6549-46c4-8f1c-d302a20b6584` | top level | `nofail,noatime,compress=zstd` |
| `/mnt/HDD_SATA` | `sdc1` | `1866df07-62b5-467c-8771-99af2fb8eae4` | top level | `nofail,noatime,compress=zstd` |
| `/mnt/SSD_SATA` | — | `2f59eee5-8bd6-4cd8-8ee4-96618b6c7541` | top level | `nofail` |
| `/mnt/SSD_SATA/scryfall-mirror` | same | same | `@scryfall` | `compress=zstd:3,ssd,noatime,discard=async` |

UUIDs change if a filesystem is recreated; with a surviving disk, mount it and read the real UUID
with `blkid` instead of copying the one above.

### 2.2 Restore source (branch on `/mnt/BACKUP`)

| Situation | Action |
|---|---|
| **NAS disk survived** | Mount it at `/mnt/BACKUP`; skip the download. |
| **NAS disk lost** | After the age key and rclone credentials are available (§2.4), pull the off-site mirror: `rclone sync "gdrive:BACKUP MNEMOCINE" /mnt/BACKUP` (dry-run first with `--dry-run`). The rclone credentials (`RCLONE_GDRIVE_*`) are themselves in the SOPS store, so §2.4 comes first in this branch. |
| **Google Drive unreachable** | `/mnt/BACKUP/configs-homelab/*` on kavure/kuaray clients and the GitHub repos are the surviving copies. See the warning in [`disaster-recovery.md`](disaster-recovery.md) §3. |

### 2.3 NFS exports

1. Restore `/etc/exports` (from `configs-homelab/psicopompo` or the etckeeper repo). The NAS mirror copy is `configs-homelab/psicopompo/golden/etc/exports`. Live set on 2026-11-26 (`exportfs -s`): `/mnt/BACKUP/{media/music,media/books,configs-homelab,repos/git}`, `/mnt/BACKUP/{sumaenima,zomboid,minecraft,n8n,valheim,monitoring,miracena}-server-kavure` and `/mnt/SSD_SATA/scryfall-mirror`, scoped to tailnet addresses.
2. `sudo exportfs -arv`, then `sudo systemctl enable --now nfs-server`.
3. Client mounts must keep `soft` (never `hard` — see [`../AGENTS.md`](../AGENTS.md)). Verify from kavure/kuaray: `findmnt -n -o FSTYPE /mnt/nas | rg nfs`.

### 2.4 Secrets

1. On a host holding an age key (kavure, or the cold copy), decrypt the store and confirm it opens: `sops -d mnemocine/secrets.enc.env >/dev/null && echo OK` (never print the output).
2. Place the age key on the rebuilt psicopompo at `~/.config/sops/age/keys.txt` (`0600`, owner `edu`) **only if** you intend psicopompo to be a recipient again; otherwise keep decrypting from kavure and re-add psicopompo's new key as a recipient later.
3. If the psicopompo recipient changed, update **both** copies of the rules and verify the recipient count, per [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) (HB-072).
4. Repopulate per-service credentials with `provisioning/scripts/inject-secrets --dry-run`, then without the flag, from a clone of the private repository `MNEMOCINE-OPS` (versioned 2026-11-27, PR #30, tested with synthetic data; remote hosts not yet exercised). It needs `sops`, the age key and SSH to the targets. The older copies `/mnt/NVME_PCI/secrets/inject-secrets.{sh,py}` remain on the NVMe disk only. Fallback by hand: the table in [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md).

### 2.5 Docker and Swarm

1. Install Docker; **do not** set `"live-restore": true` (breaks Swarm — [`../AGENTS.md`](../AGENTS.md)).
2. On **kavure** (manager): remove the dead worker entry — `docker node rm Psicopompo` — then rejoin the rebuilt host with the worker join token (`docker swarm join-token worker` on the manager).
3. Re-label the node `role=gpu` (the GPU services are constrained by that label).
4. Restore the compose projects to `/home/edu/homelab/*/` from the NAS mirror or the private `MNEMOCINE-CONFIGS` git repo (`MNEMOCINE` is the public documentation repo), then `docker compose up -d` per project. The private registry (`registry:3`, port 5000) is the image source for Swarm deploys, so bring it up first.

### 2.6 Operational layer — `MNEMOCINE-OPS`

Without this layer there are **no timers** and the backup circuit does not exist.

```bash
git clone https://github.com/ceduardorodrig/MNEMOCINE-OPS ~/homelab/mnemocine-ops
cd ~/homelab/mnemocine-ops/provisioning/scripts
./install-homelab-tools.sh --list      # what exists and where
./install-homelab-tools.sh --check     # what is out of sync
./install-homelab-tools.sh --all       # install the tools (Rust tools are compiled on psicopompo, the build node)
```

Then install the **systemd units** with the same installer (`--units`, MNEMOCINE-OPS PR #24; the
timer set per host is `HOST_TIMERS` inside the script):

```bash
./install-homelab-tools.sh --host psicopompo --units     # run it after --all
```

It copies every `provisioning/systemd/*.{service,timer}`, runs `daemon-reload` and enables the
host's timers. A unit that already exists with other content is kept and reported as `DIFFERS`
(exit 1); read the difference before using `--force-units`, which saves `<unit>.bak-<time>` first.
PR #25 (merged 2026-11-26) added the psicopompo drop-ins (`provisioning/systemd/hosts/psicopompo/`),
versioned `hl-access-audit` and `hl-docker-prune` and added `hl-dnat-audit`: `HOST_TIMERS[psicopompo]`
lists 23 timers. Reconciled on 2026-11-27: `--units --force-units` overwrote four reviewed units (backups
`.bak-20261127022849` and `.prev-i1`), enabled `hl-dnat-audit.timer`, and a second `--units` run reported
`PASS unchanged=90 differs=0 timers=23`.

Not covered by the installer: the drop-in `hl-arandu-sync.service.d/hub-repo.conf` (points at the
Arandu source clone) and `hl-wol-relay.service`, which belongs to `KURURU-TAB3LITE-LINUX`.
`hl-infer.service` is installed but must be enabled by hand (it is a service, not a timer).

## 3. Restarting the backup circuit — strict order

All backup units use `RequiresMountsFor=/mnt/BACKUP`, so the NAS mount comes first. Start them **manually once, in this order**, and check the health stamp after each:

| # | Step | Unit / command | Health stamp (`/srv/health/…`) |
|---|---|---|---|
| 1 | NAS mounted | `findmnt /mnt/BACKUP` | — |
| 2 | Config mirror | `hl-config-backup.service` | `config-backup-psicopompo-last-ok` |
| 3 | Git push of configs | `hl-configs-git-push.service` | `configs-git-push-last-ok` |
| 4 | Restic | `hl-restic-configs-backup.service` | `restic-configs-last-ok` |
| 5 | etckeeper push | `hl-etckeeper-push.service` | — (check the bare repo's HEAD date) |
| 6 | Vault mirror | `hl-agentic-ai-backup.service` | `agentic-ai-backup-last-ok` |
| 7 | Off-site (**last**, it uploads everything above) | `hl-rclone-gdrive-backup.service` | `rclone-gdrive-last-ok` |

Do **not** start the off-site job (7) before the earlier ones succeed — it would mirror a half-restored NAS to Google Drive and could overwrite the only off-box copy. Always `--dry-run` the first rclone run after a rebuild.

## 4. Post-rebuild verification

Run these from **another host** where possible (test as the end user — [`../../governance/multi-agent-workflow.md`](../../governance/multi-agent-workflow.md)):

- [ ] `tailscale status` shows psicopompo online; `tailscale ping psicopompo` answers.
- [ ] From kavure/kuaray: the NFS mounts are `nfs` and writable as uid 1000.
- [ ] `docker node ls` (on kavure) shows psicopompo `Ready`, `role=gpu`.
- [ ] `docker ps` on psicopompo: containers `healthy`; the registry answers on `100.82.51.112:5000`.
- [ ] Every stamp in §3 is **younger than 26 h** and Prometheus's `BackupNotRun` is not firing for psicopompo.
- [ ] `stenio --health` reports the backup chain **Intact**.
- [ ] Vault: `/mnt/NVME_PCI/agentic-ai` is present and `stenio --scope homelab` passes (0 errors).
- [ ] Off-site: `rclone about gdrive:` works and `rclone-gdrive-last-ok` is fresh.
- [ ] Update this file and [`../servers/psicopompo.md`](../servers/psicopompo.md) with everything that differed from the plan.

## 5. Known gaps in this runbook

| Gap | Tracked as |
|---|---|
| ~~Btrfs subvolume layout and `fstab` of psicopompo are not recorded in the vault~~ — **closed 2026-11-03**: §2.1 records the verified layout | — |
| ~~Whether `install-homelab-tools.sh` installs/enables the units~~ — **closed 2026-11-03**: `--units` installs them (§2.6, MNEMOCINE-OPS PR #24/#25) | — |
| ~~`inject-secrets.sh` (and its `.py`) unversioned and not mirrored~~ — **closed 2026-11-27**: ported to `MNEMOCINE-OPS` `provisioning/scripts/inject-secrets` (§2.4); never exercised against remote hosts | HB-065 |
| No second, independent freshness witness for the off-site pipeline | HB-066 |
| No failover for the NFS exports (rebuild is the only path) | HB-067 |
| **The runbook was never executed** — the only remaining blocker to closing HB-065 | run it in a recovery drill |

## References

- [`psicopompo-loss.md`](psicopompo-loss.md) — dependency matrix and ranked gaps this runbook answers
- [`disaster-recovery.md`](disaster-recovery.md) — unified DR manual (§3 links here)
- [`../servers/psicopompo.md`](../servers/psicopompo.md) — host manifest
- [`../backups/config-backup.md`](../backups/config-backup.md) · [`../backups/backup-rituals.md`](../backups/backup-rituals.md)
- [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md)
