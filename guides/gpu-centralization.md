---
tags: [homelab, guides, gpu, rust, psicopompo]
pending: [HB-022]
---

# GPU Centralization — Runbook

How the homelab shares its single GPU (RTX 5050, psicopompo). The device is scarce, so **one
daemon owns it** and everything else asks it for a lease.

**Gateway:** [`hl-infer`](../services/hl-infer.md) · `http://100.82.51.112:9095` (tailnet) and
`http://127.0.0.1:9095` (loopback) · unit `hl-infer.service`.

## The rule

**No workload touches the GPU without a lease.** There is no CPU fallback (ADR-020): a job that
does not fit **waits**.

## Requesting a lease

```bash
# 1. ask (kind: transcribe | triage | create | image_gen | other)
#    wait_secs makes the gateway BLOCK until admission (the wait policy is central)
curl -s -X POST 'http://127.0.0.1:9095/v1/jobs?wait_secs=600' \
  -H 'content-type: application/json' \
  -d '{"kind":"transcribe","required_bytes":1900000000,"label":"steniorec"}'
# → 201 {"id":"job-000001",...,"state":"admitted","expires_at_unix":...}
# → 202 {"...","state":"queued"}  when the wait expires (no VRAM, or window closed)

# 2. while working (resident models): renew before the TTL elapses
curl -s -X POST http://127.0.0.1:9095/v1/jobs/job-000001/renew

# 3. always release when done
curl -s -X POST http://127.0.0.1:9095/v1/jobs/job-000001/release
```

> **Never treat `202 queued` as a green light.** Proceeding means using the GPU without a lease —
> the exact drift the audit and the alert exist to catch. Wait, retry, or fail loudly.

| Kind | Behaviour |
|---|---|
| `transcribe` | interactive — served whenever VRAM fits, **ignores the fixed windows** |
| `triage` / `create` / `image_gen` | batch — only drains **inside** the announced windows |
| `other` | lowest priority, ignores windows |

`required_bytes` is what the job **declares** it needs; the gateway measures the device itself and
subtracts the leases already granted. Declaring too little is how you over-commit the GPU — be
honest, and prefer a small safety margin.

## Fixed windows

Batch classes only run inside `06:00-07:00, 12:00-13:00, 18:00-19:00, 00:00-01:00` (configured on
the unit). Outside them the GPU belongs to the machine owner. A job that misses its window **waits
for the next one** — it is never rushed.

## Debugging: who is using the GPU?

```bash
hl-infer audit                      # human-readable; exit code ≠ 0 when drift exists
curl -s http://127.0.0.1:9095/v1/gpu/consumers | python3 -m json.tool
```

The audit cross-checks the driver's compute processes against the leases granted:

| Status | Meaning |
|---|---|
| `managed` | matches a lease the gateway granted |
| `desktop` | known non-inference user (Electron, browsers, editors, compositors, media players — `mpv`, `stremio`) |
| `idle_context` | a service that is merely **up** — a CUDA context of a few dozen MiB (`--idle-context-bytes`, default 256 MiB). Reported, never drift |
| `unmanaged` | **holding VRAM with no lease — drift** (a loaded model, gigabytes) |

If the gateway is unreachable the audit falls back to a local measurement (leases unknown) and says
so.

## Single entry point (by design, 2026-10-12)

**The gateway is the only entry to the GPU. If it does not work, GPU work does not happen — for
every class, without exception.** This is deliberate: it is the only way to guarantee that no job
ever runs unaccounted, and it makes the policy enforceable instead of aspirational.

Consequences, accepted on purpose:

- Consumers refuse to start (or refuse the job) when the gateway is unreachable — StênioREC's
  `HL_INFER_REQUIRED=true` makes this explicit, and the autopilot treats a non-admitted lease as an
  error.
- The gateway is therefore a **hard dependency** and must be as available as the GPU itself:
  `Restart=always` with the start limit disabled, the `HlInferDown` alert, and Prometheus scraping.
  If the gateway is down, `HlInferDown` fires — the operator's job is to bring it back.
- The reverse is also true and intentional: the gateway itself refuses to run without a GPU
  (ADR-020), so "no GPU" and "no gateway" collapse into the same, honest failure.

## Enforcement layers

| Layer | Where |
|---|---|
| **Static** | StenioSentinel rule `HOMELAB-GPU-UNIFIED` — a compose service claiming the GPU must be a registered consumer (`stenio --explain HOMELAB-GPU-UNIFIED`) |
| **Dynamic** | `hl-infer audit` / `GET /v1/gpu/consumers` |
| **Reactive** | alerts `HlInferUnmanagedConsumer`, `HlInferDown`, `HlInferVramExhausted`; dashboard **GPU Gateway (hl-infer)** |

## Registering a new consumer

1. Route the workload through the gateway (lease → work → release; renew for resident models).
2. Add the service name to **`mnemocine/network/gpu-consumers.txt`** (a data edit — never an engine
   change; the engine falls back to a built-in list only when that file is missing), and to the
   consumer list in [`services/hl-infer.md`](../services/hl-infer.md).
3. Give it a kind: interactive (`transcribe`) or batch (`triage`/`create`/`image_gen`).

## Owner priority (2026-10-12)

The machine owner always wins on their own GPU:

- **Reserve:** the gateway shields `hl_infer_owner_reserve_bytes` (default ~1.4 GiB,
  `--owner-reserve-bytes`) from **batch** classes. Autonomous work can never consume below that
  floor, so the owner always has headroom for their own apps and games.
- **Interactive classes** (the owner's own work, e.g. transcription) **may** use the reserve.
- **Consumers release VRAM as soon as they are idle:** the model is unloaded after the idle timeout
  and the lease is released with it, so a reservation never outlives the actual usage.
- A batch job that does not fit above the floor **waits**; it never competes with the owner.

## Model store (canonical)

There is **one** Ollama store for the whole homelab: `/mnt/NVME_PCI/ollama_models/models`.
The GPU worker container mounts `/mnt/NVME_PCI/ollama_models` at `/root/.ollama` (so its models land
in `models/`), and the host service is pointed at the same path via the documented `OLLAMA_MODELS`
variable (systemd drop-in `/etc/systemd/system/ollama.service.d/10-models.conf`).

Before 2026-10-12 the host used `~/.ollama` while the worker used the NVMe path — two stores, two
copies of the same model. When provisioning new models (HB-023), pull them **once** into the
canonical store; the host and the worker then see the same set.

> Ownership note: the container writes as `root`, the host service runs as user `ollama`. Files are
> world-readable (0644), so both can read; each side owns what it pulls. Keep the directory
> group-writable (`0775`, group `ollama`).

## Troubleshooting

| Symptom | Check |
|---|---|
| Job stuck `queued` | `GET /v1/queue` → is `effective_free_bytes` enough? Batch job outside a window? |
| VRAM "reserved" but nothing running | a consumer died without releasing — wait for the TTL (default 30 min) or restart it; `hl_infer_leases_expired_total` counts these |
| `hl-infer` down | `systemctl status hl-infer`; consumers that require a lease will refuse to work (by design) |
| Drift alert firing | `hl-infer audit` → find the pid, then make it a registered consumer or stop it |
| Batch never runs | the fixed windows may not cover the current hour |

## Migration status

See the fleet inventory in [`services/hl-infer.md`](../services/hl-infer.md#migration-pending).
Only **psicopompo** has a GPU, so the migration is entirely local: StênioREC → autopilot (via
Ollama) → retire the redundant lifecycle logic (`gpu-supervisor`, `sumaenima-ctl gpu up/down`,
per-consumer `keep_alive`, the 180 s idle auto-exit).
