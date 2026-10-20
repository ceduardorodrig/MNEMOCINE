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

141 files, < 1 MB: `runs/` (the run journal), `metrics.jsonl`, `engage/state.jsonl` (the **daily
caps**), `learn/*.json` (memory proposals), `cards/`. It is gitignored and must be **single-writer**:
only one host may run the timers at a time.

## Backups

`hl-config-backup` (05:00) mirrors the whole repo — source, personas, config **and** `var/` — to
`/srv/backup-configs/kavure/sumaenima-socialmedia-autopilot/` on the NAS, excluding `target/`
(2.6 MB in total). The unit files and the `10-kavure.conf` drop-ins are **golden files** in the same
backup, and `/etc/config-backup.conf` now backs itself up, so a rebuilt host recovers the rule too.

## Deploy

From psicopompo (dev) to kavure (prod):

```bash
git archive --format=tar.gz HEAD | ssh kavure@kavure 'tar -xzf - -C ~/homelab/sumaenima-socialmedia-autopilot'
ssh kavure@kavure 'cd ~/homelab/sumaenima-socialmedia-autopilot && ~/.cargo/bin/cargo build --release --locked'
```

Building **on the destination** keeps the binary inside the host's glibc (kavure 2.39). A binary
built on psicopompo (glibc 2.44) can silently start requiring a symbol the destination does not have.

## Unit notes

- `TimeoutStartSec=30min` — `Type=oneshot` has **no** start timeout by default
  ([`systemd.service(5)`](https://www.freedesktop.org/software/systemd/man/systemd.service.html)); a
  hung provider subprocess would block every later window.
- `UMask=0077` keeps the journal owner-only.
- Host-specific values live in `/etc/systemd/system/hl-autopilot*.service.d/10-kavure.conf`
  (`User=kavure`, `AUTOPILOT_DIR`, `SOPS_DECRYPT`, `HL_INFER_URL`); the unit files stay identical to
  the psicopompo ones (config-as-code, no fork).

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
