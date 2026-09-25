---
tags: [homelab, service, syncthing, storage]
---

# Syncthing

File sync between devices — keeps the Obsidian vault and other data in sync.

**Server:** Distributed mesh (psicopompo ↔ kuaray ↔ ybytu ↔ phones)

## Instances

| Server | Type | User | Folder | Status |
|---|---|---|---|---|
| psicopompo | Native — systemd user unit `syncthing.service` (config in `~/.local/state/syncthing/config.xml`) | edu | folders below | ✅ **active** (10/08) |
| kuaray | Container (`syncthing/syncthing`) | — | `/config/Sync/...` | ✅ active |

> **Ybytu removed (06/08/2026):** Syncthing container + folders deleted (not needed). Ybytu device removed from psicopompo's config.

## Folders (07/08/2026)

| id | label | psicopompo | kuaray | Content |
|---|---|---|---|---|
| `default` | `default-folder-syncthing` | `/home/edu/Default Folder Syncthing/` (**sendreceive**, source) | `/home/kuaray/Default/` (container `/default`, **receiveonly**) | kdbx (KeePass), CNH, personal docs |
| `agentic-ai` | `agentic-ai` | `/mnt/NVME_PCI/agentic-ai/` | `/home/kuaray/agentic-ai/` (container `/agentic-ai`, **receiveonly**) | **Obsidian vault + working folder** |
| `backup` | `backup` | `/mnt/BACKUP/` (source, **sendreceive**) | `/mnt/storage/backup/` (**receiveonly**) | **Cold mirror of the backup** — music, books, recovery, dumps |

> **Folder `default` (10/08/2026):** kuaray became a **receiveonly mirror** of psicopompo's `default` (path moved from `/config/Sync/` → `/home/kuaray/Default/`, outside the config dir). Consistent naming on both hosts. Before that, kuaray's `default` was a **local-only** folder (not connected to psicopompo) and empty.

> **Folder `music` removed (07/08):** music is NO LONGER synced to kuaray — the services (Navidrome, Lidarr) read via **psicopompo NFS** (`/mnt/storage/data/media/music` = NFS mount). See [`network/nfs.md`](../network/nfs.md).

> **Standardized labels** (06/08): identical on both sides — `default-folder-syncthing`, `music`, `agentic-ai`.
>
> **Kuaray:** the `agentic-ai` folder lives in `/DATA/AppData/agentic-ai/` (**system SSD**, `/dev/sda2`) — outside `/config/Sync` to avoid nesting with the `default` folder.

> **⚠️ Folder `agentic-ai` (critical):** points at the **root of the working folder** (which is the Obsidian vault). Special configuration:
> - The root `.stignore` excludes `.venv/`, caches, backups → they do not sync.
> - **Real mirror + versioning (06/08):** `ignoreDelete=false` (deletions propagate — any device can delete) + **`versioning` `simple`** (keep 5 on psicopompo / keep 3 on kuaray) → deleted files go to the local `.stversions/` instead of vanishing. Protects against a "deletion storm" from a faulty disk.
> - **Lesson 06/08:** without `ignoreDelete`, syncthing propagated deletions from kuaray and wiped files from the old git repo (recovered via `git checkout`). With versioning, deletions become recoverable history.
> - `.obsidian`/`.pandoc` (Obsidian config) sync; `.smart-env`/`.SMART CHATS` (caches) are ignored.

## Ports

| Port | Protocol | Role |
|---|---|---|
| `8384` | TCP | Web interface (Tailscale only) — **bound to `127.0.0.1:8384` + exposed via `tailscale serve --tcp 8384`** (10/08) |
| `22000` | TCP/UDP | Data transfer |
| `21027` | UDP | Local discovery |

## Access

Web interface (tailnet only):
- **psicopompo:** `http://100.82.51.112:8384` (via `tailscale serve`, which proxies TCP → `127.0.0.1:8384`)
- **kuaray:** `http://100.94.209.99:8384`

