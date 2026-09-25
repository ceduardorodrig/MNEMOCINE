---
tags: [homelab, tutorial, docker, storage, kavure]
---

# Docker/containerd Disk Cleanup — kavure

Diagnostic and maintenance guide for the space used by Docker/containerd on kavure. Canonized on **13/09/2026** after the cleanup that recovered ~14GB (containerd 51G → 38G; disk 71G → 85G free).

## Why kavure accumulates (root cause, 13/09/2026)

kavure runs **Ubuntu + Docker with the containerd runtime** (`/var/lib/containerd`). The accumulation comes from:

1. **Watchtower updates images but does not remove the old versions that still have a tag** — `WATCHTOWER_CLEANUP=true` only removes *dangling* (`<none>`) images; old tagged images with duplicates (e.g.: `postgres:15-alpine` ×2, `valkey:8-alpine` ×3, `pgvector:pg16` ×2) **stay stuck**.
2. **Orphan replicas from Swarm redeploys** — old tasks (`sae-core_api.1.*`, `sae-core_backup.1.*`) remain as `Exited` containers after `docker stack deploy`; Swarm does not remove them on its own.
3. **Orphan unnamed containers** from containerd — state residue that `docker rm` cannot resolve (it says "No such container" but still lists it). Harmless, it goes away on a docker restart.

> `docker system df` shows these as "RECLAIMABLE" even when they have a tag, because no **active** container uses them — but they are **NOT blindly-removable garbage**: images for on-demand services (Crafty/Zomboid `danixu86/project-zomboid-dedicated-server` 10.4GB, Swarm edge `nginx-sumaenima`/`sumaenima-umami`) show up as "unused" but are needed to bring up on-demand services.

## Cleanup routine (check/run manually)

```bash
# 1. Estado
docker system df
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' | sort -rh | head -25
sudo du -sh /var/lib/containerd

# 2. Containers parados — INVESTIGAR antes de remover (zomboid/minecraft ficam parados de propósito)
docker ps -a --filter status=exited --format '{{.ID}} | {{.Names}} | {{.Image}} | {{.Status}}'
# Réplicas antigas do Swarm (seguras): docker rm <id>
# Container sem nome órfão: deixar (docker rm falha; some no restart)

# 3. Imagens dangling (seguro)
docker image prune -f

# 4. Imagens com tag duplicada sem uso — confirmar com:
for img in $(docker images -q); do
  cnt=$(docker ps -a --filter ancestor=$img -q | wc -l)
  [ "$cnt" = "0" ] && echo "SEM USO: $img $(docker image inspect $img --format '{{.RepoTags}}')"
done
# Depois: docker rmi <ids confirmados sem uso e duplicados>

# 5. NUNCA remover imagens usadas por services Swarm sob demanda (edge_proxy/umami) 
#    nem a do servidor de jogo do Crafty — docker service ls para conferir.
```

> Do **NOT** use `docker system prune -af` blindly: it removes images for on-demand services. Prefer explicit targets (the homelab standard).

## Result of the 13/09/2026 cleanup

| Item | Before | After |
|---|---|---|
| `/var/lib/containerd` | 51G | **38G** |
| `/` disk | 71G free (66%) | **85G free (60%)** |
| Images | 61 (54GB) | 45 (40GB) |
| Dangling | 10 (17GB) | 0 |

Removed: 3 orphan containers (2 Swarm replicas + 1 unnamed) · 10 dangling · 6 duplicate/orphan images (`postgres:15-alpine`, `pgvector:pg16`, `valkey:8-alpine` ×2, `kavita`, `hello-world`).

Preserved (needed on demand): `danixu86/project-zomboid-dedicated-server` (10.4GB, Crafty), `nginx-sumaenima`/`sumaenima-umami` (Swarm edge), `steamcmd`.

## References

- Homelab: [`services/monitoring.md`](../services/monitoring.md) · [`servers/kavure.md`](../servers/kavure.md) · [`guides/docker-disk-cleanup.md`](docker-disk-cleanup.md) (psicopompo, btrfs/snapper)
