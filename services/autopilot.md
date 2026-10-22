---
tags: [homelab, service, agents, kavure]
pending: [HB-078]
---

# Social-Media Autopilot (`SUMAENIMA-SOCIALMEDIA-AUTOPILOT`)

**Role:** the autonomous social-media engine — harvest → triage → create → guardrail → publish →
metrics → learn, plus a separate engagement stage (reply / like / follow at a human pace).
**Runtime:** native systemd timers (`Type=oneshot`) — **not** a container.
**Production host:** `kavure` (24/7, no GPU) — cut over 2026-10-19.
**Development host:** `psicopompo` — source of truth for the code and the only GPU host.

## Why kavure

`psicopompo` is a Hyprland workstation: it reboots, suspends, and takes kernel updates. A publication
window that lands while the desktop is off is **lost**, because every timer is `Persistent=false` and
the pipeline's invariant is *periodicity over volume* — a missed window is never replayed with a
burst. `kavure` is always on.

The engine is **CPU-only** in its normal path: the LLM is cloud-first (the `opencode` CLI, then
Gemini), the cards rasterise with `rsvg-convert`, and the GPU is only the third fallback.

## Tenant model (2026-10-21, HB-079)

The engine is **code**; the **tenant** owns the persona packs, the account identities, the engage
config and the state. On kavure the tenant is `/home/kavure/autopilot/tenants/sumaenima/`
(`personas/`, `config/`, `var/`), owned by `kavure` (`0700`). The wrapper `cd`s into
`$AUTOPILOT_TENANT_DIR`; the engine stays in `/home/kavure/homelab/sumaenima-socialmedia-autopilot`
and is built there.

- **Identity** is the pack's `channel.handle`. The login uses it, and the publisher rejects a
  session that belongs to another account (`create_session_for_channel`).
- **Secrets are names**: the pack declares `app_password_env` (Bluesky) and `x_env` (X); the unit's
  `AUTOPILOT_SECRETS` lists the variables the wrapper loads from SOPS. No handle or secret is global,
  so two personas in one process can use different accounts.
- **Per-persona engage**: `config/engage/<slug>.yaml` when present, else `config/engage.yaml`.
- The public engine ships `examples/` only; the real pack and the tenant state are not published.

## Timers

| Timer | Fires (`America/Sao_Paulo`) | Stage |
|---|---|---|
`hl-autopilot.timer` | 00:15 · 06:15 · 12:15 · 18:15 | publish (`run`) |
`hl-autopilot-engage.timer` | 09:35 · 13:35 · 20:35 | engage (own windows, caps) |
`hl-autopilot-metrics.timer` | 06:45 | 24 h / 48 h samples |
`hl-autopilot-learn.timer` | 12:45 | memory **proposal** only |

All four are `Persistent=false`: a missed window is not replayed.

## Dependencies (verified 2026-10-19)

| Dependency | Where | Detail |
|---|---|---|
| `opencode` **v2.0.32** | kavure `/usr/local/bin` | **the same binary** as psicopompo (needs only glibc 2.17). The parser expects the v2 event shape (`type:"text"`, `part.text`); the v1 install script would break it. **No credential is needed** for `opencode/mimo-v2.6-flash-free` — the probe and a real call succeed with no `auth.json` (verified 2026-10-19); the file is only needed for a paid model. |
| Gemini | cloud | `GEMINI_API_KEY` from the SOPS store. **Currently unusable: HTTP 402** — prepayment credits depleted (verified 2026-10-19). |
| Ollama | psicopompo `127.0.0.1:11434` | reached as `http://psicopompo:11434` through `ollama-tailnet` (kernel-bound forwarder). Ollama itself never leaves loopback. |
| `hl-infer` | psicopompo `:9095` | `HL_INFER_URL=http://psicopompo:9095`; the VRAM lease is still taken on the GPU host. |
| SearXNG | kavure `:8080` | the harvest endpoint (already on kavure — the engine was already coupled to it). |
| `rsvg-convert` 2.58 + `fontconfig` | kavure | `librsvg2-bin`, `fonts-dejavu-core`, `fonts-liberation`. |
| SOPS store | kavure `~/.config/mnemocine/secrets.enc.env` | **encrypted** mirror of the vault store; kavure's own age key decrypts it (`/usr/local/bin/sops-decrypt`). |

