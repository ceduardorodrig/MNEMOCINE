---
tags: [homelab, service, agents, kavure]
pending: [HB-078, HB-114, HB-116]
---

# Social-Media Autopilot (`SOCIAL-MEDIA-AUTOPILOT`)

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

The engine is **CPU-only** in its normal path: the LLM is cloud-first (the `opencode` CLI), the
cards rasterise with `rsvg-convert`, and the local GPU is the fail-safe.

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
| `opencode` **v2.2.5** | kavure `/usr/local/bin` | Upgraded 2026-11-06 (was 2.0.32) from the official standalone tarball (`https://opencode.ai/update/api/latest/cli/opencode/opencode-linux-x64.tar.gz`) so it matches psicopompo's package version. The engine parser (`crates/autopilot-providers/src/complete.rs:81` → `type:"text"`/`part.text`) was re-verified against 2.2.5 on the free model; the event shape is unchanged. **Rollback:** `sudo install -o root -g root -m 0755 /var/backups/opencode-rollback/opencode-v2.0.32-20261106 /usr/local/bin/opencode` (sha256 `727027334c61a8e52d23abb5a7dc368a42fd50b0dde44e2315b4e028b74cfe61`), then kill the `opencode serve --service` daemon so it respawns. **No credential may live on kavure:** `~/.local/share/opencode/auth.json` is intentionally absent and no unit/config depends on `opencode-go/*` — the keyed Go models are reserved for psicopompo (owner decision). **No credential is needed** for `opencode/mimo-v2.6-flash-free` (verified 2026-11-06 with auth.json absent). |
| Gemini | cloud | **Removed from the registry on 2026-11-06** (owner decision: no top-up). It answered `HTTP 402` — prepayment credits depleted — since 2026-10-19, so it never contributed a single call; keeping it in the chain only cost a 15 s timeout per failed run. `GEMINI_API_KEY` remains in the SOPS store but nothing consumes it. |
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
- `AUTOPILOT_SECRETS="BLUESKY_APP_PASSWORD"` — the variable **names** the wrapper
  loads from SOPS. The pack names its own per-channel variables; list every one a tenant uses.

## Alerting (2026-11-06)

Until 2026-11-06 a failed run existed **only** in the journal. The four units are timer-triggered
oneshots, so a failure leaves one `failed` row that nobody reads; between 2026-11-04 06:19 and
2026-11-06 18:32 the pipeline published nothing for **60 h** — every window died at `triage` or
`grounding` with "every provider failed" (Gemini 402, opencode exit 1, Ollama refused) — and no human
was told. Two independent signals now close that gap, both delivering through the one transport
`/usr/local/bin/hl-autopilot-notify` to the fleet ntfy topic `/alerts`:

- **`OnFailure=hl-autopilot-alert@%n.service`** on all four units, added as the drop-in
  `/etc/systemd/system/<unit>.service.d/20-alert.conf` (the unit files stay untouched). The instance
  unit runs `/usr/local/bin/hl-autopilot-alert <unit>`, which scans the journals written in the last
  4 h and names the failing **persona and stage** in the message; when the failure happened before any
  journal record (build, secret, missing binary) it says so instead of inventing a stage.
- **`hl-autopilot-watchdog.service` + `.timer`** — every 3 h at `hh:40`, `Persistent=true`, because
  `OnFailure=` is blind to silence. It reads the newest `"status":"published"` record across every
  journal and alerts when the last publication is older than **36 h**, or when the newest journal of an
  active persona carries a `"status":"error"` inside **7 h** that no later publication superseded.
  `status: skipped` + `stage: run` is normal (a slot is an opportunity) and never alerts. Exit codes:
  **0** healthy — or the same state already alerted inside the 12 h cooldown, so an outage pages twice
  a day, not eight times; **2** alert delivered (`SuccessExitStatus=2`, so a delivered alert is not a
  failed unit); **1** the channel refused — the only failed state, and it means ntfy itself is down.

**By hand, both ways.** Healthy: `sudo systemctl start hl-autopilot-watchdog.service` → exit 0, one
journal line with the real last-publication timestamp, no message. Failure: never fake data in
`var/runs`; point the script at an empty directory —
`sudo env AUTOPILOT_TENANT_DIR=$(mktemp -d) STATE_DIR=$(mktemp -d) NTFY_URL=http://127.0.0.1:8083/alerts /usr/local/bin/hl-autopilot-watchdog; echo $?`
→ exit 2 and one message. To read the payload without paging the owner, run a one-file
`http.server` stub on `127.0.0.1:18083` that logs the POST body and returns 200, and pass
`NTFY_URL=http://127.0.0.1:18083/alerts`.

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
`SUMAENIMA-SOCIALMEDIA-AUTOPILOT` (and to `SOCIAL-MEDIA-AUTOPILOT` on 2026-10-22, to remove the
agency prefix: the engine is tenant-neutral, and the Sumænimá deployment is its first tenant), and
its description/topics were set. The pre-rewrite bundle is
`/mnt/BACKUP/sumaenima-socialmedia-autopilot-pre-public-2026-10-21.bundle` (verified). All commit
hashes changed and the vault references were remapped. The 18:15 run published on the tenant
(card + Bluesky post); the repository was flipped **public** on 2026-10-21 with branch protection,
secret scanning/push protection, vulnerability reporting and the **v0.1.0** release. The social
preview is the only manual step left.

