---
tags: [homelab, service, syncthing, storage]
---

# Syncthing

Continuous decentralized peer-to-peer file synchronization — preserves real-time parity across the Obsidian workspace vault and sensitive personal datasets.

**Server:** mesh (psicopompo ↔ kuaray ↔ ybytu ↔ mobile endpoints)

## Active Instances

| Node | Deployment Type | User | Monitored Paths | Status |
|---|---|---|---|---|
| psicopompo | Bare-metal Systemd user unit (`syncthing.service`, config in `~/.local/state/syncthing/config.xml`) | `edu` | Canonical folder targets below | ✅ Active |
| kuaray | Docker Container (`linuxserver/syncthing:1.29.7`, host networking) | `abc` (PUID/PGID 1000) | Storage targets below | ✅ Active |
| ybytu | Systemd service `syncthing@ubuntu.service` (package from the official `apt.syncthing.net` repo, **v2.1.6**) | `ubuntu` | `default` folder — **`AlgoAqui.kdbx` only** (see *Ybytu KeePass recovery mirror* below) | ✅ Active (2026-10-13) |

> **Ybytu history.** The instance was **decommissioned on 2026-08-06** to cut cloud memory
> overhead, and **recommissioned on 2026-10-13** for one purpose only: an off-site (datacenter)
> copy of the KeePass database, so losing `psicopompo` does not lose the secret store. This time it
> is **selective by design** — see the next section.

