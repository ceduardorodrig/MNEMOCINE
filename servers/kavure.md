---
tags: [homelab, server, kavure, docker, storage, gaming, todo]
pending: []
---

# kavure

**Role:** Dedicated application server — Sumænimá Swarm Manager (`sae-core`), Minecraft Dominium, Project Zomboid, Valheim, and core monitoring.  
**Default Shell:** bash (`/bin/bash`)  

## Hardware Specifications

| Component | Specification |
|---|---|
| **Chassis** | Dell OptiPlex 3060 SFF |
| **CPU** | Intel Core i3-8100 4C/4T @ 3.60 GHz |
| **RAM** | 12 GB DDR4 (11 GiB addressable, 2 DIMM slots) |
| **System Storage** | 223 GB SATA 2.5" SSD (Kingston SA400S3) — LVM configuration (217 GB on `/`) |
| **Planned Expansion** | M.2 SATA 1 TB (OS/Docker) + 3.5" HDD 4–8 TB (Bulk Storage) |
| **Network** | Gigabit Ethernet (`enp1s0`, wired to gigabit switch) |
| **LAN IP** | `192.168.3.41/24` via switch |
| **MTU (PPPoE)** | **1492** (netplan `enp1s0`) aligned with WAN uplink |
| **OS** | Ubuntu 24.04 LTS (kernel `6.8.0-149-generic`) |
| **Filesystem** | LVM + ext4 |
| **Tailscale IP** | `100.124.146.77` — `kavure` |
| **Access** | `tailscale ssh kavure@kavure` · **OpenSSH key-only** (no password since 13/10 — [detail](../network/tailscale.md)) |

## Operational Capabilities & Architecture

- **Docker Swarm Manager (`role=core`):** Orchestrates the `sae-core` stack (PostgreSQL, Valkey, API `:9090`, Umami DB, backup daemon, and Asciline).
- **Sumænimá Edge Standby:** Configured as backup failover node (`edge_backup=true`) hosting dormant standby replicas of `proxy`, `tunnel`, and `umami`.
- **Game Server Host:** Dedicated containerized game environments:
  - **Project Zomboid:** `danixu86/project-zomboid-dedicated-server` (active since 2026-08-06);
  - **Minecraft Dominium:** Crafty Controller running Fabric Loader on Minecraft 1.21.1;
  - **Valheim:** Dedicated container server (`mbround18/valheim:3`).
- **Homelab Automation (n8n, reactivated 2026-10-09):** Standalone n8n + `n8n-postgres` (`:5678`) for homelab workflows — **distinct** from the Miracena n8n on kuaray (not part of that stack). Its daily `pg_dump` writes to the NAS (see backups).
- **Subnet Router (Activated 2026-10-05):** Advertises route `192.168.3.0/24` across the Tailnet, granting remote access to local IoT devices and home routers.
- **DNS Core Resolver (2026-10-08):** Runs Pi-hole alongside a native **recursive `unbound`** instance (`127.0.0.1:5053`, DNSSEC validation). Monitored by a dedicated Rust watchdog (`hl-dns-watchdog.timer`).
- **Social-media autopilot host (2026-10-19):** production scheduler for `SOCIAL-MEDIA-AUTOPILOT` — four `Type=oneshot` timers (publish/engage/metrics/learn). CPU-only: the LLM is cloud-first and the GPU fallback stays on psicopompo behind `hl-infer`. The **tenant** (packs, config, state) lives in `/home/kavure/autopilot/tenants/sumaenima/`; the repo is code only (HB-079). See [`../services/autopilot.md`](../services/autopilot.md).
- **Homepage Dashboard (migrated 2026-11-18, `HB-095`):** standalone container at `/srv/data/homepage/` serving `100.124.146.77:3003->3000/tcp` (UFW tailnet-only, `mem_limit: 256m`), reading local `/var/run/docker.sock` and remote `dockerproxy` on `ybytu`/`psicopompo`/`ybyra`/`kuaray`.

## Storage Layout & Directory Structure

```
/srv/data/zomboid/              ← Project Zomboid container volume
/srv/data/pihole/               ← Pi-hole ad-blocking configuration and gravity.db
/srv/data/dnscrypt-proxy/       ← Cold storage archive (superseded by native unbound)
/srv/data/ops/                  ← Infrastructure operations stack (autoheal, watchtower, glances)
/srv/data/sumaenimahub/         ← Sumænimá Swarm runtime data and volumes
/srv/data/sumaenimahub/backup   ← NFS mount -> psicopompo:/mnt/BACKUP/sumaenima-server-kavure
/srv/data/minecraft/            ← Crafty Controller and Minecraft Dominium server assets
/srv/data/valheim/              ← Valheim dedicated server data
/srv/data/valheim/offbox        ← NFS mount -> psicopompo:/mnt/BACKUP/valheim-server-kavure
/srv/data/n8n/                  ← Homelab n8n container data + n8n-postgres volume (reactivated 09/10)
/srv/data/n8n/offbox            ← NFS mount -> psicopompo:/mnt/BACKUP/n8n-server-kavure
/var/lib/docker/                ← Docker storage root (overlay2)
```

