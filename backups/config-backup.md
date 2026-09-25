---
tags: [homelab, backup, config, docker, compose]
---

# Canonical Config Backup — `config-backup`

> Central mirror of the CONFIGURATIONS of all hosts on the NAS (psicopompo `/mnt/BACKUP/configs-homelab`).
> It came out of the CasaOS lesson (08/08/2026): configs of ~12 containers deleted with no backup because **there was neither code nor mirror**.

## Architecture

```
Cada host (05:00) → /usr/local/bin/config-backup (systemd timer hl-config-backup.timer)
  0. GUARDA DE ROOT (10/08): `id -u` != 0 → aborta ANTES de rsync/ntfy
  1. check TCP 2049 (NAS alcançável) — fail-fast
  2. rsync -a --delete --delete-excluded --no-o --no-g -x  (só espelho; fontes são só lidas)
  3. golden files (composes + /etc selecionado) → <dest>/golden/
  4. ntfy /backup (falha=high, sucesso=low) + health file /srv/health/
      → espelho em /mnt/BACKUP/configs-homelab/{host}/
         ├─ git → GitHub privado mnemocine (05:55)
         ├─ restic → /mnt/BACKUP/repos/restic/configs (05:40, retenção 14d/8s/6m)
         └─ snapper (config `backup`) — anti-deleção do próprio espelho
```

**Standard schedule (05:00–06:00 BRT window; VPS at 08:00 UTC):**

| Time | Job |
|---|---|
| 04:55 | **noctalia-config-export (psicopompo, user)** — `noctalia config export` → `~/.config/noctalia/merged-config.toml` (effective layer: declarative + GUI overrides) |
| 05:00 | config-backup (all) |
| 05:00 | zomboid-restart (kavure, unchanged) |
| 05:15 | zomboid-backup (kavure) |
| 05:20 | agentic-ai-backup (psicopompo) |
| 05:40 | restic-configs-backup |
| 05:55 | etckeeper-push + configs-git-push |
| Sun 06:00 | restic check |

> **Policy note (24/09/2026):** the `~/.local/state/noctalia/settings.toml` override holds the idle policy of the Hyprland/Noctalia desktop (lock 900 s; screen off disabled while unlocked and 60 s when locked; lock+suspend disabled). That file is mirrored along with `~/.config/noctalia`; `merged-config.toml` is generated output only and must not be edited by hand.

## Components

| Piece | Where |
|---|---|
| Script | `/usr/local/bin/config-backup` (identical everywhere) |
| Per-host config | `/etc/config-backup.conf` (`SRC_DIRS`, `EXCLUDES`, `GOLDEN_FILES`, `MOUNT`, `HOST`, `POST_CMD`) |
| NFS export | `/mnt/BACKUP/configs-homelab` (rw, all_squash, anonuid=1000) + `/mnt/BACKUP/repos/git` |
| Mounts | `/srv/backup-configs` (configs), `/srv/backup-gitrepos` (bare git) — fstab `nofail` |
| Scheduling | systemd timer `hl-config-backup.timer` (05:00, `Persistent=true`) — migrated from cron on 10/08 |
| **Git push authentication (GitHub)** | `hl-configs-git-push.service` runs as `User=edu`; it uses git's **credential store** (`~/.git-credentials`, 0600, owner `edu`) with a PAT scoped to `repo` on the private `MNEMOCINE` repo. The token **NEVER** goes plaintext into the vault/NAS — backup in the **sops store** as `GH_PUSH_TOKEN` (`guides/secrets-centralizados.md`; restore: `sops-decrypt.sh GH_PUSH_TOKEN` → recreate `~/.git-credentials`). Canonized 21/09/2026 — before that the helper was `gh auth git-credential` (empty token → push had been failing silently since ~09/2026) |

