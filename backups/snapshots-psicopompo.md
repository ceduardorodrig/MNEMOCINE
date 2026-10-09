---
tags: [homelab, backup, snapshot, snapper, btrfs, psicopompo]
---

# Btrfs Snapshots — psicopompo (snapper)

> Accidental deletion safeguards against data loss or filesystem deletion storms across psicopompo storage drives.
> **Snapshots are NOT backups** (sharing the same physical drive substrate) — they serve as point-in-time rollbacks. Real backups are governed by `config-backup.md`, restic, Syncthing, and off-site replication.

## Active Configurations (Standardized 06/09/2026)

> **Golden Rule:** **Reconstructible** filesystems → **no** snapshots (wastes disk space and I/O); **non-reconstructible** filesystems → automated timeline anti-deletion policies. Aligns with ArchWiki guidelines (timeline snapshots for user data; excluded for ephemeral caches) and CachyOS conventions (root subvolumes protected by default).

| Configuration | Subvolume | Contents | Classification | Timeline Retention |
|---|---|---|---|---|
| `root` | `/` (`@` subvolume) | Operating system | System (CachyOS standard) | Disabled (managed via snap-pac) |
| `nvme` | `/mnt/NVME_PCI` (toplevel) | Vault, Docker, games, code | Mixed (**vault** is non-reconstructible) | ✅ 8/7/4/3 |
| `backup` | `/mnt/BACKUP` (toplevel) | NAS: Media, off-box backups, configs | **Non-reconstructible** | ✅ 4/7/4/0 |
| ~~`hdd`~~ | ~~`/mnt/HDD_SATA`~~ | ~~Steam Library~~ | Reconstructible | ❌ Removed 06/09 |
| _(Unconfigured)_ | `/mnt/SSD_SATA` | Scryfall image cache (kavure) | Reconstructible | ❌ Unconfigured |

- **`root`**: Automated pre/post snapshots taken on every `pacman -Syu` execution via **snap-pac** hooks. Bootable directly via the **Limine bootloader** menu (`limine-snapper-sync`).
- **`nvme`/`backup`**: Hourly timeline snapshots (`snapper-timeline.timer` active) — protects vault, mirrored configs, and persistent backups.
- **`hdd` Decommissioned (06/09):** HDD_SATA contains SteamLibrary (306 GB) — reconstructible cache, snapshots deleted (`snapper -c hdd delete-config`).
- **`ssd` Unconfigured:** SSD_SATA houses `@scryfall` (ephemeral image cache for kavure) — reconstructible from upstream.
- **Qgroups**: Disabled (prevents Btrfs metadata latency spikes). **Swap**: Zram (active, priority 100, 46.9 GB zstd) — `/swap` subvolume retired on 03/10/2026, reclaiming 48 GB NVMe space. **updatedb**: `.snapshots` added to `PRUNENAMES`.

## Commands

```bash
sudo snapper list-configs
sudo snapper -c nvme list
sudo snapper -c nvme create -c number --description "pre-change snapshot"   # manual
sudo snapper -c nvme delete <n>                                             # prune snapshot
# Inspect orphaned subvolumes outside snapper management:
sudo btrfs subvolume list -o /mnt/NVME_PCI/.snapshots
```

## Restoration Runbook

- **Individual Files / Folders**: Extract directly from a read-only snapshot without unmounting filesystems:
  ```bash
  sudo cp -a /mnt/NVME_PCI/.snapshots/<N>/snapshot/<path> <destination>
  ```
- **Entire Data Subvolumes** (NVMe / BACKUP in active use): Stop consuming services → create read-write snapshot from read-only target → swap active subvolumes → validate → start services. Refer to ArchWiki Snapper guide.
- **Root Filesystem**: Boot into desired snapshot from Limine menu → interact with `limine-snapper-sync` rollback dialog → reboot. (Caution: Kernel-only updates without boot partition parity may require fallback kernel images).

## Operational Notes

- **`nvme` Pins Docker Extents (Critical):** Subvolume `/mnt/NVME_PCI` contains `containerd-data`/`docker-data`. Btrfs timeline snapshots **pin reflink extents** — after running Docker prune commands, reclaimed disk space is only freed in `df` once older snapshots are purged (`snapper -c nvme delete --sync <n>`). On 06/09/2026, 18 older snapshots were purged, releasing ~110 GB. Snapshots containing Docker caches provide zero rollback utility and should be pruned aggressively. See [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md).
- NFS mounts from kavure may display legacy export paths in `mountinfo` — cosmetic kernel artifact; data routes accurately.
- Tuning retention limits: `sudo snapper -c nvme set-config TIMELINE_LIMIT_HOURLY=10 ...` (consult `snapper-configs(5)`).