## History (06/08/2026)

1. **IP fix:** `syncthing@edu` failed on boot — `config.xml` pointed at the old IP. Fixed to `100.82.51.112`.
2. **Reorganization:** Default Folder moved to `/home/edu/Default Folder Syncthing/`; MUSIC to `/mnt/BACKUP/media/music/` (migration in progress); Calibre Ingest deleted.
3. **Obsidian vault:** migrated from `~/Syncthing/Default Folder/OBSIDIAN/Mnemocine` to the **root of agentic-ai** (vault = the whole folder).
4. **Git repos consolidated:** `git [SUMAENIMA-INFRA]` and `git [CURRICULUM-VITAE]` merged into the **single agentic-ai folder** (nested `.git` removed, backup in `.backup-git-nested/`). Folders renamed to `mnemocine/` and `curriculum-vitae/` (06/08). **agentic-ai is no longer a git repo** (07/08) — it is a working folder/vault synced via Syncthing. The original repos stay on GitHub.
5. **Folder id/label:** `obsidian` → **`agentic-ai`** (re-accept on all devices).
6. **kuaray parity:** the `agentic-ai` folder moved from `/config/Sync/obsidian` (nested in default) → **`/DATA/AppData/agentic-ai/`** (SSD, outside default). The leftover `obsidian` junk (3.2G, duplicate copy) removed from psicopompo's Default Folder. **Labels standardized** on both sides. Hidden `.obsidian`/`.pandoc` re-synced.
7. **Encoding:** 3 filenames NFD→NFC (git via `git checkout`); `core.precomposeunicode=true`.
8. **kuaray HDD crisis (06/08):** kuaray's `music` folder threw `Bad message` — the root cause was a **double-mount** of `/dev/sdb` (stale loop0 + loop100, both rw) that corrupted ext4. The `music` folder was **removed** from kuaray (media consolidated on psicopompo). Orphan Ybyra device removed from psicopompo's config. See `servers/kuaray.md`. Detail: on kuaray, `ignoreDelete=true` was also applied to the `agentic-ai` folder.
9. **Music restore (06/08, night):** HDD reformatted (MBR/LBA2048, healthy fs — `mnt-storage.service` removed). The `music` folder (`gtuwj-mspep`) was **recreated** in kuaray's syncthing → `/mnt/storage/data/media/music`. "Add music folder" prompt resolved.
10. **Deletion storm (06/08, night):** recreating kuaray's `music` folder **empty** made kuaray's index report the library as deleted → psicopompo (mirror) started applying deletions. **~18 real files (~465MB) were lost** before the "directory not empty" errors stopped it; restored from `/mnt/HDD_SATA/Music` (original source intact). **Solution applied:** kuaray's `music` folder → **`receiveonly`** (the mirror receives everything but never sends state → a faulty HDD/recreated folder cannot trigger a storm). Applies until kuaray's Lidarr/arr-stack is migrated. `.syncthing.*.tmp` junk (445) removed from HDD_SATA.

## History (07/08/2026) — "everything at 100%"

