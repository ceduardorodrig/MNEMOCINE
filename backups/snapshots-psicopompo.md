---
tags: [homelab, backup, snapshot, snapper, btrfs, psicopompo]
---

# btrfs Snapshots — psicopompo (snapper)

> Protection against accidental deletion / "deletion storm" of the psicopompo disks.
> **A snapshot is NOT a backup** (same disk) — it is "going back in time". The real backup lives in `config-backup.md` + restic + Syncthing + off-site.

## Active configs (standardized 06/09/2026)

> **Golden rule:** **rebuildable** disk → **no** snapshot (it only consumes space/I/O); **non-rebuildable** disk → anti-deletion timeline. Aligned with the ArchWiki (timeline for user data; **not** for cache) and with CachyOS (root by default; other subvolumes only with explicit config).

| Config | Subvolume | Content | Classification | Timeline |
|---|---|---|---|---|
| `root` | `/` (subvol `@`) | System | System (CachyOS default) | disabled (snap-pac) |
| `nvme` | `/mnt/NVME_PCI` (toplevel) | vault, Docker, games, repos | Mixed (**vault** not rebuildable) | ✅ 8/7/4/3 |
| `backup` | `/mnt/BACKUP` (toplevel) | NAS: media, backups, configs | **Not rebuildable** | ✅ 4/7/4/0 |
| ~~`hdd`~~ | ~~`/mnt/HDD_SATA`~~ | ~~Steam~~ | Rebuildable | ❌ removed 06/09 |
| _(no config)_ | `/mnt/SSD_SATA` | Scryfall cache (kavure) | Rebuildable | ❌ no config |

- **`root`**: automatic pre/post snapshots on every `pacman -Syu` via **snap-pac** (hooks). Boot/restore through the **Limine** menu (limine-snapper-sync).
- **`nvme`/`backup`**: hourly timeline (timer `snapper-timeline.timer` active) — protects the vault, mirrored configs, backups and data.
- **`hdd` removed (06/09):** HDD_SATA = SteamLibrary (306G) — rebuildable, does not deserve a snapshot. Config + 16 snapshots + `.snapshots` deleted (`snapper -c hdd delete-config`).
- **`ssd` with no config:** SSD_SATA = `@scryfall` (scryfall cache for kavure) — rebuildable.
- **qgroups**: disabled (no slowdown). **Swap**: zram (active, pri 100) + swapfile `/swap` 48G (hibernation, pri 1) — the `/swap` subvolume is a **sibling of `/@`** (top-level), outside the `root` snapshots. **updatedb**: `.snapshots` in `PRUNENAMES`.

## Commands

```bash
sudo snapper list-configs
sudo snapper -c nvme list
sudo snapper -c nvme create -c number --description "antes de X"   # manual
sudo snapper -c nvme delete <n>                                    # remover
# verificar órfãos (snapshots no disco fora do controle do snapper):
sudo btrfs subvolume list -o /mnt/NVME_PCI/.snapshots
```

## Restore

- **File/folder**: copy from a snapshot without taking anything down:
  ```bash
  sudo cp -a /mnt/NVME_PCI/.snapshots/<N>/snapshot/<caminho> <destino>
  ```
- **Entire data subvolume** (NVMe/BACKUP, in use): stop the services using it → create an rw snapshot from the RO → switch the subvolume → validate → start. See the ArchWiki Snapper page.
- **Root**: boot the snapshot from the Limine menu → limine-snapper-sync restore dialog → reboot. (Careful: a kernel snapshot is not bootable — CachyOS wiki.)

## Notes

- **`nvme` pins Docker data (important):** the `/mnt/NVME_PCI` subvolume contains `containerd-data`/`docker-data`. Timeline snapshots **hold (reflink) the extents** — when you prune Docker, the space only returns to `df` after deleting the old snapshots (`snapper -c nvme delete --sync <n>`). On 06/09/2026, 18 old snapshots were deleted (17 pre-cleanup + `snapshot-inicial-vault` #1), freeing ~110GB; only 2 recent timeline snapshots remained. Snapshots of Docker data (rebuildable) have no rollback value — delete them without mercy. See [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md).
- The kavure NFS mount may show the old export path in `mountinfo` — that is only a cosmetic label; the data lands in the right place.
- Adjusting retention: `sudo snapper -c nvme set-config TIMELINE_LIMIT_HOURLY=10 ...` (see `snapper-configs(5)`).
