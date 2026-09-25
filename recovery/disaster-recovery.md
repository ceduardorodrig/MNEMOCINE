---
tags: [homelab, recovery, backup, checklist]
---

# Disaster Recovery — Mnemocine

> The **single** recovery guide (replaces the old `*-disaster-recovery.md` and `playbook.md`).
> **Sources:** NAS mirror · restic · GitHub git `mnemocine` · rclone→Drive · etckeeper · snapper · syncthing.
> **Golden rule:** a backup that was never restored does not exist → **monthly drill** (`backups/backup-rituals.md`).

## 1. Recovery sources

| Source | Restores | Where |
|---|---|---|
| **NAS mirror** | Configs + composes from all hosts | `/mnt/BACKUP/configs-homelab/{host}/` |
| **restic** | Config + vault history/versions | `/mnt/BACKUP/repos/restic/configs` (`--insecure-no-password`) |
| **GitHub git `mnemocine`** | Versioned configs | private repo `ceduardorodrig/mnemocine` |
| **rclone → Google Drive** | **Off-site** — everything from `/mnt/BACKUP` | folder `BACKUP MNEMOCINE` |
| **etckeeper** | `/etc` from each host | bare repos `/mnt/BACKUP/repos/git/etckeeper-{host}.git` |
| **snapper** | btrfs snapshots of psicopompo | configs `nvme`/`backup`/`hdd`/`root` |
| **syncthing** | Vault + `backup` mirror | kuaray (receiveonly) |

## 2. Generic restore procedure (any host)

1. **OS + Docker/compose** (see the host's role in section 4).
2. **Configs/composes:** `git clone https://github.com/ceduardorodrig/mnemocine` (or copy from the NAS mirror) → `/home/{user}/homelab/`; `/etc` via etckeeper (`git clone /srv/backup-gitrepos/etckeeper-{host}.git`).
3. **Bring up services:** `for d in /home/{user}/homelab/*/; do (cd "$d" && docker compose up -d); done`.
4. **Data:** `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password restore latest --target /` or NFS.
5. **Verify** (section 5).

## 3. Recovery order (cross dependencies)

> **psicopompo FIRST** — it is the NAS/backup hub. Everything else depends on the NFS/mirror.

### Total loss of psicopompo (including /mnt/BACKUP)
The source then becomes **rclone off-site** (Google Drive, `BACKUP MNEMOCINE`, no encryption):

1. Recreate psicopompo (OS + NFS + Docker).
2. `rclone sync "gdrive:BACKUP MNEMOCINE" /mnt/BACKUP` (download everything).
3. Re-export NFS (`/etc/exports`) + `exportfs -arv`.
4. Restore the vault: `/mnt/BACKUP/agentic-ai-server-psicopompo/agentic-ai` → `/mnt/NVME_PCI/agentic-ai`.
5. Secrets: sops store (`secrets.enc.env` in the vault) — the age key must be in KeePassXC.

> ⚠️ If even Drive is unavailable: **etckeeper + the client mirror** (`/mnt/BACKUP/configs-homelab/*` is the only complete copy — prioritize `psicopompo`, `kavure`, `kuaray`).

## 4. Per server (current role 09/08)

| Host | Role | Specific restore |
|---|---|---|
| **psicopompo** | NAS/NFS, vault, GPU workers, build-node | btrfs (snapper `nvme`/`backup`/`hdd`), restic, rclone off-site |
| **kavure** | Games (Zomboid/Minecraft), Swarm sae-core, HA, Pi-hole, Navidrome, Calibre, AIOStreams, Comet | composes `/srv/data/*/compose.yml`; games via off-box NFS; music/books via NFS |
| **kuaray** | arr-stack (lidarr/prowlarr/transmission/slskd/soularr/flaresolverr), syncthing, vert | composes `/home/kuaray/homelab/*/compose.yml` |

> **Post-restore secrets (28/08/2026):** the arr-stack API keys and the HA `secrets.yaml` are in the **sops store** — after restoring the configs, run `inject-secrets.sh` (psicopompo) to re-inject the values (with `.bak`). See `guides/secrets-centralizados.md`.
| **ybytu** | DNS (AdGuard), Homepage, Uptime Kuma, ntfy, changedetection | composes `/home/ubuntu/homelab/*/` |
| **ybyra** | Primary edge (sae-edge) | compose `/home/ubuntu/docker-compose.ybyra.yml` |

## 5. Post-restore verification

- `docker ps` — all containers **Up**.
- Homepage HTTP 200 (`http://ybytu:3001`).
- DNS resolves — `dig @100.124.146.77 google.com` (pihole kavure) and AdGuard ybytu.
- NFS mounted on the clients — `df /mnt/BACKUP` (kavure/kuaray).
- Vault present — `/mnt/NVME_PCI/agentic-ai` (psicopompo).
- Off-site — `/srv/health/rclone-gdrive-last-ok` recent.

## 6. Maintenance ritual

- **Monthly drill:** restore 1 config from restic + 1 from git (see `backups/backup-rituals.md`).
- **Off-site:** check `rclone about gdrive:` (quota) + health file.
- **Snapper:** `snapper -c nvme list` (week OK).
- Update this doc whenever services change host (canonical AGENTS.md rule).
