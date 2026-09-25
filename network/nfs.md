---
tags: [homelab, network, storage, psicopompo]
---

# NFS — Psicopompo as the Tailnet NAS

The **psicopompo** serves the media libraries (music, books) to the homelab services via **NFSv4**. The apps run where they are (e.g. kuaray) and mount the library remotely — **without syncing files** via Syncthing.

> **Off-box backup standard via NFS:** local→NAS mount with failsafe (reachability/retry/timeout/ntfy) — see [`backups/strategy.md`](../backups/strategy.md).

## Exports (psicopompo)

NFS server on psicopompo (`nfs-utils`), config in `/etc/exports`:

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

- **`async` (since 07/08/2026):** the server replies without waiting for the on-disk flush — it speeds up imports/backups a lot. Switched from `sync` (applied with `exportfs -ra`). Minimal risk: library mirrored on Syncthing (folder `backup`) + off-box backup.

- **`all_squash,anonuid=1000,anongid=1000`:** all clients (even container root) write as `edu` (uid 1000, the library owner). Client root **does not** become root on the server (safe).
- **Restricted to the tailnet IPs** of kuaray (`100.94.209.99`) and kavure (`100.124.146.77`). To add a host, add the IP to the line + re-export (`exportfs -arv`).
- **Firewall (ufw):** ports `2049/tcp` (NFSv4) and `111/tcp` (rpcbind) are open only for the IPs above.
- **Service hardening (20/09/2026):** drop-in `/etc/systemd/system/nfs-server.service.d/tailscale.conf` configured with `After=tailscaled.service network-online.target`, `Wants=tailscaled.service network-online.target`, `Restart=on-failure` and `RestartSec=5s` to avoid post-reboot bind failure (`errno 99`). Miracena export fixed from space to TAB in `/etc/exports`.

## Client mount (kuaray)

`nfs-common` installed; entry in `/etc/fstab`:

```
100.82.51.112:/mnt/BACKUP/media/music /mnt/nas/media/music nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
```

> **Canonical Tailnet NFS Mount Rule:** use **`soft,timeo=30,retrans=2`** and **`x-systemd.mount-timeout=10s`** (no `idle-timeout` for 24/7 Docker mounts) instead of `hard`. If the VPN (Tailscale) drops or the host is powered off before the unmount, the `hard` option causes a kernel deadlock (`hung_task_timeout` in `nfs4_file_flush`), hanging the shutdown indefinitely. With `soft` and short systemd timeouts, the kernel aborts the pending I/O and shuts down cleanly in seconds. **Docker drop-in:** `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`) on all Docker hosts.

> **HDD decoupling (28/08/2026):** the kuaray music mount was moved from `/mnt/storage/data/media/music` → `/mnt/nas/media/music` — **outside the HDD mountpoint** (`/mnt/storage`). Before, an HDD that failed to mount at boot made the NFS path "disappear" and took down the Lidarr library even with the music intact on the NAS (real case on 28/08). Music no longer depends on the HDD. `mkdir -p /mnt/nas/media`.

## Mount on kavure (Zomboid + Sumænimá backup)

kavure fstab (updated 10/09/2026):

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

> **kavure NFS pattern (10/09/2026):** all entries use `soft,timeo=30,retrans=2,nofail` + `x-systemd.mount-timeout=10s`. **No `idle-timeout`** on the mounts that serve 24/7 Docker containers (avoids a race condition with systemd automount at shutdown — "device is busy"). Only `scryfall-mirror` keeps `idle-timeout=60s` (intermittent access). fstab backup: `/etc/fstab.bak.20260910`. **Docker drop-in:** `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`) guarantees that Docker stops before the NFS mounts try to unmount.

- Used by `zomboid-backup`/`zomboid-update` — **local → NFS mirror, no SSH** (avoids the 12h Tailscale SSH `check`). Failsafe/retry/ntfy in `services/zomboid/project-zomboid.md`.
- `zomboid-backup` runs `rsync -a --delete` from `/srv/data/zomboid/data/backups/` → `offbox/daily/`; `zomboid-update` saves the pre-update copy in `offbox/archive/pre-update-<data>/`.

## Mount on ybytu (Oracle Cloud — DNS, dashboard)

ybytu fstab (updated 10/09/2026):

