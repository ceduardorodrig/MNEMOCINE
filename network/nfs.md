---
tags: [homelab, network, storage, psicopompo]
---

# NFS — Psicopompo como NAS da Tailnet

O **psicopompo** serve as bibliotecas de mídia (música, livros) via **NFSv4** para os serviços do homelab. Os apps rodam onde estão (ex: kuaray) e montam a biblioteca remotamente — **sem sincronizar arquivos** via Syncthing.

> **Padrão de backup off-box via NFS:** mount local→NAS com failsafe (reachability/retry/timeout/ntfy) — ver [`backups/strategy.md`](../backups/strategy.md).

## Exports (psicopompo)

Servidor NFS no psicopompo (`nfs-utils`), config em `/etc/exports`:

```
/mnt/BACKUP/media/music	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/media/books	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/sumaenima-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/zomboid-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/minecraft-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/valheim-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/miracena-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/configs-homelab	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.115.253.109(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.66.224.34(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/repos/git	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.115.253.109(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.66.224.34(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/SSD_SATA/scryfall-mirror	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/monitoring-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

- **`async` (desde 07/08/2026):** o servidor responde sem aguardar flush em disco — acelera muito imports/backups. Trocado de `sync` (aplicado com `exportfs -ra`). Risco mínimo: biblioteca espelhada no Syncthing (folder `backup`) + backup off-box.

- **`all_squash,anonuid=1000,anongid=1000`:** todos os clientes (mesmo root de container) escrevem como `edu` (uid 1000, dono da biblioteca). Root do cliente **não** vira root no servidor (seguro).
- **Restrito aos IPs tailnet** do kuaray (`100.94.209.99`) e kavure (`100.124.146.77`). Para adicionar host, inclua o IP na linha + reexporte (`exportfs -arv`).
- **Firewall (ufw):** portas `2049/tcp` (NFSv4) e `111/tcp` (rpcbind) liberadas só para os IPs acima.
- **Blindagem do serviço (20/09/2026):** Drop-in `/etc/systemd/system/nfs-server.service.d/tailscale.conf` configurado com `After=tailscaled.service network-online.target`, `Wants=tailscaled.service network-online.target`, `Restart=on-failure` e `RestartSec=5s` para evitar falha de bind (`errno 99`) pós-reboot. Export do Miracena corrigido de espaço para TAB no `/etc/exports`.

## Montagem no cliente (kuaray)

`nfs-common` instalado; entrada no `/etc/fstab`:

```
100.82.51.112:/mnt/BACKUP/media/music /mnt/nas/media/music nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

> **Regra Canônica de Montagem NFS via Tailnet:** Usar **`soft,timeo=30,retrans=2`** e **`x-systemd.mount-timeout=10s`** (sem `idle-timeout` para mounts Docker 24/7) em vez de `hard`. Se a VPN (Tailscale) cair ou o host for desligado antes do unmount, a opção `hard` causa deadlock no kernel (`hung_task_timeout` em `nfs4_file_flush`), travando o shutdown indefinidamente. Com `soft` e timeouts curtos do systemd, o kernel aborta I/O pendente e desliga limpo em segundos. **Drop-in Docker:** `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`) em todos os hosts Docker.

> **Desacoplamento do HDD (28/08/2026):** o mount de música do kuaray foi movido de `/mnt/storage/data/media/music` → `/mnt/nas/media/music` — **fora do mountpoint do HDD** (`/mnt/storage`). Antes, um HDD que não montava no boot fazia o caminho do NFS "sumir" e derrubava a biblioteca do Lidarr mesmo com a música intacta no NAS (caso real 28/08). Agora a música não depende mais do HDD. `mkdir -p /mnt/nas/media`.

## Montagem no kavure (backup do Zomboid + Sumænimá)

fstab do kavure (atualizado 10/09/2026):

```
100.82.51.112:/mnt/BACKUP/zomboid-server-kavure /srv/data/zomboid/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/sumaenima-server-kavure /srv/data/sumaenimahub/backup nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/minecraft-server-kavure /srv/data/minecraft/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/valheim-server-kavure /srv/data/valheim/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/media/music /srv/data/navidrome/music nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/media/books /srv/data/media/books nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/n8n-server-kavure	/srv/data/n8n/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/miracena-server-kavure /srv/data/miracena/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/monitoring-server-kavure /srv/data/monitoring/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **Padrão NFS kavure (10/09/2026):** Todos os entries usam `soft,timeo=30,retrans=2,nofail` + `x-systemd.mount-timeout=10s`. **Sem `idle-timeout`** nos mounts que servem containers Docker 24/7 (evita race condition com systemd automount no shutdown — "device is busy"). Apenas `scryfall-mirror` mantém `idle-timeout=60s` (acesso intermitente). Backup do fstab: `/etc/fstab.bak.20260910`. **Drop-in Docker:** `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`) garante que Docker para antes dos mounts NFS tentarem desmontar.

- Usado por `zomboid-backup`/`zomboid-update` — **espelho local → NFS, sem SSH** (evita o `check` de 12h do Tailscale SSH). Failsafe/retry/ntfy em `services/zomboid/project-zomboid.md`.
- `zomboid-backup` faz `rsync -a --delete` de `/srv/data/zomboid/data/backups/` → `offbox/daily/`; `zomboid-update` salva o pré-update em `offbox/archive/pre-update-<data>/`.

## Montagem no ybytu (Oracle Cloud — DNS, dashboard)

fstab do ybytu (atualizado 10/09/2026):

```
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **Fix NFS (10/09/2026):** Entries `hard` → `soft`. Backup: `/etc/fstab.bak.20260910`. Drop-in Docker: `/etc/systemd/system/docker.service.d/nfs-ordering.conf`.