> ⚠️ **Monitoring gotcha — `syncthing@*` is not a valid query.** `syncthing.service` is a systemd
> **template**, so `systemctl is-enabled 'syncthing@*'` is rejected (*"globs are not supported for
> this… Invalid unit name"*) and prints `disabled` — a **false negative**. Always query the concrete
> instance (`systemctl is-enabled syncthing@ubuntu`) or read `UnitFileState`. Verified on `ybytu`
> 2026-10-13: the instance is **enabled** (symlink in `multi-user.target.wants/`) and `active running`,
> while the wildcard still lies. Cost of the instance on `ybytu`: ~8 MB RSS.

## Synchronized Folder Repositories

| Folder ID | Folder Label | psicopompo Target | kuaray Target | ybytu Target | Dataset Scope |
|---|---|---|---|---|---|
| `default` | `default-folder-syncthing` | `/home/edu/Default Folder Syncthing/` (**sendreceive**, primary source) | `/home/kuaray/Default/` (**receiveonly**) | `/home/ubuntu/keepass/` (**receiveonly** — **`AlgoAqui.kdbx` ONLY**, `.stignore` filtered) | KeePass databases (`.kdbx`), personal documents |
| `agentic-ai` | `agentic-ai` | `/mnt/NVME_PCI/agentic-ai/` (**sendreceive**) | `/home/kuaray/agentic-ai/` (**receiveonly**) | **not shared** | **Obsidian Vault & Agent Workspace** |
| `backup` | `backup` | `/mnt/BACKUP/` (**sendreceive**, source) | `/mnt/storage/backup/` (**receiveonly**) | **not shared** | **Cold mirror of NAS** — music, eBooks, recovery tools, database dumps |

> ⚠️ **The `default` folder is mixed content.** Besides the KeePass database it holds
> **unencrypted** identity documents (`CNH C.E.R`, `CNH C.E.R PNG.png`, `TdR_…pdf`). A whole-folder
> share to an internet-facing host would expose them in the clear — so `ybytu` is **not** a peer of
> the whole folder. Its `.stignore` (see below) accepts **only** the kdbx.
>
> ℹ️ **Legacy artifact, not a sync target:** `/home/edu/Google_Drive/KEEPASS/AlgoAqui.kdbx`
> (rclone mount, dated **2026-05-26**) is **not** kept current and is **not** part of the mesh. It is
> an **intentional leftover**: the owner's pre-Linux syncing folder, which became an old backup.
> **Do not "fix", re-sync or delete it.**
>
> **Never share `agentic-ai` or `backup` with `ybytu`** — the DR need is the KeePass only.

## Ybytu KeePass recovery mirror (2026-10-13)

Purpose: survive the loss of `psicopompo` **and** of the premises, by keeping the encrypted KeePass
database in the OCI datacenter. It is **ciphered-at-rest** (KeePass), so the exposed host only stores
unreadable blobs.

- **Folder:** `default` shared to `ybytu` as **Receive Only**, labelled `keepass-recovery`,
  path `/home/ubuntu/keepass/`. It cannot write back.
- **The selector** — `/home/ubuntu/keepass/.stignore`:

  ```
  !/AlgoAqui.kdbx
  *
  ```

  The first matching pattern wins (`!` = include), so **only the kdbx** is pulled now **and for any
  file added to the folder later** — the identity documents never reach `ybytu`.
- **Listener:** bound to the **tailnet IP** `100.115.253.109:22000` (not `0.0.0.0`), firewall
  tailnet-only, consistent with the HB-047 posture.
- **Verified 2026-10-13:** `sha256` of the kdbx on `ybytu` == `psicopompo`
  (`8d917d1011aec487baaf854149dee4d6215304cbd148148147c909108b7d5a45`); the folder holds **only**
  `AlgoAqui.kdbx` (+ `.stfolder`/`.stignore`) — `CNH*` and the PDF are **absent**; the service is
  enabled at boot and the folder is **Receive Only**.
- **What the age key needs:** the `Mnemocine · SOPS age key (cold)` KeePass entry holds the
  private key that decrypts `mnemocine/secrets.enc.env`. With the kdbx above **and** that key,
  recovery works from `ybytu` without `psicopompo`. A second age recipient (`kavure`) also exists —
  either key decrypts the store.
- **Rollback:** remove the `ybytu` device/folder, then `apt purge syncthing`.

### Critical Vault Folder Rules (`agentic-ai`)

- The root `.stignore` file explicitly excludes virtual environments (`.venv/`), temporary build caches, and local lockfiles.
- **Bi-directional Propagation with Local Versioning:** `ignoreDelete=false` (deletions propagate across devices) paired with **`simple` versioning** (keeps 5 revisions on psicopompo, 3 revisions on kuaray). Files deleted accidentally are archived locally in `.stversions/` instead of vanishing permanently, mitigating "deletion storm" risks from failing disks.
- Configuration artifacts (`.obsidian/`, `.pandoc/`) synchronize transparently; machine-specific caches (`.smart-env/`, `.SMART CHATS/`) are ignored.

## Network Ports

| Port | Protocol | Purpose |
|---|---|---|
| `8384` | TCP | Web administration UI (bound to `127.0.0.1`; exposed **tailnet-only** via `tailscale serve --tcp 8384` on both hosts) |
| `22000` | TCP/UDP | Encrypted mTLS data synchronization protocol |
| `21027` | UDP | Local LAN peer discovery |

## Web Management Access

Web GUI (Tailnet exclusive):
- **psicopompo:** `http://100.82.51.112:8384` (Proxied via `tailscale serve` to local loopback)
- **kuaray:** `http://100.94.209.99:8384` (Proxied via `tailscale serve` to local loopback, 2026-10-10)
- **ybytu:** GUI bound to `127.0.0.1:8384` (loopback only, house pattern). The mirror needs **no**
  GUI access; expose it with `tailscale serve --tcp 8384` if remote management is ever wanted.

## Operational History & Architecture Mitigations

- **Boot Race Prevention (2026-08-10):** Hardcoding GUI listeners to Tailscale IPs caused systemd units to enter `start-limit-hit` when booting faster than network initialization. The service now binds strictly to `127.0.0.1:8384`, exposing the console securely to the tailnet via persistent `tailscale serve` tunnels.
- **Exclusion of Snapshot Trees:** Snapper Btrfs snapshot subvolumes (`/mnt/BACKUP/.snapshots`) and local Restic repositories are explicitly listed in `.stignore` with `(?d).snapshots` patterns to prevent permission denied errors on root-owned datasets.
- **De-duplication of Services (2026-09-22):** Purged duplicate system-level `syncthing@edu.service` templates on Arch Linux, standardizing exclusively on the user-level `systemd --user syncthing.service`.
- **kuaray GUI hardening (2026-10-10):** the `linuxserver/syncthing` image hardcodes `--gui-address="0.0.0.0:8384"`, exposing the GUI on the LAN. Standardized to the house pattern: an **s6 run-script override** (`./svc-syncthing-run`, bind-mounted read-only over `/etc/s6-overlay/s6-rc.d/svc-syncthing/run`) binds the GUI to `127.0.0.1:8384`; tailnet access goes through `tailscale serve --tcp 8384`. `<insecureSkipHostcheck>true</insecureSkipHostcheck>` was added to `<gui>` (the proxy's Host header would otherwise return **403 "Host check error"**). Compose healthcheck uses `127.0.0.1`.
- **`backup` folder permission errors fixed (2026-10-10):** `ybyra-pre-rebuild/tailscale/{files,profile-data}` were mode `0600` (no `x`, so even the owner cannot traverse) → Syncthing reported **2 failed items** (`pullErrors=2`). Resolved with `chmod -R u+rwX` + rescan.
- **Conflict cleanup (2026-10-10):** 7 stale `*.sync-conflict-*` copies under `.obsidian/` removed (Obsidian config churn across devices).
- **ybytu commissioned as a KeePass recovery mirror (2026-10-13):** the Syncthing package came from the **official** `apt.syncthing.net` repo (pinned `Pin-Priority: 990`), running as `syncthing@ubuntu.service`. The `default` folder was shared to it as **Receive Only**, but the default behaviour would have pulled **unencrypted identity documents** onto an internet-facing host — so `/home/ubuntu/keepass/.stignore` was placed **before** accepting the share, using the first-match-wins rule (`!/AlgoAqui.kdbx` + `*`) to pull **only the kdbx**. Listener bound to the tailnet IP, not `0.0.0.0`. Evidence (checksums / absence of documents) in *Ybytu KeePass recovery mirror* above. This closes the KeePass cold-copy gap recorded in [`../recovery/psicopompo-loss.md`](../recovery/psicopompo-loss.md).
- **Off-host copy of the age key (2026-10-13):** the `Mnemocine · SOPS age key (cold)` KeePass entry now carries `~/.config/sops/age/keys.txt` as an attachment; with the kdbx mirrored to `ybytu`, the key survives independently of `psicopompo` — **no separate passphrase was created**, because KeePass itself is the lock (an extra passphrase stored in the same database would have added no strength). The owner's chosen arrangement is: entry in KeePass, plus a **paper copy of the master password** kept out of the house.

## See Also
- [`../network/tailscale.md`](../network/tailscale.md) — Tailscale mesh architecture
- [`../backups/strategy.md`](../backups/strategy.md) — Multi-tier backup strategy
- [`../../servers/psicopompo.md`](../../servers/psicopompo.md) — Workstation node profile
