---
tags: [homelab, recovery, checklist, backup, psicopompo, tailscale, sops, docker, storage, kuaray, kavure, server]
pending: [HB-065, HB-066, HB-067]
---

# Worst-Case Loss of psicopompo — Dependency Matrix & Gaps

> **Question answered here:** *if psicopompo disappears today* (host destroyed, disk dead,
> stolen, board fried), **what stops, what survives, and how is it recovered — per dependency**?
> This is a **read-only reconnaissance** (2026-10-13) across the vault and the live fleet.
> It complements — it does **not** replace — the unified [disaster recovery manual](disaster-recovery.md).

**Method.** Every claim carries its **source**: a hosting file, a live command, and the host it ran
on. Where the answer could not be established without touching a secret or a powered-off host, the
text says **unknown** and how to find out. **No secret value is printed anywhere** — only paths.

**Scope boundary.** Owner decisions (where a key copy should live, whether to build the fallback)
are flagged as decisions; this document proposes, it does not execute.

---

## 1. The dependency matrix

| # | Dependency | If psicopompo is gone today → **STOPS** | **SURVIVES** | How it is recovered | Evidence |
|---|---|---|---|---|---|
| 1 | **Tailnet access** | Nothing that gates *joining*. A **new** device (or the owner's phone) joins by **account login** at `login.tailscale.com` — the control plane is Tailscale's, not psicopompo's. | The tailnet, its ACL and its tags: the policy lives in the private repo `MNEMOCINE-ACL` (GitOps, `action: apply`) with **console lockout ON**, so GitHub + Tailscale are the source of truth. `tagOwners` are owned by `autogroup:admin`. | Log in on any device; `tailscale up`. Re-tag the rebuilt host if needed (console/API/`tailscale login --advertise-tags`, a **device** action, not an ACL edit). | [`../network/tailscale.md`](../network/tailscale.md) (§ACL GitOps, §Tagging); [`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) §6; [`../guides/security-baseline.md`](../guides/security-baseline.md) §Layer 1 |
| 1a | **`TS_AUTH_KEY`** (edge tunnel only) | The `sae-edge` containerised `tunnel` cannot re-authenticate if it must be redeployed — the key is in the **SOPS store**, which needs the **age key** (see #3). | The **running** tunnel keeps its session until it restarts; **human** devices do not use this key. | Decrypt from SOPS **once the age key is recovered**; or create a **new** tagged auth key in the console. | [`../network/tailscale.md`](../network/tailscale.md) §Edge Funnel Authentication; [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) |
| 2 | **Tailnet administration / device approval** | Nothing. Device approval is **not enabled** (a checklist item, unchecked) — so no approval path is lost; conversely there is no approval gate today. | Admin console, ACL repo, tags — all external to psicopompo. | Manage from any browser / the API token in SOPS (`TS_API_TOKEN`, itself age-encrypted → depends on #3). | [`../guides/security-baseline.md`](../guides/security-baseline.md) §5 (Device approval `[ ]`); [`../guides/tailnet-acl-runbook.md`](../guides/tailnet-acl-runbook.md) |
| 3 | **Secrets (SOPS/age)** | **Everything that needs the age private key.** The store `mnemocine/secrets.enc.env` is ciphertext and survives (Syncthing), but **cannot be decrypted without `~/.config/sops/age/keys.txt`**, which the design keeps **only** on psicopompo. | The ciphertext itself (vault + Syncthing + phones). Deployed per-service `.env` files already on target hosts (kavure/ybytu/ybyra) keep those services running. | **Only with a surviving copy of the age key.** None was verifiable off-host (see §2, Gap 🔴-1). | [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) §Architecture; live verification (§4) |
| 3a | **Plaintext master `secrets.env`** (documented fallback) | The fallback itself — it lives at `/mnt/NVME_PCI/secrets/secrets.env`, **on psicopompo only** (not in `config-backup` sources, not on the NAS). | — | Same as #3: needs an off-host copy that does not exist today. | [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md); live verification (§4) |
| 4 | **Swarm cluster** | **Nothing structural.** kavure is the **sole Manager (Leader)**; psicopompo and ybyra are **workers**. Losing the worker does not lose quorum. | kavure keeps orchestrating; tasks reschedule on the remaining nodes. | `docker node rm Psicopompo` on kavure; rejoin after rebuild. | live `docker node ls` on kavure (§4); [`../servers/kavure.md`](../servers/kavure.md); [`../servers/psicopompo.md`](../servers/psicopompo.md) §Docker Swarm |
| 5 | **Managing the servers** | Nothing. kavure and kuaray are managed over **Tailscale SSH** (`RunSSH: true`), authenticated by tailnet identity. | Full admin path from any member device (kavure = control node; kuaray = standalone Docker, `Swarm: pending`). | `tailscale ssh kavure@kavure` / `tailscale ssh kuaray@kuaray`. | live probes (§4); [`../guides/security-baseline.md`](../guides/security-baseline.md) §3; [`../servers/kuaray.md`](../servers/kuaray.md) |
| 6 | **NFSv4 NAS exports** (media, off-box backup targets) | The mounts on kavure/kuaray (`/mnt/BACKUP/media/music`, `/srv/data/*/offbox`). Their containers keep running, but **media streaming** and **backup writes** fail. | — | **No documented failover.** NFS is psicopompo-only; off-box targets are *on* psicopompo. Recovery = rebuild first (see #11). | [`../network/nfs.md`](../network/nfs.md); [`../servers/psicopompo.md`](../servers/psicopompo.md) §Roles; [`../backups/strategy.md`](../backups/strategy.md) |
| 7 | **Private Docker registry** | New Swarm image pulls are unavailable. Existing images remain **cached on each node**, so running services continue. | Cached images. | Rebuild the registry; or push images from a rebuilt host. | [`../services-catalog.md`](../services-catalog.md) (psychopompo `registry`); [`../guides/docker-registry.md`](../guides/docker-registry.md) |
| 8 | **GPU services** — `hl-infer`, `steniorec`, `comfyui`, `ollama` | All local AI/GPU work: transcription (`steniorec`), image generation, local LLM — **and the autopilot's local fallback** (Ollama behind the `hl-infer` lease). | **The autopilot keeps publishing:** it runs on `kavure` and its normal path is `opencode` (free cloud model); cards are CPU (`rsvg-convert`). The **Ollama fallback** and the VRAM lease are lost, so if `opencode` fails there is no second provider. GPU work itself does not survive. | No host assumes this role. Rebuild or accept downtime. | [`../services-catalog.md`](../services-catalog.md) (psychopompo rows); [`../guides/gpu-centralization.md`](../guides/gpu-centralization.md); [`../services/autopilot.md`](../services/autopilot.md) |
| 9 | **Telemetry** — `node-exporter`, `promtail`, `dockerproxy`, `glances` | psicopompo's metrics/logs stop; the Homepage tile for psicopompo goes stale. | The **monitoring stack itself** (Prometheus/Grafana/Loki) runs on **kavure** and keeps collecting every other host. | Rebuild of psicopompo re-registers the exporters. | [`../services-catalog.md`](../services-catalog.md); [`../services/monitoring.md`](../services/monitoring.md) |
| 10 | **DNS / dashboard** | Nothing — **neither runs on psicopompo.** DNS = Pi-hole + unbound (kavure) and AdGuard (ybytu); dashboard = Homepage (ybytu). | All of it. | n/a | [`../services-catalog.md`](../services-catalog.md); [`../network/dns.md`](../network/dns.md) |
| 11 | **Backup circuit** (config-backup, configs-git-push, restic, etckeeper, agentic-ai-backup, **rclone off-site**, docs-sync) | All timers **originate on psicopompo** → no new backups are produced while it is down. | Everything **already** written: the off-site GDrive mirror, the GitHub repos, the vault mirror on kuaray/phones. | Rebuild psicopompo, remount NAS, run the backup units. | [`../backups/config-backup.md`](../backups/config-backup.md); [`../backups/backup-rituals.md`](../backups/backup-rituals.md); [`../services/rclone.md`](../services/rclone.md) |
| 12 | **Desktop streaming** — `punktfunk-*` | Punktfunk host + console. | — | No host assumes this. | [`../services-catalog.md`](../services-catalog.md) |

---

## 2. Ranked gaps

### 🔴 G1 — The age private key has **no verified off-host copy** — **RESOLVED 2026-10-13 (Rota A + KeePass/ybytu cold copy)**

> **Status 2026-10-13 — RESOLVED (both halves closed).** *(a) Lost-host — closed by **Rota A**:* the
> store now carries **two** age recipients and decrypts with **either** key — psicopompo's *or*
> **kavure's** (2nd recipient `age1u2c35fk…`; private key only on
> `/home/kavure/.config/sops/age/keys.txt`, `0600`, owner `kavure`). **Proven live:** kavure decrypts
> the store with its **own** key **alone** (whole-store sha256 + `TS_AUTH_KEY` hash both match
> psicopompo), and psicopompo still decrypts (no regression). *(b) Off-host cold copy — closed the
> same day:* the private key is an **attachment** in the KeePass entry
> `Mnemocine · SOPS age key (cold)`, and the whole KeePass DB is **mirrored to `ybytu`** (Syncthing
> `receiveonly`, `.stignore` = `!/AlgoAqui.kdbx` + `*` → **only the kdbx**; sha256 identical
> `8d917d10…`; `CNH*`/PDF verified **absent**; listener `100.115.253.109:22000`, tailnet-only).
> **Owner decision recorded:** KeePass entry + a **paper copy of the master password**;
> **no separate passphrase** (KeePass is the lock — a passphrase stored in the same DB adds no
> strength); the legacy `~/Google_Drive/KEEPASS/AlgoAqui.kdbx` (2026-05-26) is an **intentional**
> leftover, not a live target. Recovery now works from `ybytu` + the KeePass **without psicopompo**.
> **Closed as [HB-064](../backlog-archive.md)** · evidence in [`services/syncthing.md](../services/syncthing.md).

**The finding (verifiable, 2026-10-13 — pre-Rota-A).** The SOPS store decrypts **only** with the age
private key. Two copies of key material existed, **both on psicopompo**:

- `~/.config/sops/age/keys.txt` — `0600`, owner `edu`;
- `/mnt/NVME_PCI/secrets/age-keys-backup.txt` — `0600`, `189 B`, same host/disk family.

Both carry the **same public recipient** (`age1fgqzpez…`) and each one `AGE-SECRET-KEY` line
(compared by public key + line count; the secret value was **never** printed). Verified **absent**
from the NAS and from the other nodes: no copy under `/mnt/BACKUP` (the sole matches were the
`agentic-ai/` mirror and a compiled Rust object, by substring), and **none** on kavure or kuaray.

The **plaintext fallback** `secrets.env` is at `/mnt/NVME_PCI/secrets/secrets.env` — also
**psicopompo-only**; it is not in `config-backup`'s sources and is not on the NAS. So the fallback
dies with the host too.

**Why it is #1.** Losing the key permanently loses the ability to decrypt or re-derive the whole
secret store: `TS_AUTH_KEY`, the *arr* API keys, Home Assistant secrets, `RCLONE_GDRIVE_*` (the
off-site credentials!), `GH_PUSH_TOKEN`, `OCI_*`, `N8N_ENCRYPTION_KEY`, and more. Some secrets
survive inside already-deployed `.env` files on the target hosts, but the **master** cannot be
recovered or rotated from ciphertext without the key.

**Documentation contradicted itself** (🔵 G6) — **reconciled 2026-10-13**: [`../backups/strategy.md`](../backups/strategy.md)
lists the off-host cold backup as a **pending** action item, while
[`../backups/backup-rituals.md`](../backups/backup-rituals.md) and
[`disaster-recovery.md`](disaster-recovery.md) used to state it was **already** kept in
"KeePassXC / offline USB media". The truth is **pending** (the key was never placed in KeePass); all
three docs now say so (HB-068).

**The one candidate that *does* survive off-host — unverified.** The KeePass database
`AlgoAqui.kdbx` syncs (Syncthing folder `default`) to kuaray
(`/home/kuaray/Default/AlgoAqui.kdbx`, *receiveonly*) and also exists in Google Drive
(`~/Google_Drive/KEEPASS/AlgoAqui.kdbx`, dated **2026-05-26** — stale). Whether the age key is
**inside** it is **unknown**: the DB is encrypted and was **not** opened. *How to find out:* open it
in KeePassXC on a trusted device and look for an `age`/`SOPS` entry; or export its entry list.

> **Decision (owner).** On 2026-10-13 the owner chose **"Rota A" now**: add the **kavure** age key as a
> second recipient — this kills the *host-lost* risk immediately (see the status box above) — and keep
> the **cold offline copy** as a separate follow-up. The medium (KeePassXC entry, offline USB, paper,
> hardware key/YubiKey) is the owner's decision and the owner's action (this review never copies or
> exposes the key). Once a cold copy exists, the agent's job is to **verify** it decrypts the store and
> to keep the docs in sync.

### 🔴 G2 — There is **no psicopompo rebuild runbook** (the recovery path is implicit)

[`disaster-recovery.md`](disaster-recovery.md) §3 has a **5-step sketch** for total psicopompo loss
(pivot to rclone → rebuild → re-export NFS → restore vault → restore secrets). It is a good start but
is not executable as written:

- it **assumes** the age key comes from KeePassXC (unverified — see G1);
- it restores configs by cloning `github.com/ceduardorodrig/mnemocine` into `/home/{user}/homelab`,
  but the **operational layer** (`/usr/local/bin` scripts + systemd units) lives in
  [`MNEMOCINE-OPS`](https://github.com/ceduardorodrig/MNEMOCINE-OPS) under `provisioning/` and is
  installed by `install-homelab-tools.sh` — the restore of that layer is **not** in §3;
- it never states the **order** to restart the backup circuit (NAS mount → root →
  `config-backup` → `configs-git-push` → restic);
- there is no **verification** step that the rebuilt host is producing backups again.

> **Gap:** a from-zero rebuild runbook (this document is the matrix; the step-by-step rebuild is the
> missing piece).

### 🟡 G3 — The "are the backups safe?" answer depends on a pipeline that **starts on the dead host**

With psicopompo gone, **no new** backups are produced (all timers originate there) and the
**freshness** of the off-site mirror cannot be checked from that host. What genuinely exists
off-box is: the GDrive mirror (`gdrive:BACKUP MNEMOCINE`), the GitHub repos (`mnemocine` configs,
public `MNEMOCINE`, `MNEMOCINE-OPS`, `MNEMOCINE-ACL`), and the vault on kuaray/phones.
Note `etckeeper` bare repos are **NAS-only by design** (never pushed to GitHub) — they survive only
through the GDrive mirror of `/mnt/BACKUP`.

> **Gap:** a single-origin backup orchestrator and an unverifiable "last good off-site" from a dead
> host. *Reveal:* check `/srv/health/rclone-gdrive-last-ok` and `rclone about gdrive:` on any live
> host, or the GDrive folder's newest mtime.

### 🟡 G4 — The NFS NAS has **no failover**

kavure/kuaray mount psicopompo's exports for media and off-box backup targets
([`../network/nfs.md`](../network/nfs.md)). No runbook re-exports those datasets from another host.

> **Gap:** no emergency re-export path.

### 🟡 G5 — The registry + GPU services have **no fallback**

The private registry is the image source for Swarm deploys, and the GPU services are single-host.
Neither has an alternate.

> **Gap:** document the accepted downtime (likely **accepted** — this may be "covered by design").

### 🔵 G6 — Internal contradiction about the age-key cold copy

`strategy.md` (pending) vs `backup-rituals.md` / `disaster-recovery.md` (asserted present). One of
them is wrong; both are "sources of truth" today. Reconcile when the owner decides G1.

### 🔵 G7 — The runbook is needed exactly when the vault is hardest to reach

The recovery docs live **only in the vault** (Syncthing). They should also exist **offline**
(print/export), because the scenario is "the primary host is gone".

---

## 3. What is already covered (do **not** panic here)

- **Tailnet access and administration survive** — account login, external control plane, GitOps ACL,
  tags via the console/API. Device approval is not even enabled, so nothing is gated.
- **The Swarm survives losing the psicopompo worker** — kavure is the sole Manager/Leader; no quorum loss.
- **kavure and kuaray stay manageable** through Tailscale SSH from any member device.
- **The NAS data has an off-site copy** (rclone → Google Drive), and **GitHub** holds the config
  repo, the OPS repo, the ACL and the docs.
- **The Obsidian vault survives** on kuaray (Syncthing, receive-only) and on the phones, plus a
  nightly NAS mirror.
- **DNS, the dashboard and the monitoring stack live elsewhere** (kavure/ybytu) — unaffected.
- **Snapper snapshots** on psicopompo are correctly labelled **not** backups (same physical
  substrate) — no false comfort.

---

## 4. Evidence log (commands run 2026-10-13, read-only)

**On psicopompo** (this workspace is `/mnt/NVME_PCI/agentic-ai`):

```text
fd  -H -g 'keys.txt'    /home/edu/.config/sops           → /home/edu/.config/sops/age/keys.txt
eza -la                 /home/edu/.config/sops/age       → .rw------- keys.txt (0600)
eza -la                 /mnt/NVME_PCI/secrets            → .rw------- age-keys-backup.txt (189 B) + secrets.env (0600)
rg  -o 'age1[a-z0-9]+'  <both key files>                 → age1fgqzpez… (identical public recipient)
rg  -c 'AGE-SECRET-KEY' <both key files>                 → 1 / 1   (value never printed)
fd  -H -g 'secrets.env*' /mnt/BACKUP ; fd -H -g 'age*' /mnt/BACKUP  → no master store, no age key (only agentic-ai/ + a build .o)
dust -d 1               /mnt/BACKUP                      → 315 GiB total (media 188 GiB, repos 48 GiB, configs-homelab 22 GiB, agentic-ai mirror 7.1 GiB)
stat <AlgoAqui.kdbx>    ~/Default Folder Syncthing/…     → 2026-10-12 (live) ; ~/Google_Drive/KEEPASS/… → 2026-05-26 (stale)
```

**On kavure** (`tailscale ssh kavure@kavure`):

```text
docker node ls   → kavure = Leader; Psicopompo (worker, Ready); ybyra (worker, Ready)
find /home /srv /root /etc -iname '*age*key*' -o -iname 'keys.txt' → NONE ;  no ~/sops directory
```

**On kuaray** (`tailscale ssh kuaray@kuaray`):

```text
docker info | grep -i swarm → Swarm: pending (not a Swarm node)
find … '*age*key*'          → NONE
find /home -iname '*.kdbx'  → /home/kuaray/Default/AlgoAqui.kdbx  (the Syncthing receive-only mirror)
```

> **GNU note:** the remote probes used `find`/`grep` because `rg`/`fd` are not installed on
> kavure/kuaray (the sanctioned exception recorded in
> [`../services-catalog.md`](../services-catalog.md) §"How to keep this current").

## 5. Unknown — and how to find out

| Question | Why unknown | How to resolve |
|---|---|---|
| Is the age key **inside** `AlgoAqui.kdbx`? | Encrypted DB; not opened (read-only mandate, and it is a secret) | Owner opens it in KeePassXC and looks for an `age`/`SOPS` entry |
| Are the off-site backups **fresh** today? | The origin host is the one assumed dead | `rclone about gdrive:` + `/srv/health/rclone-gdrive-last-ok` on a live host |
| Is there any personal photo library that lives **only** on psicopompo? | No photo library is documented; the recovered archive is on external media `/mnt/RESGATE/ENTREGA/` | Owner confirms where photos are stored now |

## 6. Backlog items — **applied 2026-10-13** (`HB-064 … HB-068`)

> These rows were filed in [`../backlog.md`](../backlog.md) on 2026-10-13 as **HB-064, HB-065,
> HB-066, HB-067, HB-068**. The first (**HB-064**, the age-key cold copy) and the last (**HB-068**,
> the doc contradiction) are **resolved** and live in [`../backlog-archive.md`](../backlog-archive.md);
> the remaining **HB-065 / HB-066 / HB-067** are still open and are declared in **this** document's
> `pending:` frontmatter. The `Ref` points at this file. The fenced block keeps the
> original proposal text verbatim (the `HB-xxx` placeholders map to the ids above, in order); the
> age-key row (row 1 → **HB-064**) was re-framed at filing time to record that **Rota A closed the
> lost-host risk** and only the **off-host cold copy** remained — which then landed the same day.

```text
| **HB-xxx** | **age private key has no verified off-host copy (worst-case psicopompo loss).** The SOPS store decrypts only with `~/.config/sops/age/keys.txt`; the sole backup `age-keys-backup.txt` sits on the **same host** (`/mnt/NVME_PCI/secrets/`), and the plaintext fallback `secrets.env` is psicopompo-only too. Verified 2026-10-13: no copy on `/mnt/BACKUP`, kavure or kuaray. **Owner decision:** where the cold copy lives (KeePassXC entry + offline USB / paper / hardware key); **agent:** verify `AlgoAqui.kdbx` actually stores the key (it survives on kuaray + Google Drive; contents unverified) and make the two contradicting docs agree. Detail in [`recovery/psicopompo-loss.md`](recovery/psicopompo-loss.md) | [`recovery/psicopompo-loss.md`](recovery/psicopompo-loss.md) | 🔴 | open | 2026-10-13 — worst-case dependency review | — |
| **HB-xxx** | **No from-zero psicopompo rebuild runbook.** [`recovery/disaster-recovery.md`](recovery/disaster-recovery.md) §3 is a 5-step sketch that assumes the age key (see above), never wires in the `MNEMOCINE-OPS` operational layer (`/usr/local/bin` + systemd units, `install-homelab-tools.sh`), gives no order for restarting the backup circuit, and has no post-rebuild verification. **Owner/agent:** write `recovery/psicopompo-rebuild.md` and link it from DR §3 | [`recovery/psicopompo-loss.md`](recovery/psicopompo-loss.md) | 🔴 | open | 2026-10-13 — worst-case dependency review | — |
| **HB-xxx** | **Backup freshness is unverifiable when the origin host dies.** All backup timers originate on psicopompo; the off-site mirror is the only off-box copy of the NAS (GDrive), and `etckeeper` bare repos are NAS-only by design. **Owner/agent:** document (and, if desired, relocate) a second, independent freshness witness for the off-site pipeline (`/srv/health/rclone-gdrive-last-ok`) | [`recovery/psicopompo-loss.md`](recovery/psicopompo-loss.md) | 🟡 | open | 2026-10-13 — worst-case dependency review | — |
| **HB-xxx** | **NFS NAS exports have no failover.** kavure/kuaray mounts (media + off-box backup targets) are psicopompo-only; no emergency re-export runbook exists. **Owner/agent:** decide whether a cold re-export from another host is in scope, or document the accepted downtime | [`recovery/psicopompo-loss.md`](recovery/psicopompo-loss.md) | 🟡 | open | 2026-10-13 — worst-case dependency review | — |
| **HB-xxx** | **Doc contradiction: the age-key cold copy.** [`backups/strategy.md`](backups/strategy.md) lists the off-host cold backup as **pending**; [`backups/backup-rituals.md`](backups/backup-rituals.md) and [`recovery/disaster-recovery.md`](recovery/disaster-recovery.md) assert it is **already** kept in KeePassXC/offline USB. Reconcile in the same change that resolves the 🔴 age-key item | [`recovery/psicopompo-loss.md`](recovery/psicopompo-loss.md) | 🔵 | open | 2026-10-13 — worst-case dependency review | — |
```

## 7. See also

- [`disaster-recovery.md`](disaster-recovery.md) — unified DR manual (this doc feeds its §3)
- [`contingency-swap-nas-sshd.md`](contingency-swap-nas-sshd.md) — NAS **drive** swap (≠ host loss)
- [`../backups/strategy.md`](../backups/strategy.md) · [`../backups/config-backup.md`](../backups/config-backup.md) · [`../backups/backup-rituals.md`](../backups/backup-rituals.md)
- [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) — the SOPS/age store
- [`../servers/psicopompo.md`](../servers/psicopompo.md) · [`../servers/kavure.md`](../servers/kavure.md) · [`../servers/kuaray.md`](../servers/kuaray.md)
- [`../services-catalog.md`](../services-catalog.md) · [`../network/nfs.md`](../network/nfs.md) · [`../network/tailscale.md`](../network/tailscale.md)
