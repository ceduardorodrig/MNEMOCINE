---
tags: [homelab, recovery, storage, psicopompo]
---

# Contingency Plan — NAS Disk Replacement (psicopompo)

> **Status:** documented (13/09/2026) — **NOT executed**. The NAS's current disk is healthy.
> **Trigger when:** psicopompo's `sda` (the NAS `/mnt/BACKUP`) shows **Reallocated_Sector_Ct > 0** OR **Current_Pending_Sector > 0** — same as the kuaray `sdb` case (1 pending → `SmartDiskError` alert firing). Monitored automatically via smartd + Prometheus.

## Context

The homelab NAS is psicopompo's **`sda`** (`ST1000LM024 HN-M101MBB`, 931.5G, SATA 2.5"). It hosts `/mnt/BACKUP` (media, off-box backups, configs) + serves NFSv4 to kavure/kuaray/ybytu/ybyra.

| | Current (`sda`, in the PC) | Candidate (`sdf`, SSHD-1TB USB) |
|---|---|---|
| Model | ST1000LM024 (SpinPoint M8) | ST1000LM014 (Laptop SSHD) |
| Size | 931.5G | 931.5G |
| Format | 2.5" internal SATA | 2.5" SATA (currently via a USB reader) |
| Health (13/09) | ✅ 0 realloc, 0 pending | ✅ 0 realloc, 0 pending |
| Power-on | 17.285h | 22.656h |
| Advantage | — | **NAND cache** (faster repeated reads) |

Both are 2.5" SATA — the SSHD fits in the same internal slot.

## Decision (13/09/2026)

**Do not replace it now.** The `sda` is healthy (0 reallocated, 0 pending = no remapping in progress). The high Load_Cycle count (275k) is characteristic of a 2.5" laptop HDD, not a death sign. The SSHD will stay as **ready reserve** for when the `sda` shows signs.

## Procedure (when needed)

> ⚠️ Downtime of **hours** — the NAS serves 4 hosts via NFS. Schedule it in a maintenance window and warn ahead of time.

1. **Stop the NFS clients:** warn/stop usage on kavure (zomboid/minecraft/valheim/media/n8n/sumaenima), kuaray (music/lidarr), ybytu/ybyra (configs).
2. **Unmount NFS:** `exportfs -au` on psicopompo + `umount` on the clients (optional — `soft` prevents hanging).
3. **Shut down psicopompo.**
4. **Physically:** connect the SSHD (sdf) as an internal SATA disk **in place of the sda** (same slot/power). The sda comes out.
5. **Boot with recovery media** (the SSHD comes from a USB reader, it may have no OS).
6. **Copy the data:** `rsync -a --info=progress2 /mnt/BACKUP/ <destino>` or clone with dd/Clonezilla. 289G used → several hours.
7. **Validate:** `smartctl -a` (0 realloc/pending on the new one), `btrfs check`/`fsck`, mount `/mnt/BACKUP`.
8. **Re-export NFS** (`/etc/exports` kept) + `exportfs -arv`.
9. **Re-mount on the clients** + restart the affected containers (NFS bind `rprivate`).
10. **Test:** `df` on the clients, services Up, media access.

## Less invasive alternative (assess on the spot)

If only the NAS's **data sectors** are sick but the system is fine, consider **adding the SSHD as an extra disk** and migrating `/mnt/BACKUP` to it with rsync (without shutting down the OS), then changing the mount point. Same result with less downtime.

## References

- Monitors: [`services/monitoring.md`](../services/monitoring.md) (`SmartDiskError` alerts) · smartd `sda` on psicopompo
- Backups: [`backups/strategy.md`](../backups/strategy.md) · [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)
- NFS: [`network/nfs.md`](../network/nfs.md)
