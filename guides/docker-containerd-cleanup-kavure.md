---
tags: [homelab, tutorial, docker, storage, kavure]
---

# Docker/containerd Disk Cleanup — kavure

Guia de diagnóstico e manutenção do espaço usado por Docker/containerd no kavure. Canonizado em **13/09/2026** após a limpeza que recuperou ~14GB (containerd 51G → 38G; disco 71G → 85G livres).

## Por que o kavure acumula (causa raiz, 13/09/2026)

O kavure roda **Ubuntu + Docker com runtime containerd** (`/var/lib/containerd`). O acumulado vem de:

1. **Watchtower atualiza imagens mas não remove as versões antigas que ainda têm tag** — `WATCHTOWER_CLEANUP=true` só remove *dangling* (`<none>`); imagens antigas com tag duplicada (ex.: `postgres:15-alpine` ×2, `valkey:8-alpine` ×3, `pgvector:pg16` ×2) **ficam presas**.
2. **Réplicas órfãs de redeploys do Swarm** — tasks antigas (`sae-core_api.1.*`, `sae-core_backup.1.*`) ficam como containers `Exited` após `docker stack deploy`; o Swarm não as remove sozinho.
3. **Containers sem nome órfãos** do containerd — resíduo de estado que `docker rm` não resolve (diz "No such container" mas lista). Inofensivo, some no restart do docker.

> O `docker system df` mostra essas como "RECLAIMABLE" mesmo com tag, porque nenhum container **ativo** as usa — mas **NÃO é lixo removível às cegas**: imagens de serviços sob demanda (Crafty/Zomboid `danixu86/project-zomboid-dedicated-server` 10.4GB, Swarm edge `nginx-sumaenima`/`sumaenima-umami`) aparecem "não usadas" mas são necessárias para subir serviços sob demanda.

## Rotina de limpeza (verificar/rodar manualmente)

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

> **NÃO** usar `docker system prune -af` cegamente: remove imagens de serviços sob demanda. Prefira alvos explícitos (padrão homelab).

## Resultado da limpeza de 13/09/2026

| Item | Antes | Depois |
|---|---|---|
| `/var/lib/containerd` | 51G | **38G** |
| Disco `/` | 71G livres (66%) | **85G livres (60%)** |
| Imagens | 61 (54GB) | 45 (40GB) |
| Dangling | 10 (17GB) | 0 |

Removidos: 3 containers órfãos (2 réplicas Swarm + 1 sem nome) · 10 dangling · 6 imagens duplicadas/órfãs (`postgres:15-alpine`, `pgvector:pg16`, `valkey:8-alpine` ×2, `kavita`, `hello-world`).

Preservadas (necessárias sob demanda): `danixu86/project-zomboid-dedicated-server` (10.4GB, Crafty), `nginx-sumaenima`/`sumaenima-umami` (Swarm edge), `steamcmd`.

## Referências

- Homelab: [`services/monitoring.md`](../services/monitoring.md) · [`servers/kavure.md`](../servers/kavure.md) · [`guides/docker-disk-cleanup.md`](docker-disk-cleanup.md) (psicopompo, btrfs/snapper)