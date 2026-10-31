---
tags: [homelab, recovery, checklist, backup, psicopompo, sops, swarm, docker, tailscale, storage, server]
---

# psicopompo — From-Zero Rebuild Runbook

> **Scope.** Step-by-step rebuild of `psicopompo` after a total host loss. It is the executable
> counterpart of the dependency matrix in [`psicopompo-loss.md`](psicopompo-loss.md) (the *what stops,
> what survives* analysis) and fills the §3 sketch of [`disaster-recovery.md`](disaster-recovery.md).
> Drafted **2026-10-30** (closes the documentation half of HB-065).
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
2. Recreate the three Btrfs filesystems/mountpoints. **⚠️ unverified:** the exact subvolume layout and `fstab` entries are **not** captured in the vault — if `/mnt/BACKUP` survived, `blkid` and the surviving disk's subvolumes are the authority; otherwise take the layout from the `etckeeper-psicopompo` bare repo (§3).
3. Join the tailnet **by account login** (`tailscale up`); the control plane is Tailscale's. If tags are needed, re-tag the device per [`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md). The ACL is GitOps in `MNEMOCINE-ACL` and is **not** touched by a host rebuild.
4. Confirm `tailscale status` shows kavure and kuaray before continuing — every later step reaches them over the tailnet.

### 2.2 Restore source (branch on `/mnt/BACKUP`)

| Situation | Action |
|---|---|
| **NAS disk survived** | Mount it at `/mnt/BACKUP`; skip the download. |
| **NAS disk lost** | After the age key and rclone credentials are available (§2.4), pull the off-site mirror: `rclone sync "gdrive:BACKUP MNEMOCINE" /mnt/BACKUP` (dry-run first with `--dry-run`). The rclone credentials (`RCLONE_GDRIVE_*`) are themselves in the SOPS store, so §2.4 comes first in this branch. |
| **Google Drive unreachable** | `/mnt/BACKUP/configs-homelab/*` on kavure/kuaray clients and the GitHub repos are the surviving copies. See the warning in [`disaster-recovery.md`](disaster-recovery.md) §3. |

### 2.3 NFS exports

1. Restore `/etc/exports` (from `configs-homelab/psicopompo` or the etckeeper repo). It must contain the media, `sumaenima-server-kavure`, `zomboid-server-kavure`, `minecraft-server-kavure`, `n8n-server-kavure` and `configs-homelab` exports, scoped to the two tailnet IPs above.
2. `sudo exportfs -arv`, then `sudo systemctl enable --now nfs-server`.
3. Client mounts must keep `soft` (never `hard` — see [`../AGENTS.md`](../AGENTS.md)). Verify from kavure/kuaray: `findmnt -n -o FSTYPE /mnt/nas | rg nfs`.

### 2.4 Secrets

1. On a host holding an age key (kavure, or the cold copy), decrypt the store and confirm it opens: `sops -d mnemocine/secrets.enc.env >/dev/null && echo OK` (never print the output).
2. Place the age key on the rebuilt psicopompo at `~/.config/sops/age/keys.txt` (`0600`, owner `edu`) **only if** you intend psicopompo to be a recipient again; otherwise keep decrypting from kavure and re-add psicopompo's new key as a recipient later.
3. If the psicopompo recipient changed, update **both** copies of the rules and verify the recipient count, per [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) (HB-072).
4. Run `inject-secrets.sh` to repopulate per-service `.env` files.

### 2.5 Docker and Swarm

1. Install Docker; **do not** set `"live-restore": true` (breaks Swarm — [`../AGENTS.md`](../AGENTS.md)).
2. On **kavure** (manager): remove the dead worker entry — `docker node rm Psicopompo` — then rejoin the rebuilt host with the worker join token (`docker swarm join-token worker` on the manager).
3. Re-label the node `role=gpu` (the GPU services are constrained by that label).
4. Restore the compose projects to `/home/edu/homelab/*/` from the NAS mirror or the private `mnemocine` git repo, then `docker compose up -d` per project. The private registry (`registry:3`, port 5000) is the image source for Swarm deploys, so bring it up first.

### 2.6 Operational layer — `MNEMOCINE-OPS`

Without this layer there are **no timers** and the backup circuit does not exist.

```bash
git clone https://github.com/ceduardorodrig/MNEMOCINE-OPS ~/homelab/mnemocine-ops
cd ~/homelab/mnemocine-ops/provisioning/scripts
./install-homelab-tools.sh --list      # what exists and where
./install-homelab-tools.sh --check     # what is out of sync
./install-homelab-tools.sh --all       # install the tools (Rust tools are compiled on psicopompo, the build node)
```

Then copy the units from `provisioning/systemd/` to `/etc/systemd/system/`, `systemctl daemon-reload`, and enable the timers. **⚠️ unverified:** `install-homelab-tools.sh` installs the *tools*; whether it also installs and enables the *units* has not been confirmed — read `--list` output and the script before assuming. The Rust toolchain must exist on the rebuilt host (it is the build node, ADR-026).

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
| Btrfs subvolume layout and `fstab` of psicopompo are not recorded in the vault | to document from the live host (read-only) |
| Whether `install-homelab-tools.sh` installs/enables the units | verify by reading the script and `--list` |
| No second, independent freshness witness for the off-site pipeline | HB-066 |
| No failover for the NFS exports (rebuild is the only path) | HB-067 |
| The runbook was never executed | run it in a recovery drill |

## References

- [`psicopompo-loss.md`](psicopompo-loss.md) — dependency matrix and ranked gaps this runbook answers
- [`disaster-recovery.md`](disaster-recovery.md) — unified DR manual (§3 links here)
- [`../servers/psicopompo.md`](../servers/psicopompo.md) — host manifest
- [`../backups/config-backup.md`](../backups/config-backup.md) · [`../backups/backup-rituals.md`](../backups/backup-rituals.md)
- [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md)
