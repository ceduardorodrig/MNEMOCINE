---
tags: [homelab, backup, config, docker, compose]
---

# Canonical Configuration Backup — `config-backup`

> Central mirror of CONFIGURATIONS across all hosts on the NAS (psicopompo `/mnt/BACKUP/configs-homelab`).
> Born from the CasaOS incident (08/08/2026): configurations for ~12 containers were lost without backups because **neither source code nor mirrors existed**.

## Architecture

```
Each Host (05:00) → /usr/local/bin/config-backup (systemd timer hl-config-backup.timer)
  0. ROOT GUARD (10/08): `id -u` != 0 → aborts BEFORE rsync/ntfy
  1. TCP port 2049 probe (NAS reachable check) — fail-fast
  2. rsync -a --delete --delete-excluded --no-o --no-g -x  (mirror only; sources are read-only)
  3. Golden files (Compose files + selected /etc) → <dest>/golden/
  4. ntfy /backup (failure=high, success=low) + health file /srv/health/
      → Mirror stored at /mnt/BACKUP/configs-homelab/{host}/
         ├─ git → Private GitHub repository mnemocine (05:55)
         ├─ restic → /mnt/BACKUP/repos/restic/configs (05:40, retention 14d/8w/6m)
         └─ snapper (config `backup`) — prevents accidental mirror deletions
```

**Standardized Schedule (05:00–06:00 BRT window; Cloud VPS at 08:00 UTC):**

| Time | Job |
|---|---|
| 04:40 / 04:45 | **homelab-docs-sync (psicopompo)** — Publishes documentation repositories from vault: curriculum-vitae (04:40) and `MNEMOCINE` (04:45) (see [`docs-sync.md`](docs-sync.md)) |
| 04:55 | **noctalia-config-export (psicopompo, user)** — `noctalia config export` → `~/.config/noctalia/export/merged-config.toml` (effective layer: declarative + GUI overrides). **Targeted subfolder by design** — Noctalia only auto-loads `*.toml` files from the root config directory |
| 05:00 | config-backup (all nodes) |
| 05:00 | zomboid-restart (kavure) |
| 05:15 | zomboid-backup (kavure) |
| 05:20 | agentic-ai-backup (psicopompo) |
| 05:40 | restic-configs-backup |
| 05:55 | etckeeper-push + configs-git-push |
| Sun 06:00 | restic check |

