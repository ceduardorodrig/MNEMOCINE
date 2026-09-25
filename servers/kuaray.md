---
tags: [homelab, server, kuaray, docker, storage, media, home-assistant, automation]
---

# kuaray

> ## ⚠️ DEPRECATED (28/08/2026)
> Node **removed from the active topology** — out of any operational role in the homelab and in Sumænimá.
> Sumænimá deploys (frontend/edge) **no longer** include kuaray (see `deploy.py` / `deploy-sync.yml` in the repo).
> The content below stays as a **historical reference/config-as-code** (services may be down at any time).

**Role:** Media server — *arr stack, streaming, home automation
**Default shell:** bash (`/bin/bash`)
**Swarm role:** `standby` — Docker Swarm worker node (stack `sae-edge`, standby services with 0 replicas)

> **Config-as-code (09/08/2026):** all kuaray containers now have a `compose.yml` in
> `/home/kuaray/homelab/{serviço}/` (lidarr, prowlarr, transmission, slskd, soularr, flaresolverr,
> vert, mosquitto, syncthing, glances, dockerproxy, autoheal) — mirrored to the NAS via `config-backup`.
> Secrets (e.g. `TRANS_PASS`) live in `.env` (outside the mirror) / sops store.
> **Updated 28/08/2026:** `apt dist-upgrade` + **Docker repo corrected trixie→noble** + reboot. Kernel **7.0.0-28 → 7.0.0-30**. Docker stack aligned to the noble repo (Docker 29.7.2, containerd.io 2.3.3). watchtower stays paused.
> **Migrated to kavure (09/08):** Home Assistant, Pi-hole, Navidrome, Calibre Web. **Kavita removed 10/08**.
> **Mosquitto removed (16/08)** — no MQTT devices in use; leftovers from the old HA (`/home/kuaray/docker/homeassistant`) cleaned up (NAS mirror preserved).
> **Fix NFS (10/09/2026):** Fixed the duplicated `nofail,nofail` in fstab. Entries already use `soft` (homelab standard). See [`network/nfs.md`](../network/nfs.md).

**Role:** Media server — *arr stack, streaming, home automation
**Swarm role:** `standby` — Docker Swarm worker node (stack `sae-edge`, standby services with 0 replicas)

## Hardware

| Item | Specification |
|---|---|
| **OS** | Linux Mint 22.3 (Zena) |
| **Kernel** | 7.0.0-30-generic |
| **CPU** | Intel Core i5-4200U @ 1.60 GHz (max 2.60 GHz) — 2C/4T |
| **GPU** | Intel HD Graphics (Haswell) + NVIDIA GeForce GT 740M |
| **RAM** | 5.7 GB (3.4 GB in use) |
| **Swap** | 5.4 GB (swap on disk) + 3.4 GB ZRAM |
| **System Disk** | 224 GB SSD (Kingston A400) — `/dev/sda2` — 23% used |
| **Storage Disk** | 932 GB HDD (Seagate 1TB) — `/dev/sdb1` (MBR, starting at LBA 2048) — **reformatted 06/08/2026** (bad sectors LBA 8/32/34-39 avoided by the partition). **Degraded 28/08:** pending sectors 3→37, read error at ~464 GB, fs with errors (repaired with `e2fsck -fy`); mounted with `nofail,errors=continue` |
| **Tailscale IP** | 100.94.209.99 |
| **Tailscale DNS** | kuaray.chimaera-heptatonic.ts.net |
| **Network** | Wi-Fi Qualcomm Atheros QCA9565 (`wlp6s0`: 192.168.3.53) + Ethernet Realtek RTL810xE |
| **User** | kuaray |
| **Access** | `tailscale ssh kuaray@kuaray` (user `kuaray`, sudo NOPASSWD — `/etc/sudoers.d/kuaray-nopasswd`, 10/09/2026) |

## Roles

- Media server (music, books, torrents, streaming) — **library read via NFS from psicopompo since 07/08** (`/mnt/storage/data/media/music` = NFS mount; see [`network/nfs.md`](../network/nfs.md))
- Cold backup mirror: `/mnt/storage/backup` (Syncthing `backup` folder, receiveonly) — see [`services/syncthing.md`](../services/syncthing.md)
- Home automation (~~Home Assistant~~ migrated to kavure 09/08; ~~MQTT~~ removed 16/08)
- Secondary DNS (Pi-hole)
- Gamification (Kavita manga/ebook) — **removed 10/08** (no longer used)
- Monitoring (Glances)

