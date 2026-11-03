---
tags: [homelab, infra, guide]
pending: [HB-098]
---

# Disk hygiene audit and retention policy (2026-11-02)

Read-only audit of psicopompo and kuaray, ordered by a sub-agent and re-checked by the parent against the hosts (numbers below were confirmed with `docker system df`, `dust` and `ls -l`). Nothing was deleted by the audit.

## Finding: the weight is not hand-made `.bak` files
All `.bak`-style copies in the vault and the homelab total under 200 KB. The weight is **machine output without a retention rule**.

| Source | Size | Why it accumulates | Proposed rule |
|---|---|---|---|
| Docker BuildKit cache (psicopompo) | 48 GB | every image build by agents and CI-style loops | prune weekly: `docker builder prune --filter until=168h` |
| Rust `target/debug` (stenio, autopilot, hub server, arandu) | about 37 GB | every `cargo build`; stenio's sits inside the Syncthing vault | `cargo clean` after a build session; keep `release` only where a binary is used |
| pacman cache | 29 GB | never trimmed | `paccache -rk2` weekly (package `pacman-contrib`) |
| Trash (`~/.local/share/Trash`, `/mnt/NVME_PCI/.Trash-1000`) | 38 GB + 16 GB | deleted files stay until emptied | owner decides, then `trash-empty 30` weekly |
| OpenCode database | 24 GB | full session history | owner decides; cap or rotate |
| kuaray `/var/log/syslog*` | 14 GB (+3.9 GB journal) | kuaray Docker is a half-left Swarm worker (`Swarm: pending`, invalid join token) that retries TLS renewal in a loop, about 1.5 GB per day | fix the cause first (decide: leave the swarm or rejoin), then vacuum |
| Hub pre-deploy SQL dumps | 5.7 GB (31 files) | one per deploy | keep the newest 3 |
| kuaray unused images and dangling volumes | about 23 GB + 1.5 GB | old tags and stopped apps | `docker image prune` after the owner confirms the stopped apps; old tags are safe |
| Rollback image tags (`*-rollback-YYYYMMDD`) | small unique size | no expiry | delete after 14 days if the release is healthy |

## Retention policy proposed (to be turned into a timer, HB-098)
1. Regenerable output (build cache, `target/debug`, package caches, journals) is pruned by a weekly job with a report to ntfy; nothing is deleted without a log line.
2. Anything with possible value (trash, session DBs, VM disks, stopped apps, dumps with data) is **never** deleted by a job: it is listed in the weekly report and the owner decides.
3. An agent that creates a copy before editing (`*.bak-<date>-<reason>`) records it in the same change and removes it after the change is verified, or the copy goes to the dated config backup instead of beside the file.
4. Rust build output stays out of synced folders (`CARGO_TARGET_DIR` outside the vault).
5. Secrets copies (`secrets.enc.env.bak-*`, `.env.bak-*`) are rotated and shredded, never listed or opened.

## Executed on 2026-11-02 (owner approved each batch)
| Batch | Result |
|---|---|
| Docker build cache on psicopompo | 48 GB pruned (`docker builder prune -af`) |
| pacman cache | `paccache -rk2` removed 629 packages, 8 GB saved (21 GB remain: installed packages keep two versions) |
| App caches (`paru`, `Shelly`, `chromium` under `~/.cache`) | 6.3 GB removed |
| Rust `target/debug` (stenio, autopilot, hub server) | about 33 GB removed |
| Trash (two expunged folders) | 54 GB removed; the 41 GB file deleted on 30 Oct could not be identified before removal |
| OpenCode database | 27 GB removed (`opencode.db`); history of past sessions is gone |
| kuaray swarm leftover | `docker swarm leave`; `Swarm: inactive`; syslog.1 and syslog.2.gz removed; `/` went from 73 GB to 58 GB used |
| kuaray old image tags (delegated to a sub-agent with exact commands; verified by the parent) | 4 unused older tags removed (home-assistant 2025.11, duplicati 2.1.0, pihole 2025.11.1, alpine 3.19), 4 GB; `/` now 55 GB used; 32 containers unchanged |
| psicopompo `/` | 223.6 GB to 143.7 GB used |

Unused images kept on kuaray (about 20 GB, apps that look stopped: calibre-web-automated, home-assistant, kavita, umami, wallabag, stremio, steniobot-api and others) wait for the owner's decision; `postgres:15-alpine` was kept because 16 is a different major version.

Images removed after the Homepage cross-check (read-only inventory by sub-agents, then exact `docker rmi` commands, no `-f`): kuaray 27 unused images (images 35 GB to 15 GB, `/` 55 GB to 36 GB used), ybyra 12 old build IDs (0.5 GB), psicopompo 14 unused tags (about 4 GB; `rust:latest`, `front-builder` and the `:cpu` tags kept because they may be build bases).

