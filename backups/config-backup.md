---
tags: [homelab, backup, config, docker, compose]
pending: [HB-130, HB-133, HB-135, HB-136, HB-137]
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

> **Desktop Idle Policy Note (24/09/2026, atualizado 21/10/2026):** Override file `~/.local/state/noctalia/settings.toml` houses desktop idle management (screen lock 900s; display sleep disabled while unlocked and 60s when locked; suspend disabled; pre-action fade desativado em 0s para evitar apagão visual antes do lock). Mirrored alongside `~/.config/noctalia`; `merged-config.toml` is strictly a generated export artifact and must not be edited directly.  
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
| **Git Push Guards (19/10/2026)** | `configs-git-push` carries three safeguards: (a) **size guard** — aborts *before* committing (ntfy `high` + `OnFailure`) when any indexed blob exceeds **95 MB**, because GitHub refuses files >100 MB and rejects the **whole push**; (b) **health stamp** `/srv/health/configs-git-push-last-ok` on every successful run; (c) **diagnostics** — the raw `git push` output goes to the unit's journald log instead of `/dev/null`. Heavy artefacts stay **out of git** through the mirror's `.gitignore` while remaining in the NAS mirror, restic and Google Drive. |

> **Root Privilege Guard (10/08/2026):** The script **must execute as root** (systemd timer runs as root). Unprivileged manual invocations abort immediately (`exit 1` without rsync or ntfy dispatch) — preventing false failure alerts. To run manually: `sudo /usr/local/bin/config-backup`.

| Health Stamp | `/srv/health/config-backup-{host}-last-ok` |
| Health Stamp (git push, 19/10/2026) | `/srv/health/configs-git-push-last-ok` — touched on every successful run (including "no changes"); feeds `homelab_backup_last_ok_seconds{job="configs-git-push"}` → Grafana `BackupNotRun` (>26h). See the incident below |

> **Health stamps are empty on purpose (HB-010, verified 2026-11-26).** The scripts only `touch` them: **the mtime is the signal, the content is always empty** (`eza -l /srv/health/` shows size 0 for every stamp, which is normal and not a failure). Check one with `stat -c '%y' /srv/health/<job>-last-ok`; `health-files-metrics.sh` exports the mtime as `homelab_backup_last_ok_seconds`.