## State (`var/`)

The live state is the **tenant's** `var/` — 175 files at the migration, < 1 MB: `runs/` (the run
journal), `metrics.jsonl`, `engage/state.jsonl` (the **daily caps**), `learn/*.json` (memory
proposals), `cards/`. It is gitignored and must be **single-writer**: only one host may run the
timers at a time. The old `var/` in the engine directory is frozen for rollback.

## Backups

`hl-config-backup` (05:00) mirrors `/srv/data`, the engine repo **and the tenant**
(`/home/kavure/autopilot/tenants/sumaenima`) to `/srv/backup-configs/kavure/…` on the NAS, excluding
`target/`. The tenant mirror has **185 files** (personas + config + `var/`); the engine mirror keeps
the source. The unit files and the `10-kavure.conf` drop-ins — now with
`AUTOPILOT_TENANT_DIR`/`AUTOPILOT_SECRETS` — are **golden files**, and `/etc/config-backup.conf`
backs itself up, so a rebuilt host recovers the rule too.

## Deploy

Two independent artifacts — the **engine** (code) and the **tenant** (private packs/config/state):

```bash
# engine: source only; the tenant directories are never touched
rsync -aHAX --checksum --delete \
  --exclude .git/ --exclude target/ --exclude var/ --exclude personas/ --exclude config/ \
  ./ kavure@kavure:/tmp/autopilot-src/
ssh kavure@kavure 'sudo rsync -aHAX --checksum --delete \
  --exclude personas/ --exclude config/ --exclude var/ --exclude target/ \
  /tmp/autopilot-src/ /home/kavure/homelab/sumaenima-socialmedia-autopilot/'

# build on the destination
ssh kavure@kavure 'cd ~/homelab/sumaenima-socialmedia-autopilot && cargo build --release --locked'
```

Building **on the destination** keeps the binary inside the host's glibc (kavure 2.39). A binary
built on psicopompo (glibc 2.44) can silently start requiring a symbol the destination does not have.
The tenant lives on kavure (`/home/kavure/autopilot/tenants/sumaenima/`); it is deployed and backed
up as its own directory, never as part of the engine.

## Unit notes

