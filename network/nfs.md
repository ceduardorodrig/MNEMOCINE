---
tags: [homelab, network, storage, psicopompo]
---

# NFS — Psicopompo as Tailnet NAS Storage Provider

**psicopompo** serves shared media libraries (music, books) and backup staging volumes via **NFSv4** to services across the homelab tailnet. Applications run locally on their respective nodes (e.g. kuaray, kavure) and mount remote storage directly — eliminating redundant multi-node file duplication through Syncthing.

> **Canonical Off-Box Backup Standard via NFS:** Local host mounts to NAS target with structured failsafes (reachability tests, retry logic, strict timeout parameters, and ntfy notifications) — see [`backups/strategy.md`](../backups/strategy.md).

## Server Exports (psicopompo)

Configured via `nfs-utils` on psicopompo in `/etc/exports`:

```text
/mnt/BACKUP/media/music	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/media/books	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/sumaenima-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/zomboid-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/minecraft-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/valheim-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/miracena-server-kavure	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 192.168.3.200(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/configs-homelab	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.115.253.109(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.66.224.34(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/repos/git	100.94.209.99(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.115.253.109(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.66.224.34(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/SSD_SATA/scryfall-mirror	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
/mnt/BACKUP/monitoring-server-kavure	100.124.146.77(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

- **`async` (applied 2026-08-07):** Server acknowledges write operations immediately without waiting for disk synchronization — significantly accelerating remote backups and large imports. Converted from `sync` and reloaded via `exportfs -ra`. Minimal risk: datasets are duplicated in Syncthing (folder `backup`) alongside off-box snapshots.
- **`all_squash,anonuid=1000,anongid=1000`:** All remote client connections (including container root processes) write files under user `edu` (UID 1000, owner of the library). Client root cannot escalate privileges on the server.
- **Access restricted strictly to Tailnet IPs:** kuaray (`100.94.209.99`), kavure (`100.124.146.77`), ybytu (`100.115.253.109`), ybyra (`100.66.224.34`), and local wired LAN (`192.168.3.200`). To authorize a node, append its IP address and reload (`sudo exportfs -arv`).
- **Firewall Filtering (UFW):** Ports `2049/tcp` (NFSv4) and `111/tcp` (rpcbind) are opened only for explicitly whitelisted IP addresses.
- **Service Hardening (2026-09-20):** Drop-in `/etc/systemd/system/nfs-server.service.d/tailscale.conf` enforces `After=tailscaled.service network-online.target`, `Wants=tailscaled.service network-online.target`, `Restart=on-failure`, and `RestartSec=5s` to eliminate socket bind race conditions (`errno 99`) upon system reboot.

## Client Mount Configuration (kuaray)

Installed package `nfs-common`; persistent mount configuration in `/etc/fstab`:

```text
100.82.51.112:/mnt/BACKUP/media/music /mnt/nas/media/music nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/miracena-server-kavure /srv/data/miracena/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **Canonical NFS Mount Rule for Tailnet Environments:**  
> Always specify **`soft,timeo=30,retrans=2`** and **`x-systemd.mount-timeout=10s`** (avoiding `idle-timeout` on continuous 24/7 Docker bind mounts) instead of `hard`. If the Tailscale VPN connection drops or a node reboots unexpectedly, the `hard` mount option causes unrecoverable kernel deadlocks (`hung_task_timeout` inside `nfs4_file_flush`), blocking host shutdowns indefinitely. With `soft` and short systemd timeouts, the kernel terminates pending I/O cleanly within seconds.  
> **Docker Service Drop-in:** Apply `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`) on all Docker nodes.

> **Storage Decoupling (2026-08-28):**  
> Kuaray's music mount was relocated from `/mnt/storage/data/media/music` → `/mnt/nas/media/music` — **outside of the local physical HDD mountpoint** (`/mnt/storage`). Previously, a temporary HDD mount failure at boot concealed the NFS mountpoint and broke Lidarr's music library despite healthy NAS storage. Media access is now completely decoupled from local disk status.

## Client Mount Configuration (kavure)

Persistent `/etc/fstab` on kavure:

```text
100.82.51.112:/mnt/BACKUP/zomboid-server-kavure /srv/data/zomboid/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/sumaenima-server-kavure /srv/data/sumaenimahub/backup nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/minecraft-server-kavure /srv/data/minecraft/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/valheim-server-kavure /srv/data/valheim/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/media/music /srv/data/navidrome/music nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/media/books /srv/data/media/books nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/n8n-server-kavure /srv/data/n8n/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
# n8n-server-kavure mount removed 2026-10-09 (n8n consolidated into Miracena/kuaray), RE-ADDED 2026-10-09
# when the standalone Homelab n8n was reactivated on kavure (see services/n8n.md).
100.82.51.112:/mnt/SSD_SATA/scryfall-mirror /srv/data/scryfall-mirror nfs rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,x-systemd.idle-timeout=60s,nofail 0 0
100.82.51.112:/mnt/BACKUP/monitoring-server-kavure /srv/data/monitoring/offbox nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

> **kavure NFS Standard (2026-09-10):** All active mounts use `soft,timeo=30,retrans=2,nofail` + `x-systemd.mount-timeout=10s`. Mounts hosting 24/7 Docker volumes omit `idle-timeout` to eliminate systemd automount race conditions at shutdown. Only `scryfall-mirror` retains `idle-timeout=60s` due to intermittent batch usage.

- Utilized by `zomboid-backup` and `zomboid-update` — direct local mirror to NFS target without requiring SSH.
- `zomboid-backup` triggers `rsync -a --delete` from `/srv/data/zomboid/data/backups/` → `offbox/daily/`; `zomboid-update` archives snapshots into `offbox/archive/pre-update-<date>/`.

## Client Mount Configuration (ybytu — Oracle Cloud)

`/etc/fstab` on ybytu:

```text
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

## Client Mount Configuration (ybyra — Oracle Cloud Edge)

`/etc/fstab` on ybyra:

```text
100.82.51.112:/mnt/BACKUP/configs-homelab /srv/backup-configs nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
100.82.51.112:/mnt/BACKUP/repos/git /srv/backup-gitrepos nfs4 rw,soft,timeo=30,retrans=2,_netdev,x-systemd.automount,x-systemd.mount-timeout=10s,nofail 0 0
```

## Container Volume Bindings

Application containers map NFS mountpoints using standard directory binds without modifications to Docker Compose definitions:
- **Navidrome (kavure):** bind `/srv/data/navidrome/music → /music`
- **Calibre (kavure):** bind `/srv/data/media/books → /books`
- **Lidarr (kuaray):** bind `/mnt/nas/media/music → /data/media/music` (decoupled from local HDD). Local torrent staging remains bound at `/mnt/storage/data/torrents → /data/torrents`.

> ⚠️ **Container Bind Mounts Use `rprivate` Propagation:**  
> Mounts mounted on the host *after* container startup will not propagate inside the container namespace. If an NFS mount drops and is remounted, restart dependent containers (`docker restart lidarr navidrome`).

## Performance & Throughput Characteristics

- **Local NVMe/SSD write speed on psicopompo:** ~1 GB/s (Btrfs subvolume).
- **Remote NFS write speed from kuaray:** ~3.6 MB/s — the primary throughput bottleneck is the host's physical Wi-Fi connection (`wlp6s0`, SSID "Cratos"; ethernet `enp7s0` disconnected). Ping latency to kuaray ranges between 74–190 ms.
- While `async` improves transmission bursts, physical link saturation remains the limiting factor for batch rescans.
- **kavure Gigabit Link:** Kavure connects via physical Ethernet (`192.168.3.41`) with 0.17–0.28 ms local latency. Operating through the dedicated `IT-BLUE LE-4203` Gigabit switch, measured raw LAN throughput delivers **912 Mbps up / 858 Mbps down** (93% line rate saturation) — see [`topology.md`](topology.md).

## Boot-Race Mitigation (2026-09-22) — Tailscale Binding & tailscaled-wait

**Historical Issue:** `nfs-server` failed at startup with `rpc.nfsd: unable to bind AF_INET TCP socket: errno 99` because the explicit Tailscale IP bind (`host=100.82.51.112`, adhering to zero-trust rules prohibiting `0.0.0.0`) initialized before Tailscaled completed network negotiation.

**Resolution:**
1. Deployed `/usr/local/bin/tailscaled-wait.sh` and `/etc/systemd/system/tailscaled-wait.service` — pauses service dependencies until `tailscale status` confirms `BackendState=Running` (timeout 60s).
2. Service drop-in `/etc/systemd/system/nfs-server.service.d/10-tailscaled-wait.conf` enforces `After=tailscaled-wait.service` and `Wants=tailscaled-wait.service`.
3. Preserves strict Tailscale IP binding on `100.82.51.112` without exposing listening ports across LAN broadcast domains.