> **Root guard (10/08/2026):** the script **must run as root** (the timer runs as root). Manual execution as non-root aborts immediately (`exit 1`, no rsync/ntfy) — this avoids a false "FAILED" alert. The script reads root-owned configs and writes to `/var/log` + `/srv/health`. To run it manually: `sudo /usr/local/bin/config-backup` (or `pkexec`).
| Health | `/srv/health/config-backup-{host}-last-ok` |

## Sources per host (what is mirrored)

| Host | SRC_DIRS | Main excludes |
|---|---|---|
| psicopompo | `/home/edu/homelab`, `/usr/local/bin`, syncthing state, **desktop configs** (`~/.config/hypr`, `~/.config/noctalia`, `~/.config/uwsm` — env: McMojave cursor + NVIDIA, `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia`, `~/.config/gtk-3.0`, `~/.config/gtk-4.0`, `~/.config/qt6ct`), rclone, wallpapers. **GOLDEN FILES:** `/var/lib/noctalia-greeter/greeter.toml`, `/etc/greetd/config.toml`, `/etc/systemd/sleep.conf.d/60-freeze.conf`, `/etc/systemd/system/tailscaled-wait.service`, `/etc/systemd/system/nfs-server.service.d/10-tailscaled-wait.conf`, `/etc/smartd.conf`, `/etc/sudoers.d/99-edu-homelab`, `/etc/ufw/user{,6}.rules`, `~/.gtkrc-2.0`, fstab, exports, pacman, snapper configs. | `ollama`, `index-v2`, `*.log`, **`target`** (Rust build), **Noctalia state** (`clipboard`, `notification_history*`, `recently_used.json`, `usage_counts.json`, `wallpaper_shuffle.json`, `plugin-cache`, `community-*`, `plugins/materialized`, `plugins/sources`, `plugins/data`) |
| kavure | `/srv/data` | `zomboid/data`, `pz-dedicated`, `workshop-mods`, `minecraft`, `sumaenimahub/SUMAENIMA-HUB`, `volumes`, `backup`, `aiostreams/anime-database` |
| kuaray | `/home/kuaray/docker`, `/home/kuaray/homelab` | (generic) |
| ybytu | `/home/ubuntu/homelab` | (generic) |
| ybyra | `/home/ubuntu/homelab`, `docker-compose.ybyra.yml` | `*.tar.gz`/`*.zip`/`*.tgz`/`*.tar` |

**Globally excluded (secrets — they NEVER go into the mirror):** `.env`, `secrets.yaml`, `slskd.yml`, `passwd`, `config.xml` (API keys), `*.db`, `*.log`, `*.lock`, `.venv`, `node_modules`, `.git`, `.cache`, `.stversions`. Secrets live in the **sops/age store** (`/mnt/NVME_PCI/secrets/`), which syncs encrypted via Syncthing.

## How to add a new service/host

1. On the host: create/confirm the compose in `/home/{user}/homelab/{serviço}/`.
2. Add the folder to `SRC_DIRS` in `/etc/config-backup.conf` (and `EXCLUDES` for heavy data).
3. `docker compose config --quiet` to validate the compose.
4. Run `sudo /usr/local/bin/config-backup` → check on the NAS + `git log`/`restic snapshots`.
5. Document in the vault + README-INDEX.

## Restore

- **Mirror (NAS):** copy from `/mnt/BACKUP/configs-homelab/{host}/` back onto the host.
- **Versions:** `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password snapshots` + `restore`.
- **Anti-deletion:** `sudo snapper -c backup list` (snapshot of the mirror itself).
- **Etckeeper (/etc):** `git --git-dir=/srv/backup-gitrepos/etckeeper-{host}.git log` (NAS) or on the host `git -C /etc log`.

## Security

- `--delete-excluded`: the mirror stays EXACT (it does not accumulate junk/secrets). Risk is limited to the mirror (protected by snapper + rebuilt from the source every night).
- Host sources are **read-only**; the script never writes/deletes on the hosts.
- `-x` prevents crossing NFS mounts (avoids scanning 62G of offbox — the kavure lesson).
