---
tags: [homelab, tutorial, docker, storage, kavure]
---

# Docker/containerd Disk Cleanup — kavure

Diagnostic and maintenance runbook for disk space utilized by Docker and containerd runtimes on kavure. Canonized on **2026-09-13** following a cleanup session that reclaimed ~14 GB (containerd 51 GB → 38 GB; root disk free space 71 GB → 85 GB).

## Root Causes of Storage Growth on kavure (2026-09-13)

kavure runs **Ubuntu 24.04 LTS with Docker backed by containerd** (`/var/lib/containerd`). Space accumulation originates from three distinct factors:

1. **Watchtower retains superseded image tags** — `WATCHTOWER_CLEANUP=true` only purges dangling (`<none>`) layers. Historical images with identical repository tags (`postgres:15-alpine` ×2, `valkey:8-alpine` ×3, `pgvector:pg16` ×2) remain pinned in storage.
2. **Orphaned Swarm Replica Tasks** — Older task containers (`sae-core_api.1.*`, `sae-core_backup.1.*`) persist in `Exited` status after `docker stack deploy`; Swarm does not prune these automatically.
3. **Nameless Container Residuals** — Transient containerd state anomalies that `docker rm` fails to unlink ("No such container"). These automatically clear on Docker daemon restart.

> `docker system df` displays these images as "RECLAIMABLE" even when tagged because no *active* container references them. **Do NOT blindly delete them**: on-demand services (Crafty/Zomboid `danixu86/project-zomboid-dedicated-server` 10.4 GB, Swarm edge proxies `nginx-sumaenima`/`sumaenima-umami`) appear idle but are required when starting seasonal game or edge workloads.

## Recommended Maintenance Routine

```bash
# 1. Inspect current allocations
docker system df
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' | sort -rh | head -25
sudo du -sh /var/lib/containerd

# 2. Check stopped containers (verify intentional idle services like Zomboid/Minecraft first)
docker ps -a --filter status=exited --format '{{.ID}} | {{.Names}} | {{.Image}} | {{.Status}}'
# Prune old Swarm replicas safely: docker rm <id>

# 3. Prune dangling layers
docker image prune -f

# 4. Identify tagged images without active references:
for img in $(docker images -q); do
  cnt=$(docker ps -a --filter ancestor=$img -q | wc -l)
  [ "$cnt" = "0" ] && echo "UNUSED: $img $(docker image inspect $img --format '{{.RepoTags}}')"
done
# Remove confirmed duplicate/unneeded images: docker rmi <ids...>

# 5. NEVER delete images required by on-demand Swarm services or Crafty game servers
#    Run `docker service ls` and `docker compose ls` to confirm.
```

> **Caution:** Avoid blind `docker system prune -af` invocations, as this wipes cached game server images and on-demand proxies. Target explicit images and stopped tasks.

## Cleanup Results (2026-09-13)

| Component | Initial State | Post-Cleanup |
|---|---|---|
| `/var/lib/containerd` | 51 GB | **38 GB** |
| Root Disk (`/`) | 71 GB free (66% used) | **85 GB free (60% used)** |
| Total Images | 61 (54 GB) | 45 (40 GB) |
| Dangling Layers | 10 (17 GB) | 0 B |

**Removed Artifacts:** 3 orphaned containers (2 old Swarm replicas + 1 unlinked task); 10 dangling image layers; 6 duplicate/obsolete images (`postgres:15-alpine`, `pgvector:pg16`, `valkey:8-alpine` ×2, `kavita`, `hello-world`).

**Preserved On-Demand Assets:** `danixu86/project-zomboid-dedicated-server` (10.4 GB), `nginx-sumaenima`/`sumaenima-umami` (Swarm edge), and `steamcmd`.

## References

- Homelab Documentation: [`services/monitoring.md`](../services/monitoring.md) · [`servers/kavure.md`](../servers/kavure.md) · [`guides/docker-disk-cleanup.md`](docker-disk-cleanup.md)