- `TimeoutStartSec=30min` — `Type=oneshot` has **no** start timeout by default
  ([`systemd.service(5)`](https://www.freedesktop.org/software/systemd/man/systemd.service.html)); a
  hung provider subprocess would block every later window.
- `UMask=0077` keeps the journal owner-only.
- Host-specific values live in `/etc/systemd/system/hl-autopilot*.service.d/10-kavure.conf`
  (`User=kavure`, `AUTOPILOT_DIR`, `SOPS_DECRYPT`, `HL_INFER_URL`); the unit files stay identical to
  the psicopompo ones (config-as-code, no fork).
- `AUTOPILOT_TENANT_DIR=/home/kavure/autopilot/tenants/sumaenima` — the wrapper `cd`s there, so
  `var/` and the relative defaults are tenant-scoped.
- `AUTOPILOT_SECRETS="BLUESKY_APP_PASSWORD GEMINI_API_KEY"` — the variable **names** the wrapper
  loads from SOPS. The pack names its own per-channel variables; list every one a tenant uses.

## Migration record (2026-10-19)

The engine moved from `psicopompo` to `kavure` without changing the pipeline, the persona packs or
the schedule. The cutover was a **write freeze**: disable the four psicopompo timers → verify no run
is active → final `rsync -aHAX --numeric-ids --checksum` of `var/` → verify a second dry run is empty
→ enable the four kavure timers. Rollback is the reverse, and it must copy the **current** `var/`
back (not an older snapshot), or the engage caps and the metrics journal regress.

**First scheduled execution on kavure (18:15, 2026-10-19):** `Result=success`, exit 0. The three
drafts were gated (`active: false`) and the active persona by its **daily ceiling** (`bluesky 1/1`) —
the engine's intended *"a slot is an opportunity, not an obligation"*, not a failure. The first real
publication is the next eligible window: **06:15 on 2026-10-20** (the persona's windows are 06:00 and
18:00; the 00:15 and 12:15 timers fire outside them and are clean no-ops).

Two facts, **by design**, are recorded in [`../network/ports.md`](../network/ports.md): the tailnet
ACL — not UFW — is the filter (Tailscale's `ts-input` accepts `tailscale0` before UFW), and Ollama is
reachable by **tagged servers**, not by family devices. The owner confirmed the model on 2026-10-19:
it is the same trust boundary the fleet already uses for Syncthing, NFS and the monitoring exporters.

## Tenant migration record (2026-10-21, HB-079)

- Froze the four timers and waited for the running engage to finish (`13:45:53`).
- Created `/home/kavure/autopilot/tenants/sumaenima/` (`0700`, `kavure:kavure`) and copied
  `personas/`, `config/` and `var/` with `rsync -aHAX --numeric-ids --checksum`.
- **175/175** `var/` files hash-identical; 6 persona files, 3 configs.
- Synced the engine source (excluding `personas/`, `config/`, `var/`, `target/`) and rebuilt on
  kavure (`cargo build --release --locked`, 49 s).
- Installed the tenant-aware wrapper and added `AUTOPILOT_TENANT_DIR` + `AUTOPILOT_SECRETS` to the
  four drop-ins (backup: `10-kavure.conf.bak-20261021`; `daemon-reload`).
- Dry run from the tenant: the full pipeline described, no network, no publish.
- `publish auth --persona` against the real pack: authenticated and the DID returned (the handle was
  redacted in the output); the session-handle check passed.
- `config-backup` run live: exit 0, ntfy OK, tenant mirror **185 files**.
- Re-enabled the four timers; next run 18:15.
- **Rollback:** restore the four `10-kavure.conf.bak-20261021` files, `daemon-reload`; the wrapper
  falls back to `$REPO` and the frozen `var/` in the engine directory.

**Public-release note.** The handle appeared in the **public** `MNEMOCINE` `backlog-archive.md`
(HB-073, pre-existing). The autopilot public repository does **not** include it: the real pack lives
in the tenant, the public tree ships `examples/`, and the history was sanitized before the flip. The
`MNEMOCINE` history was sanitized on 2026-10-21 (`git filter-repo`; pre-rewrite bundle
`/mnt/BACKUP/mnemocine-pre-sanitize-2026-10-21.bundle`).

**Public-release prep (2026-10-21).** The real packs were removed from the tree and from all
history with `git filter-repo` (`--path personas/ --invert-paths` +
`--replace-text`/`--replace-message`); the repository was renamed to
`sumaenima-socialmedia-autopilot`, and its description/topics were set. The pre-rewrite bundle is
`/mnt/BACKUP/sumaenima-socialmedia-autopilot-pre-public-2026-10-21.bundle` (verified). All commit
hashes changed and the vault references were remapped. The 18:15 run published on the tenant
(card + Bluesky post); the repository was flipped **public** on 2026-10-21 with branch protection,
secret scanning/push protection, vulnerability reporting and the **v0.1.0** release. The social
preview is the only manual step left.

## Known gaps

- **Short video** needs `ffmpeg` **and** `piper-tts` (with a voice `.onnx`). Neither is installed on
  kavure; the format is off in the persona policy, so text and card posts are unaffected. **Planned in
  the owner's roadmap** — tracked as **HB-078**; install them when the format is actually enabled, not
  before.
- **The old `var/` on psicopompo was removed on 2026-10-19** (owner decision, after the checksummed
  copy). The state lives on kavure **and** in the NAS mirror; a rollback copies it back from either.
- **Gemini is at 402**, so the **only** working fallbacks are `opencode` (free model) and the local
  Ollama. That is why the Ollama forwarder exists.
- The `ollama-tailnet.socket` / `.service` units and the `10-models.conf` drop-in are **golden files**
  in psicopompo's `config-backup` (`/mnt/BACKUP/configs-homelab/psicopompo/golden/…`), so a rebuilt
  psicopompo recovers the forwarder along with the rest of its configuration.

## See also

- [`../servers/kavure.md`](../servers/kavure.md) — the production host
- [`../servers/psicopompo.md`](../servers/psicopompo.md) — dev/build host and GPU fallback
- [`../services/hl-infer.md`](hl-infer.md) — the VRAM lease the fallback takes
- [`../../agents/sumaenima-socialmedia-autopilot/manifest.md`](../../agents/sumaenima-socialmedia-autopilot/manifest.md) — the agent contract