## Systemd Automated Backups

| Timer | Schedule | Protected Service | Target Destination |
|---|---|---|---|
| `hl-config-backup.timer` | 05:00 | Host configurations **+ the autopilot engine and tenant** (`/home/kavure/homelab/sumaenima-socialmedia-autopilot` with `target/` excluded, **and** `/home/kavure/autopilot/tenants/sumaenima`; 185 tenant files) | rsync $\rightarrow$ NAS mirror |
| `hl-zomboid-backup.timer` | 05:15 | Project Zomboid world saves | rsync $\rightarrow$ NAS mirror |
| `hl-n8n-backup.timer` | 05:25 | Homelab n8n PostgreSQL | pg\_dump $\rightarrow$ NAS mirror (health stamp since 09/10) |
| `hl-valheim-backup.timer` | 05:30 | Valheim world saves | rsync $\rightarrow$ NAS mirror |
| `hl-sumaenima-backup.timer` | 03:00 | Sumænimá database & uploads | Borg + pg_dump $\rightarrow$ NAS mirror |
| `stenio-hub-backup.timer` | 04:30 | Stenio shared work ledger | restore-proven snapshot in `/srv/data/stenio-hub/backup/` (14 kept); `latest.snapshot` is carried to the NAS by the 05:00 mirror |

## Stenio shared work ledger (2026-11-27)

`stenio-hub.service` serves the work ledger used by agents on every host (claims, hand-backs, owner questions, quota). Engine 4.51.0 (verified 2026-11-27); units from the engine repository (`deploy/hub/`).

- **Updates:** `stenio release-engine` rolls each release out to the targets of the engine repository file `deploy/rollout.toml` (this server first, with a ledger backup, a rollback copy `<path>.prev-<old>`, restart and health check; a failure restores the previous binary and stops), then to the client binaries on `kavure`, `kuaray` and `ybytu`, and checks version and sha256 parity.
- **Rollback of 4.51.0:** on each target copy `<path>.prev-4.50.0` over `<path>` (with `sudo` for the service binary, then `systemctl restart stenio-hub`).
- **Guard:** since 4.51.0 the harness hooks refuse a file edit inside another worker's live `tree:` claim; three expired or failed attempts of a row need `ssh -t kavure stenio-hub-owner reset-attempts --row <ID> --reason <why>`.

- **Access:** listens on `127.0.0.1:8797`; published to the tailnet only by `tailscale serve` on `https://kavure.chimaera-heptatonic.ts.net:8443` (never Funnel). The existing tailnet policy covers it. Every request needs a per-client token.
- **Files:** binary `/usr/local/lib/stenio-hub/stenio`; data `/srv/data/stenio-hub/` (`state/hub.db`, `clients.toml` with token hashes, `backup/`); `/etc/stenio-hub.env`; system user `stenio-hub`.
- **Clients:** `~/.config/stenio/hub-remote.toml` plus `~/.config/stenio/hub.token` (0600) on `psicopompo`, `kavure`, `kuaray`, `ybytu`; tokens are kept in the sops store (`STENIO_HUB_TOKEN_<HOST>`). Server unreachable: clients claim nothing and write no backlog.
- **New client:** `stenio hub token --client <host> --out <new file>`, append the printed entry to `clients.toml` (read on every request), move the token over stdin only.
- **Owner commands:** `ssh -t kavure stenio-hub-owner questions` (also `answer`, `quota override`).
- **Check:** `stenio hub audit` from any client; `systemctl status stenio-hub`.
- **Restore:** stop the service, copy a snapshot over `state/hub.db` (remove `hub.db-wal`/`-shm`, owner `stenio-hub`, mode 0600), run `sudo stenio-hub-owner audit`, start.
- **Back to the single-host ledger (psicopompo):** delete `hub-remote.toml`, remove the empty directory `~/.local/state/stenio/hub.db/`, copy the newest server snapshot to that path (the pre-move file is `hub.db.pre-remote`), re-enable the user `stenio-hub-backup.timer`.

## Network & Wake-on-LAN

Wired into the `IT-BLUE LE-4203` gigabit switch (`1000 Mb/s full-duplex`). Wake-on-LAN is persisted via Netplan and systemd (`wol@enp1s0`). The host responds to magic packets from psicopompo or kururu within 29–39 seconds from S5 power-off.

### NIC power-saving disabled (2026-10-10)