## Montagem no ybyra (Oracle Cloud — borda Swarm)

fstab do ybyra (atualizado 10/09/2026):

```
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **Fix NFS (10/09/2026):** Entries `hard` → `soft`. Backup: `/etc/fstab.bak.20260910`. Drop-in Docker: `/etc/systemd/system/docker.service.d/nfs-ordering.conf`.

## Containers afetados (kuaray)

Os containers usam o mount **no mesmo caminho antigo** — sem alterar compose:
- **Navidrome (kavure):** bind `/srv/data/navidrome/music → /music`
- **Calibre (kavure):** bind `/srv/data/media/books → /books`
- **Lidarr (kuaray):** bind `/mnt/nas/media/music → /data/media/music` (**desacoplado do HDD 28/08** — antes era `/mnt/storage/data → /data`, o que aninhava o NFS sob o mountpoint do HDD; com HDD falho o Lidarr perdia a biblioteca mesmo com a música segura no NAS). Bind `/mnt/storage/data/torrents → /data/torrents` mantido (downloads no HDD).

> ⚠️ **Bind mounts usam propagação `rprivate`** — mounts do host feitos *depois* do start do container não aparecem dentro dele. Se o mount NFS for recriado/remontado, **reinicie** os containers afetados (`docker restart lidarr navidrome`).

## Performance e gargalo (kuaray em WiFi)

- **Escrita local no psicopompo:** ~1 GB/s (btrfs, rápido).
- **Escrita NFS a partir do kuaray:** ~3,6 MB/s — o **gargalo é o link físico do kuaray**, que está em **WiFi** (`wlp6s0`, rede "Cratos"; ethernet `enp7s0` sem cabo → `unavailable`). Latência até o kuaray: 74–190 ms (vs 2 ms do kavure, wired).
- ⚠️ O `async` ajuda, mas **não resolve**: o limite é a rota física. Enquanto o kuaray estiver em WiFi, imports/rescans do Lidarr serão lentos.
- **Solução:** plugar **cabo de rede** no `enp7s0` do kuaray (esperado ~80–110 MB/s). Sem cabo, a funcionalidade opera normalmente — apenas lento.
- O **kavure** é wired (`192.168.3.41`, 2 ms) — NFS do sumaenimā/zomboid sem gargalo.

## Testes (07/08/2026)

- Mount OK no kuaray: `df -h /mnt/storage/data/media/music` → `100.82.51.112:/mnt/BACKUP/media/music 932G` (5232 arquivos).
- Escrita OK (Lidarr/root e Transmission): arquivo criado via NFS aparece como `edu:edu` no psicopompo.
- Navidrome + Lidarr reiniciados e lendo a biblioteca (60 pastas de topo).
- Exports trocadas `sync` → `async` e re-exportadas (`exportfs -ra`) — confirmado em `exportfs -v`.

## Backup frio

O mesmo conteúdo (`/mnt/BACKUP` inteiro) é **também** espelhado no HD do kuaray via **Syncthing** (folder `backup`, receiveonly) — ver [`services/syncthing.md`](../services/syncthing.md).

## Boot-race fix (22/09/2026) — bind em IP TS + tailscaled-wait

**Problema:** `nfs-server` falhava no boot com `rpc.nfsd: unable to bind AF_INET TCP socket: errno 99` — o `host=100.82.51.112` (IP Tailscale, conforme regra `ports.md` de nunca bindar 0.0.0.0) subia **antes do tailscaled atribuir o IP**.

**Fix (padrão Hellings "NFS Over Tailscale"):**
1. `/usr/local/bin/tailscaled-wait.sh` + `/etc/systemd/system/tailscaled-wait.service` — espera `tailscale status → BackendState=Running` (timeout 60s) antes de liberar dependentes.
2. `nfs-server.service.d/10-tailscaled-wait.conf` → `After/Wants=tailscaled-wait` — **mantém `host=100.82.51.112`** (regra de segurança intacta).

**Conferido:** UFW restringe `2049/tcp` + `111/tcp` só aos 4 clientes TS (kuaray/kavure/ybytu-vnic/ybyra) — clientes montam NFSv4 (só 2049); `rpcbind/mountd` bindam 0.0.0.0 (default Arch) mas bloqueados pelo UFW p/ hosts externos. **Multi-cliente:** 40 exports ativos via 1 bind no IP TS.