## Known gaps

- **The alert path has no dead-man's switch (2026-11-06):** both signals deliver through ntfy on
  **ybytu**, which was offline during this work (tailnet `offline, last seen 6h`; port 8083 timing out
  from kavure, HTTP `000`). An alert raised in that window is printed to the journal and the watchdog
  exits **1** (visible as a failed unit), but it reaches nobody. Existing queue items: **GB-166**
  (one command to classify host-down vs tailnet vs service) and **R7** of the Miracena observability
  audit (external heartbeat for the ntfy/Alertmanager chain).
- **Short video** needs `ffmpeg` **and** `piper-tts` (with a voice `.onnx`). Neither is installed on
  kavure; the format is off in the persona policy, so text and card posts are unaffected. **Planned in
  the owner's roadmap** — tracked as **HB-078**; install them when the format is actually enabled, not
  before.
- **The old `var/` on psicopompo was removed on 2026-10-19** (owner decision, after the checksummed
  copy). The state lives on kavure **and** in the NAS mirror; a rollback copies it back from either.
- **The chain is two providers, not three** (2026-11-06): `opencode` free model first, local Ollama as
  the only fail-safe. Gemini was removed — it had answered 402 since 2026-10-19. That is why the
  Ollama forwarder exists and why its boot survival is a dependency, not a nicety.

## Free-tier economics — what the chain costs, and the standing decision

**Decision (owner, 2026-11-06): the autopilot must NOT consume the paid OpenCode Go quota.** The
`OPENCODE_GO_API_KEY` is reserved for Hermes and the interactive OpenCode harness on psicopompo. The
engine therefore stays on `opencode/mimo-v2.6-flash-free` with the local Ollama as fail-safe — the
free tier plus the home GPU, and zero paid quota spent on autonomous publishing.

**Why the free model started failing (it was never removed).** OpenCode changed the Zen free regime
on **2026-10-23**: the free allowance is a bucket keyed `ip:<address>:<UTC-date>` (community-reported
~200 requests/IP/day; OpenCode publishes no number — `anomalyco/opencode#57540`, `#60991`), and an
exhausted bucket answers `HTTP 429 FreeUsageLimitError` with a retry countdown measured in hours. A
separate `403 FreeTierError` ("the free tier can only be used from within OpenCode") fires when
something other than the client makes the call — which is why the engine must keep shelling out to
the `opencode` CLI instead of calling an endpoint itself.

**Our egress is a shared, rotating CGNAT pool — measured 2026-11-06.** Both hosts leave through one
ZTE CPE (`192.168.3.1`), yet 20 rapid flows from a single host used **four** public IPv4s
(`179.48.47.48/49/50/53`, AS271114 Global Link, Brasília) and the address changes **per flow**. No
hop is in `100.64.0.0/10` — the translation happens upstream of the CPE (the CPE's own WAN is
login-gated, so CGNAT is established behaviourally, not from the router). Consequence, and the
decisive evidence that this is **not our own consumption**: 8 of the 18 pre-contamination 429s fired
on the **first model call of the UTC day**, with zero completed stages before them (e.g.
`2026-10-27T09:15:10Z`, `2026-11-05T09:15:29Z`), and the same model succeeded twice and then refused
2 s later. A bucket only we drain cannot be empty at call #0, nor refill and empty within seconds.
Our daily use is 4–5 stages (126 over 26 days), single-digit percent of the reported cap.

**An owner-controlled egress was tested and did not help yet.** Proxying the call through ybytu
(`64.181.168.251`) and ybyra (`136.248.95.139`) — the Oracle edge nodes — returned *"Free usage
limit reached"* on both, with zero usage from those addresses. That is either a burned bucket or
datacenter IPs being ineligible; the message is identical and the client does not surface the status,
so a single call after the UTC reset is the test that decides it. Until then, an exit node or CONNECT
proxy buys nothing. Also measured: the request is made by the **shared `opencode serve` daemon** (user
`kavure`, PPID 1), not by the CLI process, so a unit-level `HTTPS_PROXY` is inert — it only works with
`opencode run --standalone` (verified: 7 × `CONNECT opencode.ai:443` through a logging proxy, then a
clean transport reset), and the CLI cannot speak SOCKS at all (`UnsupportedProxyProtocol`).

