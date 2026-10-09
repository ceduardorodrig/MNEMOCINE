---
tags: [homelab, tutorial, docker, compose, btrfs, snapper, snapshot, storage, psicopompo]
---

# Docker Disk Cleanup — psicopompo

Diagnostic and operational manual for reclaiming disk space consumed by Docker (`containerd-data` and `docker-data`) on psicopompo. Canonized on **2026-09-06** following maintenance that recovered ~330 GB of storage.

## Architecture & Storage Layout

Docker 29.x utilizes the **containerd snapshotter**. Persistent data resides across two dedicated filesystem locations:

| Directory Path | Contents | Space Consumption Mechanics |
|---|---|---|
| `/mnt/NVME_PCI/containerd-data` | `io.containerd.snapshotter.v1.overlayfs/snapshots/` (unpacked layer trees) + `io.containerd.content.v1.content/` (blob cache) | Uncompressed image layers + residual build layers |
| `/mnt/NVME_PCI/docker-data` | `rootfs/overlayfs/` (container overlay mount points), `buildkit/` (`default` builder cache), `volumes/` | Build cache blobs + named persistent volumes |

> ⚠️ Running `du -sh /mnt/NVME_PCI/docker-data/rootfs` **drastically double-counts storage**: these are virtual overlayfs mount points whose backing physical data lives in `containerd-data` (e.g., displaying ~94 GB apparent usage when actual allocation is ~1 GB).

> 🛑 **Zombie Container Warning (Documented on kavure, 2026-10-02):** Deleting image layers without first pruning registered stopped containers causes corrupt filesystem references. On daemon restart, systemd logs fill with `failed to load container mount … RW layer not found` and containers appear as **nameless `[Dead]` entries**. These cannot be purged via `docker rm` or `container prune`.
>
> Remediation requires manual directory cleanup:
> ```bash
> sudo rm -rf /var/lib/docker/containers/<64_HEX_CONTAINER_ID>
> ```
> **Prevention:** Always remove stopped containers (`docker container prune -f`) prior to pruning layer snapshots. Never manually purge `snapshots/` or `content/` with `rm -rf`.

### Builder Consolidation (2026-09-06)

- **`default`** (docker driver) — Built into the Docker daemon; **cannot be removed**. Cache resides in `docker-data/buildkit`. This accumulated ~247 GB of historical build layers.
- ~~`default-builder`~~ (docker-container) — Standalone BuildKit container previously created via `docker buildx create`. **Removed on 2026-09-06** — local builds are single-architecture (`amd64`), making the default builder simpler and lower-overhead.
- ~~`kavure`~~ — Stale remote builder context pointing to legacy non-existent endpoints. **Removed on 2026-09-06** via `docker context rm kavure`.

## Problem Analysis: Silent Storage Accumulation (~500 GB)

As the primary GPU build node, psicopompo experiences substantial storage churn:

1. **BuildKit Cache:** Default builder and BuildKit containers stored ~346 GB of untracked cache artifacts.
2. **Dangling `<none>` Images:** Repeated builds leave orphaned intermediate layers (~97 GB reclaimable).
3. **Btrfs Snapper Snapshot Pinning:** Snapper snapshot references prevent filesystem extent deallocation.

## Critical Interaction: Btrfs + Snapper Extent Retention

The `nvme` Snapper configuration creates hourly timeline snapshots of the `/mnt/NVME_PCI` subvolume. Because Btrfs uses Copy-on-Write (CoW) reflinks, **deleting files from the active filesystem does not free storage blocks if an existing snapshot references those extents**. Space reclamation appears in `df` or `btrfs filesystem usage` only after deleting historical snapshots:

```bash
sudo snapper -c nvme list
sudo snapper -c nvme delete --sync <snapshot_ids...>   # --sync forces synchronous extent release
```

> Snapshots covering Docker cache or intermediate layers have zero disaster recovery value. Live application databases and configuration repositories are independently protected via Syncthing, Restic, and `/mnt/BACKUP/configs-homelab`.

## Recommended Cleanup Workflow

```bash
# 1. Inspect current allocations
docker system df
docker buildx ls
docker buildx du

# 2. Prune unused artifacts
docker buildx prune --builder default -af   # Clear BuildKit cache
docker image prune -f                       # Remove dangling images
docker container prune -f                   # Remove stopped containers

# 3. Clean containerd orphaned snapshots
sudo ctr -n moby snapshots gc

# 4. Release Btrfs extents held by historical Snapper snapshots
sudo snapper -c nvme list
sudo snapper -c nvme delete --sync <old_snapshot_ids...>

# 5. Verify actual disk space reclamation
btrfs filesystem usage /mnt/NVME_PCI
df -h /mnt/NVME_PCI
```

> **Caution:** Avoid blind `docker system prune -af` invocations, as this will purge stopped utility containers and images intended for on-demand use (such as gaming runtimes or WinBoat). Target specific subsystems explicitly.

## Active Automated Governance (2026-09-06)

1. **BuildKit Daemon GC:** Configured in `/etc/docker/daemon.json` to enforce an automatic 30 GB cache limit:
   ```json
   "builder": { "gc": { "enabled": true, "defaultKeepStorage": "30GB" } }
   ```
2. **Monthly Systemd Timer:** `docker-prune.timer` executes on the 1st of every month at 04:00, purging stale build cache and untagged images.
3. **Snapper Policy Optimization:** Transient caches (`/mnt/NVME_PCI/containerd-data`) are excluded from extended backup retention; critical subvolumes maintain a bounded rolling timeline.

## Results of the 2026-09-06 Reclamation

| Metric | Before Cleanup | Post-Cleanup |
|---|---|---|
| Total Images | 103 (~200 GB logical) | 18 (~54 GB) |
| Build Cache | ~346 GB | 0 B |
| Containerd Snapshots | 1,795 | 164 (active layers only) |
| `containerd-data` | ~396 GB | ~59 GB |
| `docker-data` | ~99 GB | ~1.8 GB |
| Free Btrfs Space | ~609 GB | ~1.16 TB |
| **Total Reclaimed Space** | | **~570 GB** |

Configuration backup archived at `/etc/docker/daemon.json.bak-gc-20260906`.

## References

- Docker Documentation: [Build garbage collection](https://docs.docker.com/build/cache/garbage-collection/)
- ArchWiki: [Snapper](https://wiki.archlinux.org/title/Snapper)
- CachyOS Documentation: [Btrfs Snapshots](https://wiki.cachyos.org/configuration/btrfs_snapshots/)
- Internal Infrastructure: [`servers/psicopompo.md`](../servers/psicopompo.md) · [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)