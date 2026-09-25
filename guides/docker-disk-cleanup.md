---
tags: [homelab, tutorial, docker, compose, btrfs, snapper, snapshot, storage, psicopompo]
---

# Docker Disk Cleanup — psicopompo

Diagnostic and maintenance guide for the space used by Docker (`containerd-data` + `docker-data`) on psicopompo. Canonized on **06/09/2026** after the cleanup that reclaimed ~330GB.

## Architecture (why the data lives where it lives)

Docker 29.x uses the **containerd snapshotter**. The data lives in two physical places:

| Directory | Contents | What takes up space |
|---|---|---|
| `/mnt/NVME_PCI/containerd-data` | `io.containerd.snapshotter.v1.overlayfs/snapshots/` (uncompressed layers) + `io.containerd.content.v1.content/` (blobs) | Layers of all images + build leftovers |
| `/mnt/NVME_PCI/docker-data` | `rootfs/overlayfs/` (container mount points), `buildkit/` (cache of the `default` builder), `volumes/` | Build cache + named volumes |

> ⚠️ `du -sh /mnt/NVME_PCI/docker-data/rootfs` **overcounts**: these are overlay mount points whose physical data lives in `containerd-data` (e.g. ~94GB "apparent" when the real size is ~1GB).

### Two builders (06/09: standardized to ONE)

- **`default`** (docker driver) — built into the daemon, **cannot be removed**. The cache lives in `docker-data/buildkit`. That is where ~247GB of cache piled up (old builds / `docker build`).
- ~~`default-builder`~~ (docker-container) — separate BuildKit container created via `docker buildx create`. **Removed on 06/09** — builds here are local/single-arch (amd64) and `default` is sufficient and simpler.
- ~~`kavure`~~ — dead remote builder (endpoint `docker.example.com`, nonexistent) derived from the `kavure` docker context. **Removed on 06/09** (`docker context rm kavure`); `sumaenima-ctl` uses SSH directly and does not depend on it.

## The problem: silent accumulation (~500GB)

psicopompo is the Sumænimá **build node** (all GPU images are built here). This generates:

1. **Build cache** from the `default` builder + the BuildKit container (reached ~247GB + ~99GB).
2. **Orphaned `<none>` images** from rebuilds (reached ~97GB reclaimable) — every `docker compose build` leaves the old layers behind.
3. **Snapper snapshots** pinning the extents — see below.

## The critical detail: btrfs + snapper pin the space

The `nvme` snapper config takes an **hourly timeline of the entire `/mnt/NVME_PCI` subvolume** (which holds the Docker data). A btrfs snapshot = a **reflink** copy: **deleting a file does not free space while a snapshot references it**. That is why `df`/`btrfs usage` does NOT show the space freed after pruning Docker — it only shows up after **deleting the old snapshots**:

```bash
sudo snapper -c nvme list
sudo snapper -c nvme delete --sync <n1> <n2> ...   # --sync libera imediato
```

Snapshots of Docker data (images/cache) **have no rollback value** (they are rebuildable) — you can delete them without regret. The `agentic-ai` vault has its own backup (Syncthing + `/mnt/BACKUP/agentic-ai-server-psicopompo`).

## Cleanup routine (check/run manually)

```bash
# 1. Estado
docker system df                    # imagens / cache / volumes
docker buildx ls                    # builders
docker buildx du                    # cache real por builder
du -sh /mnt/NVME_PCI/containerd-data 2>/dev/null   # se sem root, usar: 
#   docker run --rm -v /mnt/NVME_PCI/containerd-data:/c:ro alpine du -sh /c

# 2. Podar (se o GC automático não deu conta)
docker buildx prune --builder default -af   # cache do builder default
docker image prune -f                       # imagens <none>
docker container prune -f                   # containers parados

# 3. GC do containerd (snapshots órfãos)
pkexec bash -c 'ctr -n moby snapshots gc'

# 4. Liberar espaço pinado pelos snapshots do snapper
sudo snapper -c nvme list
sudo snapper -c nvme delete --sync <antigos>

# 5. Conferir
btrfs filesystem usage /mnt/NVME_PCI
df -h /mnt/NVME_PCI
```

> **Do NOT** use `docker system prune -af` blindly: it removes stopped containers / images of services you want to keep (e.g. WinBoat). Prefer explicit targets.

## Active prevention (06/09/2026)

1. **BuildKit GC in `daemon.json`** — the `default` builder self-limits to 30GB of cache:
   ```json
   "builder": { "gc": { "enabled": true, "defaultKeepStorage": "30GB" } }
   ```
2. **Monthly systemd timer** `docker-prune.timer` (day 01, 04:00) → runs `docker buildx prune --builder default -af` + `docker image prune -f`. Closes the loop with Watchtower (which updates images but does not remove the old ones).
3. **Snapper** keeps pinning recent state (last 8h/7d/4w/3m) — bounded by the 30GB GC. Standardized on 06/09 (see [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)): **rebuildable → no snapshot** (`hdd`/Steam removed, `ssd`/scryfall with no config); **not rebuildable → timeline** (`backup`, `nvme`).

## Result of the 06/09/2026 cleanup

| Item | Before | After |
|---|---|---|
| Images | 103 (~200GB logical) | 18 (~54GB) |
| Build cache | ~346GB | 0B |
| containerd snapshots | 1795 | 164 (all legitimate) |
| `containerd-data` | ~396GB | ~59GB apparent |
| `docker-data` | ~99GB | ~1.8GB real |
| `btrfs` free on NVME_PCI | ~609GB | ~1.16TB (btrfs `Used` 1.22TiB → 652GB) |
| **Total reclaimed** | | **~570GB** (images/cache/snapshots + btrfs block reclaim) |

Config backup: `/etc/docker/daemon.json.bak-gc-20260906`.

## References

- Docker: [Build garbage collection](https://docs.docker.com/build/cache/garbage-collection/) · [Build drivers](https://docs.docker.com/build/builders/drivers/)
- ArchWiki: [Snapper](https://wiki.archlinux.org/title/Snapper) · [snapper-configs(5)](https://man.archlinux.org/man/snapper-configs.5)
- CachyOS wiki: [Btrfs Snapshots](https://wiki.cachyos.org/configuration/btrfs_snapshots/)
- Homelab: [`servers/psicopompo.md`](../servers/psicopompo.md) · [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md) · [`backups/backup-rituals.md`](../backups/backup-rituals.md)