> **Host mount dependency in the units (HB-009, MNEMOCINE-OPS PR #25, installed on psicopompo 2026-11-27).** Verified that day: psicopompo `--units` PASS with the drop-ins loaded; the live units on kavure, kuaray and ybytu have no mount line and ybyra mounts only its own `/srv/backup-*` paths (those remote units were not overwritten and still `DIFFERS` from the repo). `hl-config-backup.service` and `hl-etckeeper-push.service` are one generic unit with no mount line; only psicopompo adds `RequiresMountsFor=/mnt/BACKUP` through `provisioning/systemd/hosts/psicopompo/<unit>.d/10-nas-mount.conf`, installed by `install-homelab-tools.sh --host psicopompo --units`. Clients reach the NAS through `x-systemd.automount` and the script's own reachability probe.

> **Drift pass, 2026-11-27.** The `config-backup` script on kavure, kuaray, ybytu and ybyra was one older revision (`67b6f43`) differing only in comments; the repository version is installed (`--check` PASS, rollback `/usr/local/bin/config-backup.prev-o1`). Units that differed **only in comments** were refreshed one by one, never with `--units` (rollback `<unit>.prev-o1`): `config-backup`, `etckeeper-push` and `notify-backup-failure@` services on kavure, kuaray and ybytu, plus `hl-autopilot.service` and `hl-scryfall-prefetch.{service,timer}` on kavure.
> **Kept on purpose, do not run `--force-units` there:** the live unit is right and the repository unit is generic. kavure: `Environment=` bind addresses of `minecraft-status`, `unbound-status`, `zomboid-health`; `ExecStartPost=touch` stamps of `n8n-backup`, `scryfall-mirror`; `TimeoutStartSec=1200` of `valheim-backup`. ybytu: UTC calendar times of the `config-backup` and `etckeeper-push` timers. ybyra: `RequiresMountsFor=/srv/backup-*` in both services. These need host drop-ins in the repository.

> **Failed runs and a DNS outage, 2026-11-27.** On `ybytu` (952 MiB RAM) both runs of the day failed and starved the host: a manual verification run at 07:32 UTC (stopped by hand at 07:49) and the 08:00 UTC timer (failed 08:24, `close failed ... .kuma.snapshot ... Input/output error`, kernel `nfs: server 100.82.51.112 not responding`). Prometheus shows `homelab_adguard_probe_ok=0` and the node target down for most of both windows, so AdGuard and ntfy were unreachable for long stretches; the last good mirror of `ybytu` is 2026-11-26. A failed run of the same kind happened on 11-22. On `kavure`, manual runs at 04:21 and 04:32 BRT failed or were stopped after about 2 GB of Valheim server files changed (same `Input/output error`; load reached 30 and Pi-hole timed out for a short while); the 05:00 run succeeded. **Do not start these backups by hand on `ybytu`.** Likely cause (inference): large files over a `soft,timeo=30,retrans=2` NFS mount.

## Load Bounds (HB-130, 2026-11-27, MNEMOCINE-OPS PR #34)

**What a run costs (measured 2026-11-27):** on `ybytu` the daily bulk is one file, `uptime-kuma/kuma.snapshot` (525 MB, rewritten at 04:45). The old `kuma.db.bak-*` copies (380 MB) are unchanged, so rsync does not resend them; they stay in the mirror and are **not** excluded. On `kavure` a normal delta was about 258 MB; a Valheim update adds about 2 GB of server files.

**Script revision `68349e6f…` is installed on all five hosts** (`ybytu` and `kavure` first; `psicopompo`, `kuaray` and `ybyra` later the same day, `--check` PASS on each). The per-host bounds below exist **only on `ybytu` and `kavure`**: the repository defines no limits drop-in for the other three and their `config-backup.conf` sets none of the new keys, so the script defaults apply (`BWLIMIT` 8000 KiB/s on `kuaray` and `ybyra`, unlimited on `psicopompo`; no resolver guard). Dry runs with the installed rsync arguments ended with status 0 on the three; one bounded run on `psicopompo` (`systemd-run`, 10 min timeout) succeeded in under 5 s. First timer run on `kuaray` and `ybyra` with this revision: not yet observed. Rollback on those three: `sudo cp -p /usr/local/bin/config-backup.prev-o3 /usr/local/bin/config-backup`.


| Bound | `ybytu` | `kavure` |
|---|---|---|
| `BWLIMIT` (rsync, KiB/s) | 600 | 8000 |
| `GUARD_RESOLVERS` (rsync stops after 2 failed probes, no retry, ntfy) | AdGuard + Pi-hole | AdGuard + Pi-hole |
| Drop-in `hl-config-backup.service.d/20-limits.conf` (`CPUQuota`, `MemoryHigh`/`Max`, `TimeoutStartSec`) | 25 %, 96/192 MB, 40 min | 50 %, 384/768 MB, 30 min |
| `KEEP_EXCLUDED` (not copied, mirrored copy **not** deleted) | **`uptime-kuma/kuma.snapshot` (temporary, see below)** | Valheim server files under `data/valheim/data/` (Steam app 896660, reinstalled by SteamCMD); `BepInEx` and `.staging` are still copied |

The consequence of the guard: if either resolver is down, the backup does not run and says so.

- **Rollback (each host):** `sudo cp -p /usr/local/bin/config-backup.prev-o2 /usr/local/bin/config-backup; sudo cp -p /etc/config-backup.conf.prev-o2 /etc/config-backup.conf; sudo rm /etc/systemd/system/hl-config-backup.service.d/20-limits.conf; sudo systemctl daemon-reload`.
- **NFS timeout not changed.** The mandatory `fstab` options in [`../AGENTS.md`](../AGENTS.md) are `soft,timeo=30,retrans=2`; `nfs(5)` gives 600 deciseconds as the TCP default and says a higher `retrans` may mitigate the corruption risk of `soft`. Raising it is an owner decision.

- **Verification, 2026-11-27 (`systemd-run`, same limits, both resolvers probed from `psicopompo`):** `kavure` succeeded in 86 s with no failed probe. `ybytu` **with** the snapshot at 1500 KiB/s failed the test: load reached 20, CPU steal 1.0 to 1.4 of 2 vCPUs, one AdGuard probe from `psicopompo` failed after 248 s and the run was stopped (memory available stayed above 300 MB, so the likely limit is CPU spent by `tailscaled`; inference). `ybytu` **without** the snapshot succeeded in about 2 minutes or less with no failed probe.
- **Open gap: the Uptime Kuma database is not leaving `ybytu`.** `kuma.snapshot` is still written locally at 04:45 UTC (journal, 2026-11-27); the mirrored copy is the one of 2026-11-26 and is protected. The `config-backup` health stamp does **not** show this gap. Options (HB-130): compress the snapshot at source before it is mirrored (changes the restore format), send it by a separate throttled path, or shrink the Kuma history. Restore the old behaviour with `/etc/config-backup.conf.prev-o2-snapshot` (not safe on this host as measured).
- **Compression at source measured, not enabled (2026-11-27 evening, HB-135, MNEMOCINE-OPS PR #38 kept as draft).** Bounded transient units with both resolvers probed from `psicopompo`: `zstd -3 --rsyncable` took the 525 MB snapshot to 130 MB in 84 s (16 s CPU, `CPUQuota=20%`), 0 failed probes; the transfer of that file to the NAS at 600 KiB/s took 217 s, 0 failed probes. The end-to-end run of the snapshot unit with the new script (21:49 UTC) then **failed the criterion**: external probes of the resolvers failed while the existing, unbounded `sqlite3 .backup` step was running (before compression started at 21:51), load reached about 23, and the unit was stopped at 21:52. The local Prometheus metric `homelab_adguard_probe_ok` recorded no failure in that window. The host is back on the previous script and configuration. The 04:45 UTC timer still runs the same backup step.
- **One current off-host copy exists:** `kuma.snapshot.zst` (made from the 04:45 UTC snapshot of 2026-11-27) is in the `ybytu` mirror; on `psicopompo` it decompressed and `PRAGMA quick_check` returned `ok` (50 monitors). The same file stays at the source path so the daily mirror run keeps it without resending it (size and modification time are identical on both sides, checked 2026-11-27, so rsync has nothing to resend; confirm after the next run). It is **not refreshed**. The mirror `.gitignore` keeps it out of GitHub (file above 95 MB).
- **Bounded sqlite step tested, failed, not installed (2026-11-28 01:58 UTC, MNEMOCINE-OPS PR #38, draft).** The whole new script ran as a transient unit on throwaway paths: each heavy step with `CPUQuota=20%`, `MemoryHigh=64M`, `MemoryMax=160M` and 4 MB/s read and write (`io.max` confirmed on the host), and `.backup` inside one read transaction (without it, every Kuma write restarts a slow copy). Both resolvers were probed from `psicopompo`: 0 failed in the 90 s baseline, then one AdGuard probe failed 129 s after start, with about 452 MB of the copy written; the local probes on `ybytu` had not failed. The units were killed 18 s after the failure (the on-host watcher lagged behind its heartbeat queue), the test files removed, and 30 later rounds against both resolvers had 0 failures. The host already showed memory pressure before the test (`/proc/pressure/memory` `some avg60` about 13 to 24 %), so the cause is not isolated. The installed script and timer are unchanged.

### `apt-daily` on `ybytu` (same day)

`apt-daily.service` (`unattended-upgrade --download-only`, started 11:04:52 UTC) thrashed the host for more than 35 minutes and AdGuard failed most probes until it was stopped (about 11:45 UTC). It started during agent work on the host (a `daemon-reload` as trigger is not ruled out). Now installed from MNEMOCINE-OPS PRs #35/#36: `apt-daily.service.d/20-limits.conf` (CPU and memory bounds, 30 min timeout), timers `apt-daily` 14:00 UTC + 1 h and `apt-daily-upgrade` 16:00 UTC + 30 min (`20-window.conf`); `apt-daily-upgrade` keeps its existing `50-limits.conf` (HB-117/118). First bounded `apt-daily` run: 14:54 UTC, 57 s. Rollback: remove `20-limits.conf` and the two `20-window.conf`, then `daemon-reload`.

## Sources by Host (Mirrored Assets)

| Host | SRC_DIRS | Primary Exclusions |
|---|---|---|
| psicopompo | `/home/edu/homelab` (**Service compose files** — first in list), `/mnt/NVME_PCI/homelab` (**Project roots**: sumaenimahub, transcribe, …), `/usr/local/bin`, syncthing state, **Desktop configs** (`~/.config/hypr`, `~/.config/noctalia`, `~/.config/uwsm`, `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia`, `~/.config/gtk-3.0`, `~/.config/gtk-4.0`, `~/.config/qt6ct`, **`~/.config/fish`** — shell config, 06/10/2026), **Dominium Prism Instance** (`~/.local/share/PrismLauncher/instances/Dominium` — modpack source of truth: mods/config/loader, ~484 MB), **PCSX2** (`~/.config/PCSX2` — inis, memory cards, savestates; 01/11/2026), rclone, wallpapers. **GOLDEN FILES:** `/var/lib/noctalia-greeter/greeter.toml`, `/etc/greetd/config.toml`, `/etc/systemd/sleep.conf.d/60-freeze.conf`, `/etc/systemd/system/tailscaled-wait.service`, `/etc/systemd/system/nfs-server.service.d/10-tailscaled-wait.conf`, `/etc/smartd.conf`, `/etc/sudoers.d/99-edu-homelab`, `/etc/ufw/user{,6}.rules`, `~/.gtkrc-2.0`, **`~/.ssh/config`** (SSH host configuration without private keys), fstab, exports, pacman, snapper configs. | `ollama`, `index-v2`, `*.log`, **`target`** (Rust build artifacts), **Noctalia runtime state** (`clipboard`, `notification_history*`, `recently_used.json`, `usage_counts.json`, `wallpaper_shuffle.json`, `plugin-cache`, `community-*`), **Prism personal cache** (`minecraft/Distant_Horizons_server_data`, `saves`, `logs`, `crash-reports`, `screenshots`), **PCSX2 game disc images** (`*.iso`, `*.chd`, `*.cso`) |
| kavure | `/srv/data`, `/home/kavure/homelab/sumaenima-socialmedia-autopilot` (engine source, 2026-10-19), `/home/kavure/autopilot/tenants/sumaenima` (tenant: packs + config + `var/`, 2026-10-21) | `zomboid/data`, `pz-dedicated`, `workshop-mods`, `sumaenimahub/SUMAENIMA-HUB`, `volumes`, `backup`, `aiostreams/anime-database`, **`minecraft/minecraftserver \[dominium\]/MINECRAFT SERVER`**, **`minecraft/minecraftserver \[dominium\]/crafty`**, **`minecraft/minecraftserver \[dominium\]/DOMINIUM-MODPACK`**, `minecraft/offbox`, `minecraft/pre-update` (06/10/2026 — tooling in `minecraft/minecraftserver [dominium]/` is mirrored). **GOLDEN FILES (08/10/2026):** fstab + **`/etc/unbound/unbound.conf.d/mnemocine.conf`** + **`/etc/sysctl.d/99-unbound.conf`** (recursive unbound config) + **32 systemd units** (`/etc/systemd/system/hl-*.{service,timer}` + `hl-minecraft-status.service` + `hl-unbound-status.service`). Systemd units are treated as configuration by homelab standards. |
| kuaray | `/home/kuaray/docker`, `/home/kuaray/homelab` | Generic exclusions |
| ybytu | `/home/ubuntu/homelab` | Generic exclusions |
| ybyra | `/home/ubuntu/homelab`, `docker-compose.ybyra.yml` | `*.tar.gz`/`*.zip`/`*.tgz`/`*.tar` |

> **Autopilot engine + tenant (2026-10-21, HB-079):** kavure mirrors the **engine**
> (`/home/kavure/homelab/sumaenima-socialmedia-autopilot`, source; `target/` excluded) and the
> **tenant** (`/home/kavure/autopilot/tenants/sumaenima`: personas, config and `var/`, **185
> files**). The four `10-kavure.conf` drop-ins now carry `AUTOPILOT_TENANT_DIR` and
> `AUTOPILOT_SECRETS`; they and the units are golden files. On psicopompo, `golden/` keeps
> `ollama-tailnet.socket`, `ollama-tailnet.service` and `ollama.service.d/10-models.conf`. The
> tenant is the single writer; the old engine `var/` is frozen for rollback.

**Global Exclusions (Secrets — NEVER mirrored):** `.env`, `secrets.yaml`, `slskd.yml`, `passwd`, `config.xml` (API keys), **`htpasswd`**, **`registry.key`** (registry certificates, 07/10/2026), `*.db`, `*.log`, `*.lock`, `.venv`, `node_modules`, `.git`, `.cache`, `.stversions`. Secrets reside strictly in the **sops/age vault** (`/mnt/NVME_PCI/secrets/`), synchronized encrypted via Syncthing.

**Correction (23/11/2026, GB-285, second instance of the same shape after 29/09/2026):** the claim above was false for `*.env`. rsync's `--exclude '.env'` and the mirror `.gitignore` entry `.env` match the **exact basename only**, so `n8n.env`, `searxng.env` and `zomboid.env` (kavure, copied on 30/10/2026), `transmission.env` and `winboat.env` reached the private GitHub repo `MNEMOCINE-CONFIGS` in clear (a mod web-config password too). Two layers now exist and must not be confused:
- **NAS mirror (`/mnt/BACKUP/configs-homelab`, restic, snapper):** deliberately keeps these files. The mirror is the only copy of anything outside a git remote, so excluding them would lose them. Their values also live in the sops store (`N8N_DB_PASSWORD`, `N8N_BASIC_AUTH_PASSWORD`, `SEARXNG_SECRET`, `ZOMBOID_RCONPASSWORD`, `WINBOAT_PASSWORD`, `TRANSMISSION_ENV_PASS`, `DOMINIUM_RESOURCEFUL_WEB_PASSWORD`; compared by machine against the files, same values, nothing printed).
- **GitHub (`MNEMOCINE-CONFIGS`):** `*.env` is now in the mirror `.gitignore`, the 6 files were removed from the index (`git rm --cached`, the files stay on the NAS) and `configs-git-push` has a **secret guard** (source `provisioning/scripts/configs-git-push` in `MNEMOCINE-OPS`): it is one call to **`stenio secrets-guard --repo … --baseline .secret-baseline --scope mirror`** (engine 4.40.0, since 23/11/2026; it was a shell guard with the same rules until PR 14). It aborts the push with ntfy `high` when a tracked path is credential-shaped (`*.env` except `*.env.example`, `*.pem`, `*.key`, `id_*`, `*.kdbx`, `*.p12`, `*.pfx`, `*.ovpn`, `htpasswd`), when `SEC-PLAINTEXT-SECRET` is reported in a tracked path outside `.secret-baseline` (reviewed placeholders and password hashes), or when a credential-shaped file is tracked although ignored; exit 2 (the guard itself failed, for example a missing binary) also aborts. It prints **paths and line numbers only**: the stenio JSON `snippet` field could hold the secret itself and 4.40.0 now masks it. Tested by `provisioning/tests/configs-git-push-test.sh` (9 cases, fake secret, in `MNEMOCINE-OPS`); run for real on 23/11/2026 (push `2231e794` with the shell guard, `sem mudanças` with the engine guard).
- **Not done (owner decision, 23/11/2026):** no rotation, and the old values remain in the history of the private repo (commits since 30/10/2026). `stenio --history` measures it; a history purge or rotation stays open in GB-285.
- **Rollback:** `sudo install -m 755 /usr/local/bin/configs-git-push.prev-shellguard /usr/local/bin/configs-git-push` (the shell-guard version, one step back), or `…/configs-git-push.prev` for the pre-guard 70-line script as it ran until 23/11/2026 (it was never in git, so that copy is the only one). Reverting the `MNEMOCINE-OPS` PR alone would restore the older 18-line version, which lacks the size guard: do not.

**`mnemocine/` Excluded on Psicopompo (30/09/2026):** `/mnt/NVME_PCI/homelab/mnemocine` is a **derived mirror** — `homelab-docs-sync` copies from vault `agentic-ai/mnemocine` and publishes to public GitHub repository `MNEMOCINE`. The private backup circuit does not require a second redundant copy of documentation. See [`docs-sync.md`](docs-sync.md).

**Dependency Manifests of Git Clones Excluded on Psicopompo (21/11/2026, owner-approved):** the mirror becomes the private repo `MNEMOCINE-CONFIGS`, so copies of `package-lock.json` / `Cargo.toml` taken from project clones raised **false/duplicate Dependabot alerts** (#31-#43 on `psicopompo/homelab/sumaenimahub/sumaenima-hub/app/frontend-v2/package-lock.json`, #37-#39 on `psicopompo/homelab/mcmojave-cursor-unified/Cargo.toml`); the real sources are GitHub repos with their own Dependabot.
- **What:** `/etc/config-backup.conf` `EXCLUDES` gained **per-clone, root-anchored** patterns (`/homelab/<clone>/…`, relative to the transfer root of `/mnt/NVME_PCI/homelab`; rsync anchors a leading `/` to the transfer root and `**` crosses directories — [rsync(1) include/exclude rules](https://download.samba.org/pub/rsync/rsync.1)) for `Cargo.toml` and `package-lock.json` in `hyprland-focused-booster`, `kururu-tab3lite-linux`, `mcmojave-cursor-unified`, `valheim-path-tracing`, `with-smooth-motion`, `sumaenimahub/sumaenima-hub`, plus nine explicit `mnemocine-ops/provisioning/*/Cargo.toml`. `Cargo.lock` was already dropped by the global `*.lock`. Dry-run proof: exactly **27** files leave the mirror, nothing else changes.
- **Why not global:** the mirror is the **only copy** of anything outside a git remote, so a global `Cargo.toml`/`package-lock.json` exclude was refused. Only clones with a GitHub remote of the owner, tracked + unmodified files and no unpushed commit touching them qualify. **Kept in the mirror on purpose:** `mnemocine-ops/provisioning/hypr-session-track/Cargo.{toml,lock}` (unpushed local commit), `sumaenima-socialmedia-autopilot` (no remote), `steam-launch-options` (not a git repo). Remote refs were read without `git fetch` and may be stale.
- **Effect:** `--delete-excluded` removes the 27 files from `/mnt/BACKUP/configs-homelab/psicopompo/homelab/` at the next 05:00 run; the 05:55 `configs-git-push` then commits the deletions to `MNEMOCINE-CONFIGS`, and GitHub closes the alerts automatically once the manifests are gone from the default branch (history stays in git and restic).
- **Rollback:** `sudo cp -p /etc/config-backup.conf.bak-20261121 /etc/config-backup.conf` (removable once validated); the files return to the mirror at the next run. New crates or clones are **not** covered automatically: add an anchored line per clone after checking the remote is pushed.

**Duplicate Basenames Handling (07/10/2026):** `/home/edu/homelab` (service compose files) and `/mnt/NVME_PCI/homelab` (projects) both map to destination `psicopompo/homelab/`. `rsync` resolves **duplicate paths preserving the FIRST specified source** — `/home/edu/homelab` is specified first, ensuring modern compose files with healthchecks take precedence. Registry secrets (`htpasswd`, `registry.key`) remain excluded; public certificates (`registry.crt`) are mirrored.

## Onboarding a New Service or Node

1. On node: Create/verify compose file in `/home/{user}/homelab/{service}/`.
2. Add directory to `SRC_DIRS` in `/etc/config-backup.conf` (and `EXCLUDES` for heavy data).
3. Validate compose syntax: `docker compose config --quiet`.
4. Trigger manual run: `sudo /usr/local/bin/config-backup` → verify files on NAS + `git log` / `restic snapshots`.
5. Document additions in vault.

## Stenio Work Ledger Backup (psicopompo, verified 2026-11-27)

The shared work ledger (`~/.local/state/stenio/hub.db`) has its own user timer, separate from
`config-backup`: `stenio-hub-backup.timer` (daily 04:30, `Persistent=true`; units in
`~/.config/systemd/user/`). It runs `stenio hub backup --out /mnt/BACKUP/stenio-hub --keep 30`
(online snapshot plus JSONL event export, restore-tested in a local scratch directory) and then
`stenio hub backup --check`. `stenio hub status` shows `backup stale` after 26 hours.

- Restore: stop agent sessions, move `hub.db`, `hub.db-wal` and `hub.db-shm` aside, copy the
  newest `hub-*.db` to `~/.local/state/stenio/hub.db`, run `stenio hub audit`.
- Disable: `systemctl --user disable --now stenio-hub-backup.timer`.

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

## Incident: Silent GitHub Push Failure (16–19/10/2026 — psicopompo)

**Symptom:** none — which is the whole problem. Grafana stayed green, no ntfy message arrived, and the private GitHub mirror (`MNEMOCINE-CONFIGS`) had been frozen at commit `06c3b26f` (16/10) for **three days**.

**Root cause:** the daily commit of 17/10 picked up `ybytu/homelab/uptime-kuma/kuma.snapshot` — an Uptime Kuma database dump that grows daily (**106 → 134 MB**). GitHub refuses any file >100 MB and rejects the **entire push**, so the runs of 17, 18 and 19/10 all exited `status=1` ("push FALHOU") at 05:55.

**Why nobody knew — three blind spots, all closed:**

| Blind spot | Fix (2026-10-19) |
|---|---|
| `git push origin main >/dev/null 2>&1` discarded the error | the git output now goes to journald (`logger`) and its last lines are embedded in the ntfy alert |
| **No health stamp** → `BackupNotRun` (>26 h) never watched this job | stamp `/srv/health/configs-git-push-last-ok` on every successful run → `homelab_backup_last_ok_seconds{job="configs-git-push"}`; the rule `(time() - homelab_backup_last_ok_seconds) > 26 * 3600` has **no job filter** (verified against Prometheus on kavure), so new jobs are covered automatically |
| **No `OnFailure=`** → a failed *run* produced no signal at all | `OnFailure=notify-backup-failure@%n.service` on the unit (ntfy `high`) |

**Remediation:** `kuma.snapshot` was added to the mirror's `.gitignore` (heavy runtime dumps belong to the NAS mirror + restic + Google Drive, not to git); the three never-pushed commits were folded into a single `auto:` commit (`git reset --soft origin/main` → `git rm --cached` → commit) and pushed — the remote is back in sync (`8cb2e96c`). The size guard makes a recurrence loud instead of silent. **Preserved on disk:** the snapshot itself (134 MB, at `ybytu/homelab/uptime-kuma/`) and the pre-rewrite commits (reachable through the mirror's `git reflog`) — nothing was deleted to fix the push.

**Lesson:** an off-site copy that fails *silently* is worse than no off-site copy, because recovery is planned around it. Every job in the backup chain needs **both** a freshness stamp and an `OnFailure` alert.

## Security & Operational Safeguards

- `--delete-excluded`: Guarantees the mirror exactly matches desired declarative state (prevents secret leaks or obsolete config accumulation).
- Host source files are **strictly read-only**; the backup daemon never alters or removes files on client nodes.
- `-x` prevents crossing filesystem boundaries (prevents accidentally traversing massive NFS shares).