## Tailscale Funnels

| URL | Proxies to | Service |
|---|---|---|
| ~~`kuaray.chimaera-heptatonic.ts.net:10000`~~ | — | Home Assistant (**funnel moved to kavure 09/08**) |

## Docker Containers

> **State (06/08/2026, night):** **19 containers active** — the music stack (Lidarr, Navidrome, Transmission, slskd, Soularr) was **reactivated** after the HDD was reformatted. **Duplicati removed** (06/08 — it did not cover the valuable data). Only **Kavita** and **Calibre-web** remain stopped (book library lost; see [HDD Crisis 06/08](#crise-hdd-06082026)).

### Active

| Container | Image | Ports | Function |
|---|---|---|---|
| pihole | pihole/pihole:latest | `0.0.0.0:53`, `0.0.0.0:8080` | DNS ad-blocking (Docker) |
| prowlarr | lscr.io/linuxserver/prowlarr:latest | `0.0.0.0:9696` | Torrent/usenet indexer |
| flaresolverr | ghcr.io/flaresolverr/flaresolverr:latest | `0.0.0.0:8191` | Cloudflare proxy |
| vert | ghcr.io/vert-sh/vert | `0.0.0.0:3030` | Proxy/content |
| syncthing | linuxserver/syncthing:1.29.7 | `0.0.0.0:8384` | Syncing |
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoring |
| dockerproxy | tecnativa/docker-socket-proxy:latest | `0.0.0.0:2375` | Docker socket proxy |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| lidarr | — | `0.0.0.0:8686` | Music management |
| navidrome | — | `0.0.0.0:4533` | Music streaming |
| transmission | — | `0.0.0.0:9091`, `51413` | Torrent client |
| slskd | — | `0.0.0.0:5030` | Soulseek client |
| soularr | — | `0.0.0.0:8265` | Soulseek download |

### Exited (stopped — books not restored yet)

| Container | Ports | Function |
|---|---|---|
| calibre-web (cwa) | `0.0.0.0:8083` | Ebook server |

## Native Programs

| Program | Function |
|---|---|
| go2rtc | WebRTC/RTSP proxy (cameras) |
| Samba (nmbd/smbd) | File sharing (SMB) |
| tailscaled | Tailscale agent |
| nginx | Secondary Edge (backup service, React static frontend, reverse proxy) |

## Important Ports

| Port | Service | Bind |
|---|---|---|
| 53 | Pi-hole (DNS) | `0.0.0.0` |
| 139, 445 | Samba | `0.0.0.0` |
| 3030 | Vert | `0.0.0.0` |
| 8080 | Pi-hole (admin) | `0.0.0.0` |
| 8085 | Nginx (Secondary Edge) | `0.0.0.0` |
| 8191 | Flaresolverr | `0.0.0.0` |
| 8384 | Syncthing | `0.0.0.0` |
| 9696 | Prowlarr | `0.0.0.0` |
| 61208 | Glances | `0.0.0.0` |
| 2375 | Docker proxy | `0.0.0.0` |
| 22000 | Syncthing transfer | `0.0.0.0` |
| 3389 | RDP (probably xrdp) | `0.0.0.0` |
| 18555 | Unknown | `0.0.0.0` |
| 631 | CUPS (printing) | `127.0.0.1` |

> **Ports of Exited services** (not listening, waiting for migration): 4533 (navidrome), 5030 (slskd), 8265 (soularr), 8083 (calibre-web), 8686 (lidarr), 9091/51413 (transmission).

## Notes

### Storage Disk (`/dev/sdb`) — bad sectors at the start

> **Situation since 31/jul/2026:** the disk has **physical read errors** (medium error, auto reallocate failed) on sectors **LBA 8, 32 and 34-39** — exactly where the primary GPT header and the primary ext4 superblock live. SMART still reports **PASSED** (0 reallocated sectors, 3 pending). The **GPT backup** (end of disk) and the **alternate superblock** (block 32768) are intact.

**Consequences:**
- `/dev/sdb1` does not show up (the kernel cannot read the damaged primary GPT).
- The primary ext4 superblock (offset 1024, LBA 36-37) is unreadable — a normal `mount` fails.
- Containers with a bind mount on `/mnt/storage` die with exit 127.

**Implemented solution (`mnt-storage.service`):**
- `/etc/systemd/system/mnt-storage.service` mounts the HDD with the **alternate superblock** via a loop device with an offset:
  ```bash
  losetup /dev/loop100 /dev/sdb -o 17408   # 17408 = LBA 34 * 512 (início da partição)
  mount -t ext4 -o rw,sb=131072 /dev/loop100 /mnt/storage  # sb em unidades de 1024B
  ```
- Enabled on boot (`systemctl enable mnt-storage.service`), runs before docker.
- The matching `/etc/fstab` entry was commented out (backup in `/etc/fstab.bak-20260731`).

### HDD Crisis 06/08/2026 (double-mount → ext4 corruption)

**Symptom:** syncthing reported `stat /mnt/storage/data/media/music: Bad message` on kuaray.

**Root cause:** the HDD was **mounted twice rw simultaneously** — a stale `loop0` (from an old service activation, never unmounted) **stacked** under the `loop100` of `mnt-storage.service`. Two rw mounts of the same ext4 → **widespread metadata corruption** (`iget: checksum invalid`, block bitmap checksum mismatch, thousands of corrupted inodes). It was not a new bad sector — the disk had already been living with LBA 8/32/34-39.

**Repair:**
- Stopped syncthing + duplicati (which held the `/mnt/storage` bind mount and kept the loop busy).
- Unmounted loop0 + loop100, ran `e2fsck -y -b 32768` (alternate superblock).
- e2fsck cleaned the corrupted inodes and moved orphan directories to `lost+found` (~24G recovered). The `/mnt/storage/data` tree was **disconnected/lost** as a structure.
- Recovered in `lost+found`: **partial music** (subset from psicopompo), **Kavita** data, and **4 EPUB books** (Bruzundanga, Torto arado, Um teto todo seu, Dao De Jing).

**Consequences and decisions (06/08):**
- **Music:** complete and SAFE on psicopompo (`/mnt/BACKUP/media/music/`, 185G). The `music` folder was **removed** from kuaray's syncthing (no longer mirrored).
- **Books:** **recovered → `/mnt/BACKUP/media/books/`** on psicopompo (only copy). **There was no backup** — Duplicati only covered `/DATA/AppData` (lesson: valuable data lives on psicopompo, not on a local HDD without a backup).
- **Duplicati removed** (06/08): the `CASAOS FILES [KUARAY]` job did not cover `/mnt/storage` or Docker volumes. Config backup will be solved later in a structured way.
- **`mnt-storage.service`:** updated with `norecovery` in the mount (the journal has bad sectors — without `norecovery` boot would fail) + drop-in `prevent-double-mount.conf` (`ConditionPathIsMountPoint=!/mnt/storage` + cleanup of stale loops over `/dev/sdb`).
- **Full recovery saved in** `/mnt/BACKUP/kuaray-hdd-recovery-20260806/` (psicopompo).

**Resolution (night of 06/08/2026):**
- **HDD reformatted** cleanly: **MBR** table (LBA 0 away from the bad sectors) + `/dev/sdb1` partition starting at **LBA 2048** (avoids LBA 8/32/34-39 for good) + clean `mkfs.ext4` (valid primary superblock).
- **`mnt-storage.service` REMOVED** (loop/offset/backup-superblock/norecovery/drop-in — all obsolete). `/dev/sdb1` mounts **normally** via `/etc/fstab` (UUID `c3a9e8fe-5842-4398-bfc0-e499f0102685`).
- **Music restored on kuaray:** `music` folder (`gtuwj-mspep`) recreated in kuaray's syncthing → `/mnt/storage/data/media/music` (same structure the stack expects). Re-sync of **177.5 GiB** from psicopompo in progress (background). "add music folder" prompt resolved.
- **⚠️ Deletion storm (night 06/08):** recreating kuaray's `music` folder **empty** made kuaray's index report the library as deleted → psicopompo (mirror) applied the deletions, **losing ~18 real files (~465MB)** before the "directory not empty" errors stopped it (restored from `/mnt/HDD_SATA/Music`, intact). **Fix:** kuaray's `music` folder → **`receiveonly`** (receives everything, never sends state → a faulty drive does not trigger a storm). Valid until kuaray's Lidarr/arr-stack is migrated.
- **Arr stack reactivated:** Lidarr, Navidrome, Transmission, slskd, Soularr are running again (navidrome reads `/music` = `/mnt/storage/data/media/music`).
- **Kavita + Calibre-web** remain stopped — the book library will be restored later from backup (user's decision).

**Recommendations:**
- **Replace the HDD in the medium term** — 2014 disk (ST1000LM024) with 3 pending sectors; although the new partition avoids the current bad sectors, the disk keeps aging. Monitor SMART.
- Media (music + books) lives in `/mnt/BACKUP/media/` on psicopompo (source of truth).

### HDD Degradation (28/08/2026) — boot fsck failed

- **Symptom:** after reboot (kernel 7.0.0-30), `systemd-fsck@...sdb1` failed → `mnt-storage.mount` `dead` → the HDD did not mount. Syncthing `backup` went into a "folder path missing" error and the music NFS (nested under `/mnt/storage`) went down with it (Lidarr with no library).
- **Disk state:** SMART overall **PASSED**, but `Current_Pending_Sector` **3 → 37**, `Multi_Zone_Error_Rate` 15742, ATA Error Count 1299 (log: UNC at LBA 32 — known region), **new read error at ~464 GB** (sector 973545360, dmesg) and `e2fsck -fn` with errors (inode 7, "Illegal block", bitmaps).
- **Repair (28/08):** `e2fsck -fy /dev/sdb1` (fixed dirs/bitmaps/orphan inodes — it did not hit the bad sector again); `/etc/fstab` for `/mnt/storage` with **`nofail,errors=continue`** (backup `/etc/fstab.bak-20260828`); `mount` OK. Details and consequences in Syncthing: [`services/syncthing.md`](../services/syncthing.md).
- **Music NFS decoupled from the HDD (28/08):** mount moved to `/mnt/nas/media/music` (outside `/mnt/storage`); Lidarr's bind adjusted in compose (`/mnt/nas/media/music:/data/media/music`). The library no longer depends on the HDD. See [`network/nfs.md`](../network/nfs.md).
- **Monitor SMART** — growing pending sectors + a new bad area indicate the failure is progressing; this reinforces the replacement recommendation.

### Other notes

- **Docker repo corrected trixie→noble (28/08/2026):** `/etc/apt/sources.list.d/docker.list` pointed at `https://download.docker.com/linux/debian trixie` — updating containerd.io required `libseccomp2 >= 2.6.0` (not available on Mint). Corrected to `https://download.docker.com/linux/ubuntu noble` (base of Mint 22.x) + `apt update` + a full update of the Docker stack to noble builds: **Docker 29.7.2**, **containerd.io 2.3.3** (`-1~ubuntu.24.04~noble`), docker-ce-cli/buildx/compose-plugin/model-plugin aligned. Old config backed up in `/var/tmp/docker.list.bak`.

- **Home Assistant**: migrated to **kavure** (09/08) — funnel `kavure...:10000`; **reconfigured on kavure 16/08** (Bluetooth caps + HACS installed).
- **CasaOS**: **removed (08/08/2026)** — containers now via `docker compose` (`/home/kuaray/homelab/*/compose.yml`).
- Media server — arr-stack + infra (config-as-code).
- **Pi-hole**: migrated to **kavure** (09/08) — global tailnet resolver.
- **Navidrome / Calibre / Kavita**: migrated to **kavure** (09/08, libraries via NFS).
- **Samba** (nmbd/smbd) runs natively for file sharing on the LAN.
- **go2rtc** native (inactive since the migration) — HA on kavure uses the **built-in go2rtc** (port `18554`); cameras not configured.
- **Duplicati removed (06/08/2026)** — the job only covered `/DATA/AppData`; valuable data (books) was not protected. Decision: media consolidated on psicopompo; structured config backup (09/08).
- Kernel updated to 6.17.0-23-generic.
- Active swap: 5.4 GB on disk + 3.4 GB ZRAM (zram0).