1. **`agentic-ai` tombstone cleanup:** the `.venv`/`.smart-env` folders (ignored) had deletion tombstones registered by kuaray on 06/08 → local syncthing refused to delete them (they contain ignored files) → **2 errors + 95% completion** on psicopompo (and 95% on the phones). **Solution:** the `agentic-ai` folder was **removed and recreated** (same config) on kuaray and on psicopompo via the API → index re-scanned, tombstones gone. Result: **100% on all devices** (psicopompo, kuaray, Pira-Nuya, Anansi), 0 errors, caches preserved.
2. **kuaray `.stignore` cleanup:** removed git-era refs (`.git/`, `.gitignore`, `.backup-*`) and added security patterns (`.env`, `*.key`, `*.pem`, `*.cert`, `secrets/`) + OS/editor junk.
3. **`.env.template` fix:** in Syncthing "the first matching rule wins" — `!.env.template` has to come **before** `.env.*`. Fixed the order in both `.stignore` files (with an explanatory comment included).
4. **kuaray music — exact mirror ABANDONED:** the disk rescue left ~975 items "receive only changed" (duplicates of the old library) → 92.5% completion. Backup of the 582 real files (19G, later removed — content confirmed duplicated in the source) + `db/override` → partially reverted it, but the recovered disk has **different versions from the source in ~5500 items** → forcing an exact mirror would require downloading **~134 GiB** again. **Decision (07/08):** transfer unviable on the dying disk → the `music` folder was **removed** (see item 5). kuaray = a "glorified" pihole.
5. **New architecture (07/08) — psicopompo = NAS + cold backup via Syncthing:**
   - **`music` folder removed** from syncthing (psicopompo + kuaray). kuaray's HDD cleaned (divergent junk deleted, 864G free).
   - **NFS:** psicopompo exports `/mnt/BACKUP/media/music` and `/media/books` (NFSv4, `all_squash,anonuid=1000`); kuaray mounts it at `/mnt/storage/data/media/music` (the same path as the container binds) → Navidrome/Lidarr read the library from psicopompo **without sync**. See [`network/nfs.md`](../network/nfs.md).
   - **`backup` folder (cold):** the whole of `/mnt/BACKUP` (source, sendreceive) → `/mnt/storage/backup` on kuaray (**receiveonly**, **no versioning** — decision: a simple mirror; the disk is dying + 2 copies already exist on psicopompo). First transfer ~179G in the background; incremental afterwards. The backup's `.stignore` excludes `.syncthing.*.tmp`/junk.
   - **Permission fix (07/08):** kuaray's syncthing daemon runs as **`kuaray` (uid 1000)** (container `linuxserver/syncthing`, PUID=1000) — not as root. The `/mnt/storage/backup` folder (created via `docker exec` as root) prevented writing → **`chown -R kuaray:kuaray /mnt/storage/backup`** (same owner as `/mnt/storage/data`). The transfer then started normally.

## Cluster (09/08/2026)
- **kuaray device ID (new):** `MYBTGZG-W6AMRCA-CRBXOVE-OLBIUCS-4MED42G-LDDYJ7D-6MTMAPI-Y4GV6AO` (old identity `XC3YRZ6-...` lost on 08/08).
- Re-paired on 09/08 via the API: kuaray = **receiveonly** on `backup` (/mnt/storage/backup) and `agentic-ai` (/home/kuaray/agentic-ai).
- psicopompo (master) removed the old device and added the new one.

## History (10/08/2026) — watcher/scan errors resolved