ybytu (after the inventory): 7 unused tagged images removed and `docker image prune -f` cleared 189 dangling images, 19.8 GB reclaimed; `/` went from 34 GB to 13 GB used (71% to 26%), and the 11 containers were unchanged. The dangling pile is probably Watchtower pull cycles, which the weekly job (HB-098) will keep down.

Incident caused by this work: `docker swarm leave` on kuaray broke container-to-container name resolution (see `servers/kuaray.md`). Lesson: a cleanup that changes the Docker engine mode is a service change, not a cleanup; research and a rollback come first (rule 11 and 5).

Still open (HB-098): the weekly prune job with report, `CARGO_TARGET_DIR` outside the vault, Hub dump retention, rollback image tags, dangling volumes on both hosts, the 16 GB Kali disk, and the `node rm` of kuaray on kavure. `/mnt/NVME_PCI` showed no change in `df` right after the prune (btrfs frees space lazily and the containerd data may be pinned by snapshots): re-check in a day.


## Installation (weekly `hl-hygiene`, HB-098)

Delivered but **not installed** (2026-11-02). Source in the `mnemocine-ops` repo: `provisioning/scripts/hl-hygiene`, `provisioning/systemd/hl-hygiene.{service,timer}`, registered in `install-homelab-tools.sh`. The timer runs Sundays 04:30 (`Persistent=true`) as `hl-hygiene --apply --notify`.

Behaviour: the default mode is report only. `--apply` prunes only `docker builder prune --filter until=168h`, `docker image prune -f` (dangling), `paccache -rk2`, `journalctl --vacuum-size=500M` and `target/debug` of cargo projects whose newest file is over 14 days old (never inside the vault). Volumes, named images, containers, Trash, `/srv/data`, the vault and backups are never touched. `--apply --dry-run` prints the exact commands without running them. The ntfy report (`/alerts`, no token) is sent only if reclaimable space is at least 5 GB (`--threshold-gb`) or any mount has under 15% free. Host label: `--host NAME` (default `hostname -s`).

Per host (psicopompo, kuaray, kavure, ybytu, ybyra), from a checkout of `mnemocine-ops`, replace `<host>` with the host name:
```bash
cd /mnt/NVME_PCI/homelab/mnemocine-ops/provisioning
sudo install -m 0755 scripts/hl-hygiene /usr/local/bin/hl-hygiene
sudo install -m 0644 systemd/hl-hygiene.service systemd/hl-hygiene.timer /etc/systemd/system/
/usr/local/bin/hl-hygiene --host <host>                 # report only, check the numbers
/usr/local/bin/hl-hygiene --apply --dry-run --host <host>   # exact commands, nothing runs
sudo systemctl daemon-reload
sudo systemctl enable --now hl-hygiene.timer
systemctl list-timers hl-hygiene.timer
```
Optional first week in report-only mode: after the `install` lines, run `sudo systemctl edit hl-hygiene.service`, set `ExecStart=` then `ExecStart=/usr/local/bin/hl-hygiene --notify`, and revert after the first report. On a host without `paccache` (Debian family) or without docker, the section prints `n/a`. Needs only coreutils (`numfmt`, `du`, `df`), `find`, `grep`, `sed`, `awk` and `curl`.

Rollback (per host):
```bash
sudo systemctl disable --now hl-hygiene.timer
sudo rm /etc/systemd/system/hl-hygiene.service /etc/systemd/system/hl-hygiene.timer /usr/local/bin/hl-hygiene
sudo systemctl daemon-reload
```
What `--apply` removed cannot be restored, but it is regenerable output (cache and build artifacts).

## Installed on 2026-11-02 (owner approved the weekly automatic clean-up)
`hl-hygiene` and `hl-hygiene.timer` are installed and enabled on psicopompo, kuaray, kavure, ybytu and ybyra (`/usr/local/bin/hl-hygiene`, units in `/etc/systemd/system`). Next run: Sunday 2026-11-08 04:30 (host local time). Mode: `--apply --notify` (the service file). Before enabling, each host ran the report and `--apply --dry-run` (the dry-run output lists only the safe categories). Version control: the tool lives in the `MNEMOCINE-OPS` repository (`provisioning/scripts/hl-hygiene`, `provisioning/systemd/hl-hygiene.*`, commit `548a38e`, pushed), installed by the same commands as the other `hl-*` tools. Rollback per host: `sudo systemctl disable --now hl-hygiene.timer && sudo rm /etc/systemd/system/hl-hygiene.{service,timer} /usr/local/bin/hl-hygiene && sudo systemctl daemon-reload`.