> **Desktop Idle Policy Note (24/09/2026):** Override file `~/.local/state/noctalia/settings.toml` houses desktop idle management (screen lock 900s; display sleep disabled while unlocked and 60s when locked; suspend disabled). Mirrored alongside `~/.config/noctalia`; `merged-config.toml` is strictly a generated export artifact and must not be edited directly.  
>  
> **⚠️ Config Collision Bug Fix (06/10/2026):** `merged-config.toml` was relocated to `~/.config/noctalia/export/` (subfolder). It previously resided in the config root, where Noctalia evaluated it as a top-level layer (alphabetical order, last write wins) — overriding manual edits in `config.toml` and freezing settings. Subfolders are ignored during startup, keeping the exported snapshot safely versioned without polluting active runtime. Details in [`../guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md).

## Components

| Component | Location |
|---|---|
| Script | `/usr/local/bin/config-backup` (identical across nodes) |
| Host Configuration | `/etc/config-backup.conf` (`SRC_DIRS`, `EXCLUDES`, `GOLDEN_FILES`, `MOUNT`, `HOST`, `POST_CMD`) |
| NFS Exports | `/mnt/BACKUP/configs-homelab` (rw, all_squash, anonuid=1000) + `/mnt/BACKUP/repos/git` |
| Client Mounts | `/srv/backup-configs` (configs), `/srv/backup-gitrepos` (bare git) — fstab `nofail` |
| Schedule | Systemd timer `hl-config-backup.timer` (05:00, `Persistent=true`) — migrated from cron 10/08 |
| **Git Push Auth (GitHub)** | `hl-configs-git-push.service` runs as `User=edu`; uses git credential store (`~/.git-credentials`, permissions 0600, owner `edu`) with PAT scoped to private repository `MNEMOCINE`. Token **NEVER** stored in plaintext — managed in **sops store** as `GH_PUSH_TOKEN` (`guides/secrets-centralizados.md`). Canonized 21/09/2026. |

> **Root Privilege Guard (10/08/2026):** The script **must execute as root** (systemd timer runs as root). Unprivileged manual invocations abort immediately (`exit 1` without rsync or ntfy dispatch) — preventing false failure alerts. To run manually: `sudo /usr/local/bin/config-backup`.

| Health Stamp | `/srv/health/config-backup-{host}-last-ok` |

## Sources by Host (Mirrored Assets)

| Host | SRC_DIRS | Primary Exclusions |
|---|---|---|
| psicopompo | `/home/edu/homelab` (**Service compose files** — first in list), `/mnt/NVME_PCI/homelab` (**Project roots**: sumaenimahub, transcribe, …), `/usr/local/bin`, syncthing state, **Desktop configs** (`~/.config/hypr`, `~/.config/noctalia`, `~/.config/uwsm`, `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia`, `~/.config/gtk-3.0`, `~/.config/gtk-4.0`, `~/.config/qt6ct`, **`~/.config/fish`** — shell config, 06/10/2026), **Dominium Prism Instance** (`~/.local/share/PrismLauncher/instances/Dominium` — modpack source of truth: mods/config/loader, ~484 MB), rclone, wallpapers. **GOLDEN FILES:** `/var/lib/noctalia-greeter/greeter.toml`, `/etc/greetd/config.toml`, `/etc/systemd/sleep.conf.d/60-freeze.conf`, `/etc/systemd/system/tailscaled-wait.service`, `/etc/systemd/system/nfs-server.service.d/10-tailscaled-wait.conf`, `/etc/smartd.conf`, `/etc/sudoers.d/99-edu-homelab`, `/etc/ufw/user{,6}.rules`, `~/.gtkrc-2.0`, **`~/.ssh/config`** (SSH host configuration without private keys), fstab, exports, pacman, snapper configs. | `ollama`, `index-v2`, `*.log`, **`target`** (Rust build artifacts), **Noctalia runtime state** (`clipboard`, `notification_history*`, `recently_used.json`, `usage_counts.json`, `wallpaper_shuffle.json`, `plugin-cache`, `community-*`), **Prism personal cache** (`minecraft/Distant_Horizons_server_data`, `saves`, `logs`, `crash-reports`, `screenshots`) |
| kavure | `/srv/data` | `zomboid/data`, `pz-dedicated`, `workshop-mods`, `sumaenimahub/SUMAENIMA-HUB`, `volumes`, `backup`, `aiostreams/anime-database`, **`minecraft/minecraftserver \[dominium\]/MINECRAFT SERVER`**, **`minecraft/minecraftserver \[dominium\]/crafty`**, **`minecraft/minecraftserver \[dominium\]/DOMINIUM-MODPACK`**, `minecraft/offbox`, `minecraft/pre-update` (06/10/2026 — tooling in `minecraft/minecraftserver [dominium]/` is mirrored). **GOLDEN FILES (08/10/2026):** fstab + **`/etc/unbound/unbound.conf.d/mnemocine.conf`** + **`/etc/sysctl.d/99-unbound.conf`** (recursive unbound config) + **32 systemd units** (`/etc/systemd/system/hl-*.{service,timer}` + `minecraft-status.service` + `unbound-status.service`). Systemd units are treated as configuration by homelab standards. |
| kuaray | `/home/kuaray/docker`, `/home/kuaray/homelab` | Generic exclusions |
| ybytu | `/home/ubuntu/homelab` | Generic exclusions |
| ybyra | `/home/ubuntu/homelab`, `docker-compose.ybyra.yml` | `*.tar.gz`/`*.zip`/`*.tgz`/`*.tar` |

**Global Exclusions (Secrets — NEVER mirrored):** `.env`, `secrets.yaml`, `slskd.yml`, `passwd`, `config.xml` (API keys), **`htpasswd`**, **`registry.key`** (registry certificates, 07/10/2026), `*.db`, `*.log`, `*.lock`, `.venv`, `node_modules`, `.git`, `.cache`, `.stversions`. Secrets reside strictly in the **sops/age vault** (`/mnt/NVME_PCI/secrets/`), synchronized encrypted via Syncthing.

**`mnemocine/` Excluded on Psicopompo (30/09/2026):** `/mnt/NVME_PCI/homelab/mnemocine` is a **derived mirror** — `homelab-docs-sync` copies from vault `agentic-ai/mnemocine` and publishes to public GitHub repository `MNEMOCINE`. The private backup circuit does not require a second redundant copy of documentation. See [`docs-sync.md`](docs-sync.md).

**Duplicate Basenames Handling (07/10/2026):** `/home/edu/homelab` (service compose files) and `/mnt/NVME_PCI/homelab` (projects) both map to destination `psicopompo/homelab/`. `rsync` resolves **duplicate paths preserving the FIRST specified source** — `/home/edu/homelab` is specified first, ensuring modern compose files with healthchecks take precedence. Registry secrets (`htpasswd`, `registry.key`) remain excluded; public certificates (`registry.crt`) are mirrored.

## Onboarding a New Service or Node

1. On node: Create/verify compose file in `/home/{user}/homelab/{service}/`.
2. Add directory to `SRC_DIRS` in `/etc/config-backup.conf` (and `EXCLUDES` for heavy data).
3. Validate compose syntax: `docker compose config --quiet`.
4. Trigger manual run: `sudo /usr/local/bin/config-backup` → verify files on NAS + `git log` / `restic snapshots`.
5. Document additions in vault.

## Restoration Procedures

- **Direct NAS Mirror:** Copy from `/mnt/BACKUP/configs-homelab/{host}/` back to destination host.
- **Incremental Historical Revisions:** `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password snapshots` + `restore`.
- **Mirror Anti-Deletion Snapshots:** `sudo snapper -c backup list` (btrfs snapshots of the mirror itself).
- **System Configuration (`/etc`):** `git --git-dir=/srv/backup-gitrepos/etckeeper-{host}.git log` (NAS) or locally via `git -C /etc log`.

## Incident: Stale NFS File Handle via Dead Automount (08/10/2026 — ybyra)

**Symptom:** `config-backup` on **ybyra** failing since **27/09/2026** (ntfy alert "config-backup FAILED (ybyra)"), with NAS mirror frozen. `rsync` logged:

```
rsync: [Receiver] ERROR: cannot stat destination "/srv/backup-configs/ybyra/": Stale file handle (116)
```

**Root Cause:** Unit `srv-backup\x2dconfigs.automount` was in an **`inactive (dead)` state since 28/08** (post-reboot). Mount served from an obsolete kernel state with legacy options (`hard,timeo=600`) — breaking when the NFS server invalidated the handle.

**Remediation (Per Host):**

```bash
U=$(systemd-escape -p --suffix=automount /srv/backup-configs)
umount -l /srv/backup-configs
systemctl daemon-reload
systemctl restart "$U"
ls /srv/backup-configs        # Retriggers automount
```

Also audited `/srv/backup-gitrepos` on ybyra and ybytu. Post-fix: Backup succeeded and git push resumed cleanly.

> ⚠️ **Key Takeaway:** `x-systemd.automount` can transition to a dead state post-reboot while the mount continues serving stale cached handles. A `hard` mount where `soft` was specified indicates an improperly reconstructed automount. Quick fleet check:  
> `findmnt -rn -t nfs4 -o OPTIONS | grep -c hard` (Expected output: **0** across all nodes).

## Security & Operational Safeguards

- `--delete-excluded`: Guarantees the mirror exactly matches desired declarative state (prevents secret leaks or obsolete config accumulation).
- Host source files are **strictly read-only**; the backup daemon never alters or removes files on client nodes.
- `-x` prevents crossing filesystem boundaries (prevents accidentally traversing massive NFS shares).
