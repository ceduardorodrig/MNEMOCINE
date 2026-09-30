---
tags: [homelab, tutorial, docker, compose, btrfs, snapper, snapshot, storage, psicopompo]
---

# Docker Disk Cleanup — psicopompo

Guia de diagnóstico e manutenção do espaço usado por Docker (`containerd-data` + `docker-data`) no psicopompo. Canonizado em **06/09/2026** após a limpeza que recuperou ~330GB.

## Arquitetura (por que os dados ficam onde ficam)

O Docker 29.x usa o **containerd snapshotter**. Os dados ficam em dois lugares físicos:

| Pasta | Conteúdo | O que ocupa espaço |
|---|---|---|
| `/mnt/NVME_PCI/containerd-data` | `io.containerd.snapshotter.v1.overlayfs/snapshots/` (camadas descompactadas) + `io.containerd.content.v1.content/` (blobs) | Camadas de todas as imagens + resíduo de builds |
| `/mnt/NVME_PCI/docker-data` | `rootfs/overlayfs/` (mount points dos containers), `buildkit/` (cache do builder `default`), `volumes/` | Cache de build + volumes nomeados |

> ⚠️ `du -sh /mnt/NVME_PCI/docker-data/rootfs` **superconta**: são mount points de overlay cujos dados físicos vivem no `containerd-data` (ex.: ~94GB "aparentes" quando o real é ~1GB).

### Dois builders (06/09: padronizado para UM)

- **`default`** (docker driver) — embutido no daemon, **não pode ser removido**. Cache vive em `docker-data/buildkit`. Foi onde ~247GB de cache acumularam (builds antigos / `docker build`).
- ~~`default-builder`~~ (docker-container) — container BuildKit separado via `docker buildx create`. **Removido em 06/09** — builds aqui são locais/single-arch (amd64) e o `default` é suficiente e mais simples.
- ~~`kavure`~~ — builder remoto morto (endpoint `docker.example.com`, inexistente) derivado do docker context `kavure`. **Removido em 06/09** (`docker context rm kavure`); `sumaenima-ctl` usa SSH direto e não depende disso.

## O problema: acúmulo silencioso (~500GB)

O psicopompo é o **build-node** do Sumænimá (todas as imagens GPU são buildadas aqui). Isso gera:

1. **Build cache** do builder `default` + do container BuildKit (chegou a ~247GB + ~99GB).
2. **Imagens órfãs `<none>`** de rebuilds (chegou a ~97GB reclamáveis) — cada `docker compose build` deixa as camadas velhas.
3. **Snapshots do snapper** pinnando os extents — ver abaixo.

## O detalhe crítico: btrfs + snapper pregam o espaço

O snapper `nvme` faz **timeline por hora do subvolume inteiro `/mnt/NVME_PCI`** (que contém os dados Docker). Snapshot btrfs = cópia **reflink**: **deletar arquivo não libera espaço enquanto um snapshot o referenciar**. Por isso o `df`/`btrfs usage` NÃO mostra o espaço liberado após podar o Docker — só sobe depois de **deletar os snapshots antigos**:

```bash
sudo snapper -c nvme list
sudo snapper -c nvme delete --sync <n1> <n2> ...   # --sync libera imediato
```

Snapshots de dados Docker (imagens/cache) **não têm valor de rollback** (são reconstruíveis) — pode deletar sem dó. O vault `agentic-ai` tem backup próprio (Syncthing + `/mnt/BACKUP/agentic-ai-server-psicopompo`).

## Rotina de limpeza (verificar/rodar manualmente)

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

> **NÃO** usar `docker system prune -af` cegamente: remove containers parados/imagens de serviços que se quer manter (ex.: WinBoat). Prefira alvos explícitos.

## Prevenção ativa (06/09/2026)

1. **GC do BuildKit no `daemon.json`** — o builder `default` se auto-limita a 30GB de cache:
   ```json
   "builder": { "gc": { "enabled": true, "defaultKeepStorage": "30GB" } }
   ```
2. **Timer systemd mensal** `docker-prune.timer` (dia 01, 04:00) → roda `docker buildx prune --builder default -af` + `docker image prune -f`. Fecha o ciclo com o Watchtower (que atualiza imagens mas não remove as antigas).
3. **Snapper** continua pinnando o estado recente (últimas 8h/7d/4w/3m) — bounded pelo GC de 30GB. Padronização 06/09 (ver [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)): **reconstruível → sem snapshot** (`hdd`/Steam removido, `ssd`/scryfall sem config); **não reconstruível → timeline** (`backup`, `nvme`).

## Resultado da limpeza de 06/09/2026

| Item | Antes | Depois |
|---|---|---|
| Imagens | 103 (~200GB lógicos) | 18 (~54GB) |
| Build cache | ~346GB | 0B |
| Snapshots containerd | 1795 | 164 (todas legítimas) |
| `containerd-data` | ~396GB | ~59GB aparentes |
| `docker-data` | ~99GB | ~1.8GB reais |
| `btrfs` livre no NVME_PCI | ~609GB | ~1.16TB (btrfs `Used` 1.22TiB → 652GB) |
| **Total recuperado** | | **~570GB** (imagens/cache/snapshots + reclaim de blocos btrfs) |

Backup do config: `/etc/docker/daemon.json.bak-gc-20260906`.

## Referências

- Docker: [Build garbage collection](https://docs.docker.com/build/cache/garbage-collection/) · [Build drivers](https://docs.docker.com/build/builders/drivers/)
- ArchWiki: [Snapper](https://wiki.archlinux.org/title/Snapper) · [snapper-configs(5)](https://man.archlinux.org/man/snapper-configs.5)
- CachyOS wiki: [Btrfs Snapshots](https://wiki.cachyos.org/configuration/btrfs_snapshots/)
- Homelab: [`servers/psicopompo.md`](../servers/psicopompo.md) · [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md) · [`backups/backup-rituals.md`](../backups/backup-rituals.md)