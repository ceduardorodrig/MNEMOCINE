---
tags: [homelab, service, syncthing, storage]
---

# Syncthing

Continuous decentralized peer-to-peer file synchronization — preserves real-time parity across the Obsidian workspace vault and sensitive personal datasets.

**Server:** mesh (psicopompo ↔ kuaray ↔ mobile endpoints)

## Active Instances

| Node | Deployment Type | User | Monitored Paths | Status |
|---|---|---|---|---|
| psicopompo | Bare-metal Systemd user unit (`syncthing.service`, config in `~/.local/state/syncthing/config.xml`) | `edu` | Canonical folder targets below | ✅ Active |
| kuaray | Docker Container (`syncthing/syncthing`) | `kuaray` (UID 1000) | Storage targets below | ✅ Active |

> Ybytu instance decommissioned 2026-08-06 to minimize cloud memory overhead.

## Synchronized Folder Repositories

| Folder ID | Folder Label | psicopompo Target | kuaray Target | Dataset Scope |
|---|---|---|---|---|
| `default` | `default-folder-syncthing` | `/home/edu/Default Folder Syncthing/` (**sendreceive**, primary source) | `/home/kuaray/Default/` (**receiveonly**) | KeePass databases (`.kdbx`), personal documents |
| `agentic-ai` | `agentic-ai` | `/mnt/NVME_PCI/agentic-ai/` (**sendreceive**) | `/home/kuaray/agentic-ai/` (**receiveonly**) | **Obsidian Vault & Agent Workspace** |
| `backup` | `backup` | `/mnt/BACKUP/` (**sendreceive**, source) | `/mnt/storage/backup/` (**receiveonly**) | **Cold mirror of NAS** — music, eBooks, recovery tools, database dumps |

### Critical Vault Folder Rules (`agentic-ai`)

- The root `.stignore` file explicitly excludes virtual environments (`.venv/`), temporary build caches, and local lockfiles.
- **Bi-directional Propagation with Local Versioning:** `ignoreDelete=false` (deletions propagate across devices) paired with **`simple` versioning** (keeps 5 revisions on psicopompo, 3 revisions on kuaray). Files deleted accidentally are archived locally in `.stversions/` instead of vanishing permanently, mitigating "deletion storm" risks from failing disks.
- Configuration artifacts (`.obsidian/`, `.pandoc/`) synchronize transparently; machine-specific caches (`.smart-env/`, `.SMART CHATS/`) are ignored.

## Network Ports

| Port | Protocol | Purpose |
|---|---|---|
| `8384` | TCP | Web administration UI (bound to `127.0.0.1` and published via `tailscale serve --tcp 8384`) |
| `22000` | TCP/UDP | Encrypted mTLS data synchronization protocol |
| `21027` | UDP | Local LAN peer discovery |

## Web Management Access

Web GUI (Tailnet exclusive):
- **psicopompo:** `http://100.82.51.112:8384` (Proxied via `tailscale serve` to local loopback)
- **kuaray:** `http://100.94.209.99:8384`

## Operational History & Architecture Mitigations

- **Boot Race Prevention (2026-08-10):** Hardcoding GUI listeners to Tailscale IPs caused systemd units to enter `start-limit-hit` when booting faster than network initialization. The service now binds strictly to `127.0.0.1:8384`, exposing the console securely to the tailnet via persistent `tailscale serve` tunnels.
- **Exclusion of Snapshot Trees:** Snapper Btrfs snapshot subvolumes (`/mnt/BACKUP/.snapshots`) and local Restic repositories are explicitly listed in `.stignore` with `(?d).snapshots` patterns to prevent permission denied errors on root-owned datasets.
- **De-duplication of Services (2026-09-22):** Purged duplicate system-level `syncthing@edu.service` templates on Arch Linux, standardizing exclusively on the user-level `systemd --user syncthing.service`.

## See Also
- [`../network/tailscale.md`](../network/tailscale.md) — Tailscale mesh architecture
- [`../backups/strategy.md`](../backups/strategy.md) — Multi-tier backup strategy
- [`../../servers/psicopompo.md`](../../servers/psicopompo.md) — Workstation node profile
