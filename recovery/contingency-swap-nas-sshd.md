---
tags: [homelab, recovery, storage, psicopompo]
---

# Contingency Plan — NAS Storage Drive Replacement (psicopompo)

> **Status:** Documented (13/09/2026) — **NOT executed**. Active NAS drive remains healthy.  
> **Trigger Conditions:** `sda` on psicopompo (NAS `/mnt/BACKUP`) reports **Reallocated_Sector_Ct > 0** OR **Current_Pending_Sector > 0** — matching the kuaray `sdb` incident (1 pending sector triggering Prometheus `SmartDiskError`). Monitored automatically via smartd + Prometheus.

## Context

The homelab NAS filesystem resides on **`sda`** of psicopompo (`ST1000LM024 HN-M101MBB`, 931.5 GB, 2.5" SATA). Hosts `/mnt/BACKUP` (media, off-box backups, configurations) and exports NFSv4 shares to kavure, kuaray, ybytu, and ybyra.

| Attribute | Active (`sda`, Internal SATA) | Standby Candidate (`sdf`, SSHD-1TB USB) |
|---|---|---|
| Model | ST1000LM024 (SpinPoint M8) | ST1000LM014 (Laptop SSHD) |
| Capacity | 931.5 GB | 931.5 GB |
| Form Factor | 2.5" Internal SATA | 2.5" SATA (currently connected via USB bridge) |
| Health (13/09) | ✅ 0 reallocated, 0 pending | ✅ 0 reallocated, 0 pending |
| Power-On Hours | 17,285h | 22,656h |
| Advantage | — | **NAND Flash Cache** (faster read acceleration) |

Both drives share identical 2.5" SATA form factors — the SSHD fits directly into the internal chassis bay.

## Architectural Decision (13/09/2026)

**Do not replace drive at this time.** Drive `sda` remains healthy (0 reallocated, 0 pending sectors). The elevated Load_Cycle count (275k) is normal behavior for 2.5" laptop HDDs with aggressive head parking, not an indicator of imminent failure. The SSHD is designated as a **hot-standby replacement** ready to deploy upon initial SMART degradation.

## Migration Procedure (When Triggered)

> ⚠️ Requires **several hours** of maintenance downtime — the NAS exports active NFS shares to 4 client nodes. Schedule during an approved maintenance window.

1. **Stop NFS Consumers:** Pause services on kavure (Zomboid, Minecraft, Valheim, media, n8n, Sumænimá), kuaray (media/Lidarr), and ybytu/ybyra (configs).
2. **Unmount NFS Shares:** Run `exportfs -au` on psicopompo + `umount` shares on clients (soft mount flags prevent hangs).
3. **Power down psicopompo.**
4. **Physical Replacement:** Connect SSHD (`sdf`) into internal SATA bay **in place of `sda`**.
5. **Boot into Live Recovery Media** (USB recovery environment).
6. **Replicate Filesystem:** `rsync -a --info=progress2 /mnt/BACKUP/ <destination>` or clone via dd/Clonezilla (~289 GB used).
7. **Validate Integrity:** `smartctl -a` (verify 0 realloc/pending), execute `btrfs check` / `fsck`, mount `/mnt/BACKUP`.
8. **Re-export NFS Shares:** Verify `/etc/exports` and run `exportfs -arv`.
9. **Remount on Clients:** Remount NFS shares and restart container workloads.
10. **Validation:** Verify `df` on clients, ensure all services report healthy, validate media streaming.

## Low-Impact Online Alternative

If only the **storage partition** shows errors while the system remains stable, connect the SSHD as a secondary drive, replicate `/mnt/BACKUP` via live `rsync`, and update the `/etc/fstab` mount point with minimal downtime.

## References

- Observability: [`services/monitoring.md`](../services/monitoring.md) (`SmartDiskError` alerts) · smartd daemon on psicopompo
- Backup Architecture: [`backups/strategy.md`](../backups/strategy.md) · [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)
- Network Filesystem: [`network/nfs.md`](../network/nfs.md)