**What one publication consumes** (engine's own instrumentation, `autopilot quota check`, which reads
the CLI's ledger — free tier, so `cost (usd) = 0.0000`):

| Window | steps | input | output | reasoning | cache read | **total** |
|---|---|---|---|---|---|---|
| today (`--days 0`) | 97 | 68 672 | 14 687 | 28 907 | 441 728 | **553 994** |
| last 7 days (`--days 7`) | 178 | 196 032 | 25 644 | 66 857 | 802 944 | **1 091 477** |

A persona run makes **4–8 provider calls** (triage → create → editor A → editor B → grounding), and
**any** single 429 kills the run — which is why one exhausted bucket looks like a dead bot. The
numbers above include the 2026-11-06 diagnostic probes, so they are an upper bound, not a baseline.
Two operational consequences: (1) the free bucket is small enough that a day of normal operation plus
a debugging session exhausts it; (2) the run must degrade to Ollama rather than die, or a quota
hiccup becomes a silent outage — that is **HB-116** (the provider discards the 429 into `exit status:
1`) and the reason the watchdog exists.

- The `ollama-tailnet.socket` / `.service` units and the `10-models.conf` drop-in are **golden files**
  in psicopompo's `config-backup` (`/mnt/BACKUP/configs-homelab/psicopompo/golden/…`), so a rebuilt
  psicopompo recovers the forwarder along with the rest of its configuration.

## Incident 2026-11-04 → 11-06 — 60 h without a publication (HB-114)

**What happened.** The last publication before the incident was **2026-11-04 06:19 -03**
(`var/runs/tech-curiosities-1793783703.jsonl` → `status: published`). The next five scheduled
windows — 04/11 18:15, 05/11 06:15 and 18:15, 06/11 06:15 and 18:15 — all failed at `triage` or
`grounding`. Publication resumed at **2026-11-06 18:32 -03** (manual run, `Result=success`,
verified on the account: `bsky.app/profile/fossfables.bsky.social/post/3mzodh5id6j2d`), i.e. the
scheduler was healthy the whole time and the inference chain was not.

**The kill chain is a sum, not a cause.** Three independent defects overlapped:

1. `opencode` (the primary, free model) answers **`HTTP 429 FreeUsageLimitError`** under load. This
   is chronic, not a regression: 1–4 incidents/day from 10-25 to 11-04, then worse. The Rust provider
   discarded stdout on a non-zero exit (`crates/autopilot-providers/src/complete.rs`), so the journal
   recorded `opencode exited with exit status: 1:` with an **empty** detail — a quota cap was
   indistinguishable from a crash. It is a short rolling window, not a daily bucket: measured
   recovery in 4.5 min and 12 consecutive calls passing afterwards, so a retry would have cost
   minutes, not days (HB-116).
2. `gemini` — **HTTP 402**, prepayment credits depleted. It had contributed nothing since 2026-10-19;
   the owner decided on 2026-11-06 to drop it from the registry rather than top up, so the chain is now
   `opencode` → local Ollama and the 15 s of dead timeout per failed run is gone.
3. `ollama` (the only fail-safe) — **connection refused**, because `ollama-tailnet.socket` never
   started after psicopompo's reboot at **2026-11-03 15:30** (systemd ordering cycle, see
   [`../servers/psicopompo.md`](../servers/psicopompo.md)). This is what turned a rate limit into an
   outage: from that moment there was no third provider to fall back to.

**Why nobody knew for 60 h.** A timer-triggered oneshot that fails only sets `failed` in
`systemctl --failed`, which nobody watches; and a run that legitimately publishes nothing — the
draft personas are skipped by design, and "a slot is an opportunity, not an obligation" — exits 0,
so *absence of a post* is indistinguishable from *a healthy quiet window* unless someone reads the
journals. There was no alert on either failure mode.

**Fixed the same day.** Forwarder repaired at the source (`FreeBind=yes`, ordering directives
removed) and the golden file updated; the chain now degrades to the local GPU instead of dying;
`OnFailure=` on all four stage units and `hl-autopilot-watchdog` (36 h silence / unrecovered
last-window error, 3 h cadence) make both failure modes audible — see §Alerting above. The provider
defect is fixed too: commit `aadb999` reads the CLI's error event, classifies the failure
(`quota` / `auth` / `server` / `crash`), retries a 5xx once after a bounded 250 ms backoff and
advances immediately on quota or auth — so the journal now says
`opencode: quota limit — kind=opencode, HTTP 429, error type 'provider.quota': Free usage limit reached … [quota: advanced immediately, no retry]`
instead of an empty `exit status: 1`. Deployed to kavure and rebuilt there on 2026-11-06 19:04
(`cargo build --release --locked`, 421 tests green, clippy `-D warnings` clean).

**Still open.** The alert path has no dead-man's switch of its
own (ybytu was offline for ~6 h during this investigation, HTTP 000 — GB-166/R7); and the free tier
remains the primary, so a saturated bucket is still a quality-of-service risk that only the fallback
absorbs.

## See also

- [`../servers/kavure.md`](../servers/kavure.md) — the production host
- [`../servers/psicopompo.md`](../servers/psicopompo.md) — dev/build host and GPU fallback
- [`../services/hl-infer.md`](hl-infer.md) — the VRAM lease the fallback takes
- [`../../agents/sumaenima-socialmedia-autopilot/manifest.md`](../../agents/sumaenima-socialmedia-autopilot/manifest.md) — the agent contract