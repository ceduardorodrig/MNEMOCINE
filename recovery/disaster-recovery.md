---
tags: [homelab, recovery, backup, checklist]
---

# Disaster Recovery — Mnemocine

> Guia **único** de recuperação (substitui os antigos `*-disaster-recovery.md` e `playbook.md`).
> **Fontes:** espelho NAS · restic · git GitHub `mnemocine` · rclone→Drive · etckeeper · snapper · syncthing.
> **Regra de ouro:** backup que nunca foi restaurado não existe → **drill mensal** (`backups/backup-rituals.md`).

## 1. Fontes de recuperação

| Fonte | Restaura | Onde |
|---|---|---|
| **Espelho NAS** | Configs + composes de todos os hosts | `/mnt/BACKUP/configs-homelab/{host}/` |
| **restic** | Histórico/versões de configs + vault | `/mnt/BACKUP/repos/restic/configs` (`--insecure-no-password`) |
| **git GitHub `mnemocine`** | Configs versionadas | repo privado `ceduardorodrig/mnemocine` |
| **rclone → Google Drive** | **Off-site** — tudo do `/mnt/BACKUP` | pasta `BACKUP MNEMOCINE` |
| **etckeeper** | `/etc` de cada host | bare repos `/mnt/BACKUP/repos/git/etckeeper-{host}.git` |
| **snapper** | Snapshots btrfs do psicopompo | configs `nvme`/`backup`/`hdd`/`root` |
| **syncthing** | Vault + espelho `backup` | kuaray (receiveonly) |

## 2. Procedimento genérico de restore (qualquer host)

1. **SO + Docker/compose** (ver papel do host na seção 4).
2. **Configs/composes:** `git clone https://github.com/ceduardorodrig/mnemocine` (ou copiar do espelho NAS) → `/home/{user}/homelab/`; `/etc` via etckeeper (`git clone /srv/backup-gitrepos/etckeeper-{host}.git`).
3. **Subir serviços:** `for d in /home/{user}/homelab/*/; do (cd "$d" && docker compose up -d); done`.
4. **Dados:** `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password restore latest --target /` ou NFS.
5. **Verificar** (seção 5).

## 3. Ordem de recuperação (dependências cruzadas)

> **psicopompo PRIMEIRO** — é o NAS/backup hub. Os demais dependem do NFS/espelho.

### Perda total do psicopompo (incluindo /mnt/BACKUP)
A fonte passa a ser o **rclone off-site** (Google Drive, `BACKUP MNEMOCINE`, sem criptografia):

1. Recriar o psicopompo (SO + NFS + Docker).
2. `rclone sync "gdrive:BACKUP MNEMOCINE" /mnt/BACKUP` (baixar tudo).
3. Re-exportar NFS (`/etc/exports`) + `exportfs -arv`.
4. Restaurar vault: `/mnt/BACKUP/agentic-ai-server-psicopompo/agentic-ai` → `/mnt/NVME_PCI/agentic-ai`.
5. Segredos: store sops (`secrets.enc.env` no vault) — chave age deve estar no KeePassXC.

> ⚠️ Se nem o Drive estiver disponível: **etckeeper + espelho dos clientes** (`/mnt/BACKUP/configs-homelab/*` é a única cópia completa — priorize `psicopompo`, `kavure`, `kuaray`).

## 4. Por servidor (papel atual 09/08)

| Host | Papel | Restore específico |
|---|---|---|
| **psicopompo** | NAS/NFS, vault, GPU workers, build-node | btrfs (snapper `nvme`/`backup`/`hdd`), restic, rclone off-site |
| **kavure** | Jogos (Zomboid/Minecraft), Swarm sae-core, HA, Pi-hole, Navidrome, Calibre, AIOStreams, Comet | composes `/srv/data/*/compose.yml`; jogos via NFS off-box; música/livros via NFS |
| **kuaray** | arr-stack (lidarr/prowlarr/transmission/slskd/soularr/flaresolverr), syncthing, vert | composes `/home/kuaray/homelab/*/compose.yml` |

> **Segredos pós-restore (28/08/2026):** API keys do arr-stack e `secrets.yaml` do HA estão no **store sops** — após restaurar os configs, rodar `inject-secrets.sh` (psicopompo) para re-injetar os valores (com `.bak`). Ver `guides/secrets-centralizados.md`.
| **ybytu** | DNS (AdGuard), Homepage, Uptime Kuma, ntfy, changedetection | composes `/home/ubuntu/homelab/*/` |
| **ybyra** | Borda primária (sae-edge) | compose `/home/ubuntu/docker-compose.ybyra.yml` |

## 5. Verificação pós-restore

- `docker ps` — todos os containers **Up**.
- Homepage HTTP 200 (`http://ybytu:3001`).
- DNS resolve — `dig @100.124.146.77 google.com` (pihole kavure) e AdGuard ybytu.
- NFS montado nos clientes — `df /mnt/BACKUP` (kavure/kuaray).
- Vault presente — `/mnt/NVME_PCI/agentic-ai` (psicopompo).
- Off-site — `/srv/health/rclone-gdrive-last-ok` recente.

## 6. Ritual de manutenção

- **Drill mensal:** restaurar 1 config do restic + 1 do git (ver `backups/backup-rituals.md`).
- **Off-site:** conferir `rclone about gdrive:` (quota) + health file.
- **Snapper:** `snapper -c nvme list` (semana OK).
- Atualizar este doc sempre que serviços mudarem de host (regra canônica AGENTS.md).