The Realtek RTL8168H (`enp1s0`, driver `r8169`) was investigated after intermittent ~30 s connectivity losses (see [`network/topology.md`](../network/topology.md#lan-stability--nic--switch-investigation-2026-10-10)). Power-saving is now fully off:
- **ASPM:** already disabled by firmware (`ACPI FADT declares the system doesn't support PCIe ASPM`; the sysfs `pcie_aspm/parameters/policy` is read-only → `Operation not permitted`). No OS action possible or needed.
- **EEE:** already `disabled`; re-asserted at every boot by `hl-nic-power-tuning.service` (systemd oneshot, `ethtool --set-eee enp1s0 eee off`).

Link verified at **1000 Mb/s full-duplex** after the change; no downtime (EEE was already off on this host).

### NIC RPS & Backup Automount Fixes (2026-11-17)

- **Receive Packet Steering (`enp1s0`):** `r8169` on RTL8168H fixes the RX ring at 256 descriptors (`ethtool -g`) and previously routed all `enp1s0` IRQs/`NET_RX` softirqs to CPU3 (`rps_cpus=0`), dropping packets (`rx_missed`) under high-pps Tailscale/NFS bursts. Enabled RPS across all 4 cores (`rps_cpus=f`) and persisted via `/etc/udev/rules.d/99-enp1s0-rps.rules`.
- **Backup `x-systemd.automount` trigger:** `valheim-backup`, `monitoring-backup`, and `sumaenima-backup` in `mnemocine-ops` now trigger `mount "$MNT"` before checking `findmnt -n -o FSTYPE "$MNT"` (avoiding false `autofs` aborts after reboot). `hl-valheim-backup.service` `TimeoutStartSec` raised from `300` to `1200` (above `timeout 900 rsync`). Both `hl-monitoring-backup` and `hl-valheim-backup` verified `status=0/SUCCESS` on 2026-11-17.

## Container Healthchecks

All standalone containers on this node implement explicit healthcheck definitions, integrated with `autoheal` for autonomous remediation.

## Disaster-Recovery Role — SOPS/age keyholder (2026-10-13)

kavure is the **second age recipient** of the centralized SOPS store, so the homelab's secrets stay
decryptable if `psicopompo` is lost — DR "Rota A" (detail in
[`../recovery/psicopompo-loss.md`](../recovery/psicopompo-loss.md) §2 G1 · HB-064).

- **Key:** `~/.config/sops/age/keys.txt` — `0600`, owner `kavure` (the recovery user); **never synced
  and never mirrored to the NAS** (`config-backup` sources only `/srv/data`).
- **Public recipient:** `age1u2c35fk…` — the **private key never leaves this host**.
- **Tooling (installed 2026-10-13):** `age` (apt, Ubuntu repo) + `sops` (`sops_3.13.3_amd64.deb`,
  official GitHub release — `sops` is not packaged in Ubuntu).
- **Decrypt from here:** `sops --decrypt --input-type dotenv --output-type dotenv <store>` (fetch the
  ciphertext store from Syncthing/GitHub or the vault mirror first).
- **Verified 2026-10-13:** decrypts the store with its **own** key alone — whole-store sha256 and the
  `TS_AUTH_KEY` value-hash both match psicopompo (no regression on psicopompo).

## See Also

- [`network/kavure-migration-plan.md`](../network/kavure-migration-plan.md) — Service migration blueprint
- [`services/crafty.md`](../services/crafty.md) — Minecraft server controller
- [`services/unbound.md`](../services/unbound.md) — Recursive local DNS resolver

> **2026-11-02 note:** on 2026-11-01 around 02:46 UTC `calibre`, `navidrome` and `crafty-controller` stopped with exit 128 (`error mounting /srv/data/media/books ... no such device`): they were started while the NFS exports from psicopompo (`/mnt/BACKUP/media/books` and `music`, automount in fstab) were not available. The mounts were healthy again on 2026-11-02 and the three containers were started with `docker start` (no recreate). To prevent a repeat, give the containers a start dependency on the mounts (for example `restart: unless-stopped` plus a check in the compose `depends_on` wrapper or a systemd drop-in that waits for the automount), tracked in HB-100.

> **2026-11-26 (HB-100):** the alert `ContainerExitedNfs` is live in Prometheus (these three containers `exited` for 10m, severity warning; rollback copy `/srv/data/monitoring/prometheus/alerts.yml.bak-20261126-205203-hb100`, tested with `promtool test rules`). The recovery actor `nfs-container-recover` + `hl-nfs-container-recover.timer` comes from [MNEMOCINE-OPS PR #26](https://github.com/ceduardorodrig/MNEMOCINE-OPS/pull/26), merged and **installed 2026-11-27**. A docker.service dependency on the mounts was rejected: it would hold every container down while one export is unreachable. A Docker restart policy does not retry a container that never started ([Docker docs](https://docs.docker.com/engine/containers/start-containers-automatically/)). Verified after the install: service `Result=success`, timer every 2 min, the three containers healthy and no container qualifying for a start (a live NFS failure was not provoked). `--units` also copied 40 unit files left disabled and kept 12 `DIFFERS` units untouched. Rollback: `sudo systemctl disable --now hl-nfs-container-recover.timer`.