1. **Error on psicopompo — `backup` (source):** watcher + rescan failed on `/mnt/BACKUP/.snapshots` (`permission denied`) — `.snapshots` is the **snapper snapshots subvolume** (`root:root`, `drwxr-x---`). **Solution:** added to `/mnt/BACKUP/.stignore` the `(?d).snapshots` and `(?d).Trash-*/` patterns. Syncthing's ignoring docs confirm: a pattern without `!` (negation) makes both the scan AND the watcher **skip** the directory. After the edit: 0 new errors, `backup` folder in `idle` (152774/152774).
2. **Error on kuaray — `backup` (receiveonly):** "Failed to sync 12 items / directory not empty" — the local `.Trash-1000` (23G, junk from the 06/08 HDD recovery) diverged from the global one (psicopompo's `.Trash-1000` was empty); receiveonly preserves local files → it could not delete. **Solution:** manually removed `/mnt/storage/backup/.Trash-1000` (23G freed) and `/mnt/storage/backup/.snapshots` (leftover) → `backup` folder in `idle`, `needFiles=0`.
3. **`default` folder — consistency:** kuaray did not have `default` connected to psicopompo (it was local-only in `/config/Sync`, inside the config dir — bad practice). Reconnected via the API: path `/home/kuaray/Default` (new volume in the compose), **receiveonly**, psicopompo device added (and vice versa). `ignorePerms=true` aligned with the master. **Label fixed (10/08):** `Default Folder` → `default-folder-syncthing` (same as psicopompo).
4. **`ignorePerms`:** kuaray is now `true` on all 3 folders (default = psicopompo).
5. **Tailscale SSH:** `ssh kuaray` (via Tailscale SSH) asked for the owner's "additional check" (periodic re-verification) — approved by the owner; no config change.
6. **Local additions on kuaray's `backup` (10/08):** the mirror showed 5 "local additions" in `sumaenima-server-kavure/sumaenima_borg/` — 2 `*.sync-conflict-*-KSNJAZU` (conflicts from the sendreceive period) + 3 obsolete versions of the Borg repo (`hints.9`/`index.9`/`integrity.9`; the master is at `.17`). Removed manually (receiveonly folder, no borg running on kuaray) → `local = global` (153030/153030).
7. **`.stignore` on the kuaray mirror (10/08):** created `/mnt/storage/backup/.stignore` with the same patterns as the master (`(?d).snapshots`, `(?d).Trash-*/`, temp, OS junk) — good practice: a receiveonly mirror honors the same ignores. The `receiveOnlyChangedDeletes=1` pending item (the `.snapshots` entry) was resolved with **Revert Local Changes** (`POST /db/revert`) → `receiveOnlyChanged = 0/0/0`.

## History (10/08/2026, night) — GUI boot race + definitive fix

**Symptom:** after the ~15:46 reboot, `syncthing.service` (user) was **dead** (`start-limit-hit`) and the vault no longer synced from psicopompo.

**Root cause:** the GUI was pinned to **`100.82.51.112:8384`** (Tailscale IP). Syncthing came up 4s after tailscaled, before the TS IP was assigned → `bind: cannot assign requested address` → 4 attempts in 60s → `start-limit-hit`. **Same class of bug as 06/08** ("old IP") — hardcoding the bind to a tailnet IP is fragile on boot.

**Fix applied (Option A — localhost + Tailscale Serve):**
1. GUI → **`127.0.0.1:8384`** in `config.xml` (no longer depends on the TS IP at boot).
2. **`tailscale serve --bg --tcp 8384 tcp://127.0.0.1:8384`** → tailscaled (owner of the TS IP) exposes `http://100.82.51.112:8384` on the tailnet; it persists across reboots (the serve state lives in tailscaled).
3. **GUI host check** (`Host check error` 403 when accessing via `100.82.51.112`): in **v2.1.3** the field is a **child element** `<insecureSkipHostcheck>true</insecureSkipHostcheck>` inside `<gui>` (the XML attribute is **ignored**). Set via `POST /rest/system/config` (PUT returns 405).
4. `systemctl --user reset-failed syncthing.service` + start.

**Validation:** restart preserves the setting (runtime `insecureSkipHostcheck=true`), GUI 200 via `100.82.51.112:8384` and via MagicDNS, serve active, `agentic-ai`/`backup`/`default` folders in sync (`need=0`).

> **Lesson:** a service with a "tailnet only" GUI **must not** bind to the TS IP — use `127.0.0.1` + `tailscale serve` (or a firewall). Reboot-safe.

## History (28/08/2026) — HDD did not mount on boot → `backup` folder in error

**Symptom:** kuaray's `backup` folder in the **"folder path missing" error state** (the "stopped" in the GUI).

**Root cause:** after the reboot (kernel 7.0.0-30), the `/dev/sdb1` HDD **did not mount** — `systemd-fsck` failed (dependency) → `mnt-storage.mount` `dead`. The disk degraded beyond what was documented: **`Current_Pending_Sector` 3 → 37**, **new read error at ~464 GB** (sector 973545360, dmesg), and `e2fsck -fn` reported **filesystem errors** (inode 7 / group descriptors, "Illegal block"). The boot fsck hit the bad sectors and aborted the mount. Without the mount, the path `/mnt/storage/backup` did not exist → folder error.

**Side effect:** the music NFS mount (`/mnt/storage/data/media/music`) was **nested under the HDD mountpoint** → it went down too → **Lidarr with no library** (music safe on the NAS, but the local path vanished).

**Resolution (28/08):**
1. `e2fsck -fy /dev/sdb1` — repaired (directories, bitmaps, counters, orphan inodes). It did not hit the bad sector again (~464 GB seems to be outside the used region).
2. `/etc/fstab`: `/mnt/storage` with **`nofail,errors=continue`** (boot does not hang on a sick disk). Backup in `/etc/fstab.bak-20260828`.
3. `mount /mnt/storage` → `backup/` + `data/` mirrors accessible.
4. **`docker restart syncthing`** — the `/mnt/storage:/mnt/storage` bind was created before the HDD mounted and pointed at the SSD's empty folder (same `rprivate` rule as in `nfs.md:69`); without the restart the container did not see the mount.
5. Scan + **`POST /rest/db/revert?folder=backup`** — e2fsck left **2334 "receive only changed" items**; the revert aligned the mirror with the master. `backup` folder → **`idle`, local = global = 155628**.
6. **Music NFS decoupled from the HDD** (see [`network/nfs.md`](../network/nfs.md)): mount moved to `/mnt/nas/media/music`; Lidarr's bind adjusted. The HDD can no longer take the library down.

> **State (28/08):** `agentic-ai` (1482) and `default` (4) folders **idle**; `backup` **idle** (155628/155628). The disk remains degraded (37 pending) — the HDD replacement recommendation stands (`servers/kuaray.md`).

## History (22/09/2026) — unit conflict (06/08 duplication) + 40 errors in the restic repo

**Symptoms:**
1. `syncthing.service` (user) ended the boot at **`start-limit-hit`** ("is another Syncthing instance already running") — the `syncthing@edu.service` (system) won the lock race.
2. `backup` folder with **40 `pullErrors`** per boot: `permission denied` on `/mnt/BACKUP/repos/restic/configs/data/*`.

**Root causes:**
1. **Duplicate units:** the `syncthing@edu` (system) was enabled on **06/08 15:00** (symlink created that day) during the "IP fix" (06/08 history) — alongside the canonical user unit (default preset since 28/05) → a race on every boot. The doc contradicted itself (the Instances section declares the **user** unit as canonical).
2. **restic repo inside the `backup` folder:** the restic timer (05:45) creates packs as **`root:root` mode 400** — syncthing (edu) cannot read them → scan/hash failure (40 errors this boot; 321 via the system instance before disabling it).

**Fix:**
1. `sudo systemctl disable --now syncthing@edu` — removes the 06/08 duplication.
2. `systemctl --user reset-failed syncthing` + `start` — the canonical user unit takes over.
3. `/mnt/BACKUP/.stignore` += **`repos/restic/`** — scan/watcher skip it (same recipe as the 10/08 `(?d).snapshots`; the `.stignore` needs a folder restart/new scan to reload).

**Validation (22/09):** `syncthing.service` (user) **active+enabled**; `syncthing@edu` **disabled**; `backup`/`agentic-ai`/`default` folders **`idle`, `need=0`, `errors=0`**, zero `permission denied` after the fix (control scan at 12:29+).

> **Lessons:** (1) Arch offers both a user unit AND a system template — enabling both = a lock race on every boot; keep only the one declared canonical in the doc. (2) repos with root-only permissions (restic/git) inside a syncthing folder must go into `.stignore` — syncthing should never scan content it cannot read (the `.stignore` is reloaded on folder/service restart, not on a hot scan).
