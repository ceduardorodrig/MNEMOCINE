---
tags: [homelab, service, gpu, psicopompo]
pending: []
---

# hl-infer (GPU Inference Gateway)

Centralized GPU inference gateway: **one daemon owns the GPU** and every consumer asks it for a
VRAM **lease**. Written in Rust, it arbitrates instead of executing — the consumer runs its own
workload once admitted.

**Server:** psicopompo (RTX 5050 8 GB)  
**Port:** `9095`  
**Bind:** `127.0.0.1` + `100.82.51.112` (loopback + tailnet) — **never `0.0.0.0`**
([`ports.md`](../network/ports.md) §4, `SEC-PORT-EXPOSURE`). Containers reach it through the tailnet
IP, allowed by a scoped firewall rule rather than a wide bind:
`ufw allow from 172.16.0.0/12 to any port 9095 proto tcp` (any Docker network) +
`ufw allow 9095/tcp on tailscale0`. The LAN stays denied.
**Source:** [`MNEMOCINE-OPS/provisioning/hl-infer`](https://github.com/ceduardorodrig/MNEMOCINE-OPS) (private)  
**Unit:** `provisioning/systemd/hl-infer.service`  
**Status:** **deployed** on psicopompo (`hl-infer.service`, enabled, port `9095`); consumer migration pending (see [HB-022](../../mnemocine/backlog.md))

## Why

Before this gateway, every GPU consumer carried its own `up/status/down` logic and its own idea of
when VRAM was free — the divergence `ARCH-DRY-DUPLICATION` exists to prevent. The gateway replaces
that with a single, auditable policy.

## Admission model (lease based)

1. A consumer submits a job: `kind` + `required_bytes` (+ an optional label).
2. The gateway measures **free VRAM from the driver at runtime** (never a hardcoded size) and
   subtracts the bytes already **reserved** by admitted jobs.
3. If the job fits and its class is allowed, it becomes `admitted`; otherwise it **waits** — there
   is no CPU fallback ([ADR-020](steniorec.md)). The wait is **centralized**: `POST /v1/jobs?wait_secs=N`
   blocks until admission and answers `202` + `state: queued` if the wait expires, so consumers do
   not each re-implement polling. A consumer that ignores `queued` is doing GPU work unarbitrated —
   the autopilot treats it as an error.
4. The consumer releases the job when it finishes, freeing the reservation. Leases carry a **TTL**
   (default 30 min, `--lease-secs`): a consumer that crashes without releasing has its reservation
   reclaimed automatically, so **dead VRAM is never left reserved**. `POST /v1/jobs/{id}/renew`
   extends a legitimately long job.

The accounting is deliberately **conservative**: a lease is subtracted until it is released, so a
model that is still loading can never be over-admitted.

| Job class | Priority | Fixed windows |
|---|---|---|
| `transcribe` (StênioREC, interactive) | highest | **ignored** — served whenever VRAM allows |
| `triage` / `create` / `image_gen` (batch) | medium | **enforced** |
| `other` | lowest | ignored |

## Fixed windows

Batch classes drain only inside announced windows (configured on the unit), so the machine owner
knows exactly when autonomous work may touch the GPU:

```text
06:00-07:00, 12:00-13:00, 18:00-19:00, 00:00-01:00
```

Outside them the GPU is exclusively the owner's. A job that misses its window **waits for the next
one** rather than behaving unpredictably.

## VRAM measurement

The ledger reads the driver **at runtime** — total/used are never hardcoded. The default source
queries `nvidia-smi --query-gpu=name,memory.total,memory.used`, which keeps the crate buildable on
hosts without the NVIDIA userspace libraries (build node, CI) while reporting real numbers where a
GPU exists. `nvml-wrapper` (the crate StênioREC uses for `ADR-020`) is the alternative source if
strict NVML parity is preferred; the `VramSource` trait isolates the choice.

## Endpoints

| Method | Endpoint | Function |
|---|---|---|
| `GET` | `/v1/health` | Process liveness |
| `GET` | `/v1/ready` | **Semantic readiness** — `503` without a GPU (ADR-020) |
| `GET` | `/v1/vram` | Live total/used/free VRAM |
| `GET` | `/v1/queue` | Queue + reservations + effective free VRAM |
| `POST` | `/v1/jobs` | Submit a job (`kind`, `required_bytes`, `label`); `?wait_secs=N` blocks until admitted |
| `GET` | `/v1/jobs/{id}` | Job state |
| `POST` | `/v1/jobs/{id}/release` | Release a lease |
| `POST` | `/v1/jobs/{id}/renew` | Extend a live lease (long interactive sessions) |
| `GET` | `/v1/gpu/consumers` | GPU processes classified against the leases (drift detection) |
| `GET` | `/metrics` | Prometheus exposition |

## Metrics

`hl_infer_vram_total_bytes`, `hl_infer_vram_used_bytes`, `hl_infer_vram_free_bytes`,
`hl_infer_vram_reserved_bytes`, `hl_infer_vram_effective_free_bytes`, `hl_infer_jobs_pending`,
`hl_infer_jobs_admitted` — all labelled with `device`.

## Verified behaviour (2026-10-12, psicopompo)

Live run against the RTX 5050 (8.55 GB total, 2.4 GB in use by the owner at the time):

| Scenario | Result |
|---|---|
| `create` job outside a window | stays **queued** (waits for 18:00) |
| `transcribe` job outside a window | **admitted** (interactive classes ignore windows) |
| `image_gen` requesting 32 GB | stays **queued** (does not fit) |
| release | reservation drops to 0, effective free recovers |
| release of an unknown id | `404` |
| **resident lease + renew** (the pattern a long-lived consumer such as StênioREC uses) | `transcribe` lease admitted with a TTL, reservation visible in `effective_free_bytes`, `renew` extends it, `release` returns the reservation |
| **centralized wait** | a fitting job answers `201 admitted` in ~24 ms; an oversized job with `?wait_secs=5` blocks ~6 s and answers `202 queued` |

## Enforcement

Three layers keep the GPU centralized — the gateway alone is not enough, because
nothing stops a new service from claiming the device directly:

| Layer | Mechanism |
|---|---|
| **Static** | StenioSentinel rule **`HOMELAB-GPU-UNIFIED`** — a compose service that claims the GPU (`runtime: nvidia`, `gpus:`, `deploy` device reservations or `NVIDIA_VISIBLE_DEVICES`) must be a **registered consumer**; a new claim is flagged (`--explain HOMELAB-GPU-UNIFIED`) |
| **Dynamic** | `GET /v1/gpu/consumers` and the `hl-infer audit` CLI cross-check the driver's compute processes against the leases granted — a process holding VRAM with **no lease** is `unmanaged` (drift). A process holding only a **small idle CUDA context** (`--idle-context-bytes`, default 256 MiB) is `idle_context`: still reported, never counted as drift, so a long-running GPU service can stay up without crying wolf. Loading a **model** costs gigabytes and therefore remains drift unless leased |
| **Reactive** | Prometheus alerts `HlInferUnmanagedConsumer` (drift), `HlInferDown` and `HlInferVramExhausted` |

`hl-infer audit` **exits non-zero when drift is found**, so agents and CI can gate on GPU
centralization instead of relying on good intentions. Desktop/rendering processes (Electron,
browsers, editors, compositors, media players — `mpv`, `stremio`) are classified `desktop` and never
reported as drift. A media player that now renders on the GPU (after its Flatpak NVIDIA GL runtime was
installed) would otherwise have looked like drift the moment playback pushed it past the idle-context
tolerance.

Registered consumers (allowlist): `hl-infer`, `steniorec`/`stenio-server`, `steniobot`, `sae-core`,
`ollama`, `transcribe`, `comfyui`.

## Monitoring

Prometheus (kavure) scrapes `http://100.82.51.112:9095/metrics` through the `hl-infer` job, with
the instance relabelled to `psicopompo`. Alerts live in the `gpu-gateway` group:

| Alert | Condition | Severity |
|---|---|---|
| `HlInferDown` | `up{job="hl-infer"} == 0` for 5m | critical |
| `HlInferVramExhausted` | `hl_infer_vram_effective_free_bytes < 512 MiB` for 15m | warning |

Without the gateway the GPU has no arbiter: jobs would queue without accounting and the fixed
windows guarantee is lost — hence the critical severity.

**Single entry point (by design):** the gateway is the *only* entry to the GPU — if it is
unreachable, GPU work does not happen, for every class. Consumers therefore treat it as a hard
dependency (`HL_INFER_REQUIRED=true`), which is why `HlInferDown` is critical.
See [`../guides/gpu-centralization.md`](../guides/gpu-centralization.md).

**Dashboard:** Grafana **`GPU Gateway (hl-infer)`** (uid `gpu-gateway`) — VRAM free/used/reserved/
effective-free, queue depth, lease churn and the drift stat (red when > 0).

## Deployment

| Step | Command |
|---|---|
| Build + install the binary | `install-homelab-tools.sh --host psicopompo hl-infer` |
| Install the unit | `sudo install -m 0644 provisioning/systemd/hl-infer.service /etc/systemd/system/` |
| Enable | `sudo systemctl daemon-reload && sudo systemctl enable --now hl-infer` |

Deployed **2026-10-12 18:00** (psicopompo): binary from `MNEMOCINE-OPS`, unit enabled at boot.

## Migration (pending)

Fleet inventory (2026-10-12) — only **psicopompo** has a GPU, so this is the whole migration:

| Consumer | Class | VRAM | Action |
|---|---|---|---|
| **StênioREC** (`stenio-server`) | interactive | ~1.6 GB | ✅ **migrated 2026-10-12** — holds a resident lease for the process lifetime (verified live: `state=Admitted`, renewed every 600 s) |
| **Autopilot** (via Ollama) | batch | model-dependent | ✅ **migrated** — the lease wraps the Ollama call; a lease that is not `admitted` is an error |
| **Ollama** (`steniobot_ollama`) | batch | ~2–4.7 GB | ⏳ its callers hold the lease (the autopilot path is done) |
| `transcribe-whisper` | interactive | ~1.6 GB | disposable — functionally covered by StênioREC; retire (HB-027) |
| `steniobot-vision` / `steniobot-audio` | batch | legacy | already removed from `sumaenima-ctl`; retire (HB-027) |
| **ComfyUI** (`comfyui`) | batch | ~84 MiB idle + model | ✅ **deployed 2026-10-12** — started on demand under an `image_gen` lease with the `process: "python"` hint (it holds a CUDA context whenever it runs, so it must be stopped when idle) |

**Redundant lifecycle logic to retire after migration:** the `gpu-supervisor` crate + its
`sumaenima-gpu.service` unit and installer, `sumaenima-ctl gpu up/status/down`, the per-consumer
`OLLAMA_KEEP_ALIVE=0` / `keep_alive: 0` handling and the 180 s idle auto-exit — all of that is what
the gateway now owns. `app/server/src/device.rs` (ADR-020 GPU-presence gate) stays: it is orthogonal
to arbitration.

## See also

- [`steniorec.md`](steniorec.md) — ADR-020 (GPU-only, no CPU fallback) and the `gpu-supervisor`
- [`../network/ports.md`](../network/ports.md) — port registry
- [`../backlog.md`](../backlog.md) — HB-022

## Investigation note — 2026-10-13 (HB-022 / HB-023): `steniobot_ollama` is a phantom

**Question:** the `steniobot_ollama` worker container is defined in the Sumænimá Hub stack, but no
caller was found in the hub's Rust code. Is it a live, unleased GPU consumer to migrate, or a dead
definition?

**Answer: dead definition — the container never runs and nothing calls it.** The live Ollama is a
*host* systemd service, and its two real callers are already accounted for. Details and evidence
(read-only audit):

**1. Definition.** `sumaenima-hub/docker-compose.yml` (`ollama` service, `container_name:
steniobot_ollama`): `ollama/ollama:latest` (digest-pinned), `OLLAMA_KEEP_ALIVE=0`, port
`11434:11434`, volume `/mnt/NVME_PCI/ollama_models:/root/.ollama`, `runtime: nvidia` + `deploy`
device reservation (`capabilities: [gpu]`). It is the only definition left; the current
`provisioning/stacks/gpu.yml` holds **only** `steniorec` (the old `ollama` block survives solely in
`.archive-legacy-gpu-2026-10-12/steniobot-gpu/gpu.yml`).

**2. Live state — not running anywhere.** `docker ps -a` on psicopompo shows no `steniobot_ollama`
and no `ollama` image is even pulled; `docker service ls` / `docker ps -a` on kavure, kuaray and
ybyra show none either. The container is a config artifact, not a service.

**3. No caller exists.**
- **Hub Rust:** `rg -i ollama` over `*.rs` → **zero matches** (no HTTP client to `:11434`, no
  `OLLAMA_HOST` use).
- **n8n:** kavure `n8n` → `SELECT count(*) FROM workflow_entity` = **0**; kuaray `miracena-n8n`
  (`miracena-postgres`, db `n8n`) → **0** workflows. No workflow references `ollama`/`11434`/`9095`.
- **Scripts/units:** the only `11434` hits outside the compose file are the autopilot provider
  registry and the archived `kernel-watchdog` skill doc.
- **`.env`:** `OPENWIKI_PROVIDER=ollama` is dead — OpenWiki lives only under `scripts/archive/` and
  runs nowhere (no container on kavure).

**4. The real Ollama is the host service, not the container.** `ollama.service` on psicopompo
(`/usr/local/bin/ollama serve`, drop-in `OLLAMA_MODELS=/mnt/NVME_PCI/ollama_models/models`, models
`gemma4:e2b`, `qwen3:8b`, `qwen2.5:7b`), listening on **`127.0.0.1:11434`** (no overlay, no host
publish) **plus** a kernel-bound forwarder on `100.82.51.112:11434` (`ollama-tailnet.socket`,
`systemd-socket-proxyd`; since 2026-10-19, HB-076). Its callers:
- **Autopilot** (now `hl-autopilot.timer` **on kavure**): endpoint `http://psicopompo:11434`,
  model `gemma4:e2b`; the call is wrapped by a gateway lease against
  `HL_INFER_URL=http://psicopompo:9095` (`gateway.rs`).
- **OpenCode server** (`opencode serve`, loopback): polls `GET /api/tags` every 30 s. Metadata
  only — it lists installed models and loads none, so it never touches VRAM.

**5. VRAM / drift.** `nvidia-smi` compute apps: only `python` (ComfyUI idle context, 84 MiB),
`helium` (browser) and `electron` (Obsidian) — **no ollama process**. Gateway
`GET /v1/gpu/consumers` → `unmanaged: 0`, `leases: []`; `GET /v1/queue` → `reserved_bytes: 0`,
`effective_free_bytes: 5.8 GB`. The host Ollama holds no VRAM at rest (no model loaded), so there is
**no drift** to flag.

**6. Decision implied.** The `steniobot_ollama` path is **dead**: there is nothing to lease. The
migration step is therefore *removal*, not an env/lease change — delete the `ollama` service from
`docker-compose.yml` (and fix the stale `steniobot_ollama → :11434` claim in
[`../network/service-topology.md`](../network/service-topology.md) and
[`steniobot.md`](steniobot.md)), after which the container is no longer a registered-but-nonexistent
GPU claim and **HB-022 can be closed**. The live host Ollama needs no `OLLAMA_HOST` change: the
autopilot already holds the lease around it, and OpenCode's `/api/tags` polling is metadata-only
(if it ever runs a model it must be leased like any batch consumer).