```
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **NFS fix (10/09/2026):** entries `hard` → `soft`. Backup: `/etc/fstab.bak.20260910`. Docker drop-in: `/etc/systemd/system/docker.service.d/nfs-ordering.conf`.

## Mount on ybyra (Oracle Cloud — Swarm edge)

ybyra fstab (updated 10/09/2026):

```
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **NFS fix (10/09/2026):** entries `hard` → `soft`. Backup: `/etc/fstab.bak.20260910`. Docker drop-in: `/etc/systemd/system/docker.service.d/nfs-ordering.conf`.

## Affected containers (kuaray)

The containers use the mount at the **same old path** — no compose change needed:
- **Navidrome (kavure):** bind `/srv/data/navidrome/music → /music`
- **Calibre (kavure):** bind `/srv/data/media/books → /books`
- **Lidarr (kuaray):** bind `/mnt/nas/media/music → /data/media/music` (**decoupled from the HDD on 28/08** — before it was `/mnt/storage/data → /data`, which nested the NFS under the HDD mountpoint; with a failing HDD Lidarr lost the library even with the music safe on the NAS). Bind `/mnt/storage/data/torrents → /data/torrents` kept (downloads on the HDD).

> ⚠️ **Bind mounts use `rprivate` propagation** — host mounts made *after* the container starts do not show up inside it. If the NFS mount is recreated/remounted, **restart** the affected containers (`docker restart lidarr navidrome`).

## Performance and bottleneck (kuaray on WiFi)

- **Local write on psicopompo:** ~1 GB/s (btrfs, fast).
- **NFS write from kuaray:** ~3.6 MB/s — the **bottleneck is kuaray's physical link**, which is on **WiFi** (`wlp6s0`, network "Cratos"; ethernet `enp7s0` with no cable → `unavailable`). Latency to kuaray: 74–190 ms (vs 2 ms on wired kavure).
- ⚠️ `async` helps but **does not solve it**: the limit is the physical route. While kuaray is on WiFi, Lidarr imports/rescans will be slow.
- **Solution:** plug an **ethernet cable** into kuaray's `enp7s0` (expect ~80–110 MB/s). Without a cable, everything works normally — just slowly.
- **kavure** is wired (`192.168.3.41`, 2 ms) — sumaenimā/zomboid NFS with no bottleneck.

## Tests (07/08/2026)

- Mount OK on kuaray: `df -h /mnt/storage/data/media/music` → `100.82.51.112:/mnt/BACKUP/media/music 932G` (5232 files).
- Write OK (Lidarr/root and Transmission): a file created over NFS shows up as `edu:edu` on psicopompo.
- Navidrome + Lidarr restarted and reading the library (60 top-level folders).
- Exports switched `sync` → `async` and re-exported (`exportfs -ra`) — confirmed in `exportfs -v`.

## Cold backup

The same content (all of `/mnt/BACKUP`) is **also** mirrored to kuaray's HDD via **Syncthing** (folder `backup`, receiveonly) — see [`services/syncthing.md`](../services/syncthing.md).

## Boot-race fix (22/09/2026) — bind on the TS IP + tailscaled-wait

**Problem:** `nfs-server` failed at boot with `rpc.nfsd: unable to bind AF_INET TCP socket: errno 99` — the `host=100.82.51.112` (Tailscale IP, per the `ports.md` rule of never binding 0.0.0.0) came up **before tailscaled assigned the IP**.

**Fix (Hellings "NFS Over Tailscale" pattern):**
1. `/usr/local/bin/tailscaled-wait.sh` + `/etc/systemd/system/tailscaled-wait.service` — waits for `tailscale status → BackendState=Running` (60s timeout) before releasing dependents.
2. `nfs-server.service.d/10-tailscaled-wait.conf` → `After/Wants=tailscaled-wait` — **keeps `host=100.82.51.112`** (security rule intact).

**Verified:** UFW restricts `2049/tcp` + `111/tcp` to only the 4 TS clients (kuaray/kavure/ybytu-vnic/ybyra) — clients mount NFSv4 (2049 only); `rpcbind/mountd` bind to 0.0.0.0 (Arch default) but are blocked by UFW for external hosts. **Multi-client:** 40 active exports via 1 bind on the TS IP.
