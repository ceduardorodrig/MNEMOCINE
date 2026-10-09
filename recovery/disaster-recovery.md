---
tags: [homelab, recovery, backup, checklist]
---

# Disaster Recovery — Mnemocine

> **Unified** recovery playbook (supersedes legacy `*-disaster-recovery.md` and `playbook.md` documents).  
> **Restoration Sources:** Central NAS Mirror · restic · GitHub Private Mirror `mnemocine` · rclone→Drive · etckeeper · snapper · Syncthing.  
> **Golden Rule:** A backup that has never been restored does not exist → **monthly drills** (`backups/backup-rituals.md`).

## 1. Restoration Sources

| Source | Target Restored | Location |
|---|---|---|
| **Central NAS Mirror** | Configurations and Docker Compose stacks across all nodes | `/mnt/BACKUP/configs-homelab/{host}/` |
| **restic** | Versioned configuration history + Obsidian vault | `/mnt/BACKUP/repos/restic/configs` (`--insecure-no-password`) |
| **git GitHub `mnemocine`** | Declarative configuration history | Private repository `ceduardorodrig/mnemocine` |
| **rclone → Google Drive** | **Off-Site Storage** — Full mirror of `/mnt/BACKUP` | `BACKUP MNEMOCINE` directory |
| **etckeeper** | System `/etc` configurations per node | Bare git repositories at `/mnt/BACKUP/repos/git/etckeeper-{host}.git` |
| **snapper** | Btrfs timeline snapshots on psicopompo | Configs `nvme`/`backup`/`hdd`/`root` |
| **Syncthing** | Vault + `backup` mirror | kuaray (receive-only) |

## 2. Generic Host Recovery Procedure

1. **OS Installation & Container Engine Setup** (see host role in Section 4).
2. **Restore Configurations & Compose Files:** Clone `git clone https://github.com/ceduardorodrig/mnemocine` (or copy from NAS mirror) → `/home/{user}/homelab/`; restore `/etc` via etckeeper (`git clone /srv/backup-gitrepos/etckeeper-{host}.git`).
3. **Launch Containers:** `for d in /home/{user}/homelab/*/; do (cd "$d" && docker compose up -d); done`.
4. **Restore Persistent Volumes:** Extract from restic via `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password restore latest --target /` or mount NFS off-box targets.
5. **Verify Operational Health** (Section 5).

## 3. Order of Recovery (Cross-Node Dependencies)

> **psicopompo RESTORED FIRST** — Operates as the Tailnet NAS / central backup repository. Remaining nodes depend on its NFS exports.

### Total Loss of Psicopompo (Including `/mnt/BACKUP`)
The recovery path pivots to **rclone off-site storage** (Google Drive `BACKUP MNEMOCINE`):

1. Rebuild psicopompo (OS + NFS daemons + Docker).
2. Retrieve off-site backup: `rclone sync "gdrive:BACKUP MNEMOCINE" /mnt/BACKUP`.
3. Re-export NFS shares (`/etc/exports`) and run `exportfs -arv`.
4. Restore Obsidian vault: `/mnt/BACKUP/agentic-ai-server-psicopompo/agentic-ai` → `/mnt/NVME_PCI/agentic-ai`.
5. Restore credentials: SOPS store (`secrets.enc.env` in vault) using offline age master key from KeePassXC.

> ⚠️ If Google Drive is unreachable: **Recover via etckeeper and client mirrors** (`/mnt/BACKUP/configs-homelab/*` is the sole surviving mirror — prioritize `psicopompo`, `kavure`, and `kuaray`).

## 4. Node Roles & Specific Restore Tasks

| Host | Node Role | Specific Recovery Focus |
|---|---|---|
| **psicopompo** | NAS/NFS, Obsidian vault, GPU inference workers, build node | Btrfs subvolumes (snapper `nvme`/`backup`), restic, rclone off-site |
| **kavure** | Game servers (Zomboid/Minecraft/Valheim), Swarm sae-core, HA, Pi-hole, Navidrome, Calibre, AioStreams, Comet | Composes in `/srv/data/*/compose.yml`; game saves via NFS off-box; media libraries via NFS |
| **kuaray** | *arr stack (Lidarr, Prowlarr, Transmission, slskd, Soularr, FlareSolverr), Miracena stack, Syncthing, Vert | Composes in `/home/kuaray/homelab/*/compose.yml`; Miracena PostgreSQL/MariaDB dumps via NFS |

> **Post-Restore Secret Injection (28/08/2026):** API keys for the *arr stack and `secrets.yaml` for Home Assistant reside in the **SOPS store** — after restoring configs, run `inject-secrets.sh` (psicopompo) to repopulate credentials. See `guides/secrets-centralizados.md`.

| Host | Node Role | Specific Recovery Focus |
|---|---|---|
| **ybytu** | DNS (AdGuard), Homepage dashboard, Uptime Kuma, ntfy, changedetection | Composes in `/home/ubuntu/homelab/*/` |
| **ybyra** | Primary Public Edge (sae-edge) | Compose `/home/ubuntu/docker-compose.ybyra.yml` |

## 5. Post-Restore Verification Checklist

- `docker ps` — All containers running in **healthy** state.
- Homepage responds with HTTP 200 (`http://ybytu:3001`).
- DNS lookup resolves cleanly: `dig @100.124.146.77 google.com` (Pi-hole on kavure) and AdGuard on ybytu.
- NFS shares mounted on clients: `df /mnt/BACKUP` (kavure/kuaray).
- Obsidian vault verified: `/mnt/NVME_PCI/agentic-ai` (psicopompo).
- Off-site pipeline verified: Fresh timestamp in `/srv/health/rclone-gdrive-last-ok`.

## 6. Maintenance Rituals

- **Monthly Recovery Drill:** Restore 1 configuration from restic + 1 from git (see `backups/backup-rituals.md`).
- **Off-Site Quota Audit:** Check `rclone about gdrive:` + verify health files.
- **Snapper Audit:** Run `snapper -c nvme list` to ensure snapshot timelines are advancing.
- Update this document whenever services migrate across hosts (canonical AGENTS.md rule).
