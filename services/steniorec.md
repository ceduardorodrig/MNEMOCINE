---
tags: [homelab, service, gpu, psicopompo]
---

# StênioREC (Rust Whisper Daemon)

Unified audio transcription and real-time STT streaming daemon with GPU acceleration (CUDA 13) running on host **Psicopompo**, built 100% in Rust (Axum 0.8 + `whisper-rs`).

Replaces legacy fragmented Python workers (`steniobot-audio`, `steniobot-vision`, `transcribe_server.py`) with a single high-performance daemon.

---

## 1. Topology & Hardware

- **Physical Host:** Psicopompo (Xeon E-2246G + RTX 5050 8GB Blackwell)
- **Port:** `9090/tcp` (bound to `0.0.0.0:9090` on host)
- **Tailnet Access:** `http://100.82.51.112:9090` (or `http://psicopompo:9090`)
- **Container:** `steniorec` (image `sumaenima-server:latest` / `sumaenima-server:cuda`)
- **Compose:** `/mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/provisioning/stacks/gpu.yml`
- **Model:** Whisper `Large-v3-Turbo Q8_0` GGML (`/mnt/NVME_PCI/homelab/sumaenimahub/llm_model_cache/whisper-ggml/ggml-large-v3-turbo-q8_0.bin`, 874 MB)
- **VRAM Footprint:** ~1.6 GB on RTX 5050

---

## 2. Service Lifecycle

The service runs standalone and is managed via `sumaenima-ctl`:

| Command | Action |
|---|---|
| `sumaenima-ctl gpu up` | Starts the `steniorec` container on port 9090 |
| `sumaenima-ctl gpu status` | Checks container status, VRAM consumption, and CUDA binary linkage |
| `sumaenima-ctl gpu down` | Stops the container and releases GPU VRAM |

### Boot-Time Supervision (Fix 29/09/2026 — Rust Supervisor)

Managed by a **single** systemd unit executing the native Rust supervisor:

| Unit / Binary | Path | Function |
|---|---|---|
| `sumaenima-gpu.service` | `/etc/systemd/system/` | `Type=simple` + `Restart=always` → systemd revives the supervisor |
| `gpu-supervisor` (Rust) | `/usr/local/bin/` | Event-driven supervisor (source: `app/gpu-supervisor/` in hub) |

**Guaranteed Boot Ordering:** `tailscaled-wait.service` → `docker.service` → `sumaenima-gpu.service`.

Supervisor workflow:
1. Waits for `tailscale status → BackendState=Running` (IP addresses are assigned **after** the daemon reports *ready* — [tailscale#11504](https://github.com/tailscale/tailscale/issues/11504)).
2. Waits for active **Swarm session** (`LocalNodeState=active` + manager:2377 reachable + `ingress` network present). Note that on worker nodes, `docker node inspect self` does not exist.
3. Launches the worker via `docker compose up -d` **with exponential retries** — container network attachment is what materializes the overlay network (see §5).
4. Verifies `healthy` status and enforces the **image contract** (`:cuda`).
5. Enters **event-driven supervision**: Subscribes to Docker `/events` and reacts to `die`/`kill`/`stop`/`oom` within **milliseconds** (a 30s tick acts strictly as a fallback).

`gpu-supervisor --check` runs the 5 validation gates once and prints diagnostics.

> ⚠️ The initial implementation (29/09 morning) used a **bash script** + `Type=oneshot` + 5-minute timer. It was superseded because `Type=oneshot` **cannot use `Restart=`** in systemd. Measured recovery time dropped from 5 minutes down to **~10s**. The legacy **user unit** (`~/.config/systemd/user/sumaenima-gpu.service`) was removed because user units cannot order against system-level targets.

---

## 2b. Image Contract (Never `:latest`)

| Node | Role | Dockerfile | Tag |
|---|---|---|---|
| **psicopompo** | GPU (Whisper/CUDA) | `app/server/Dockerfile` | `sumaenima-server:cuda` |
| **kavure** | Core/API (No GPU) | `app/server/Dockerfile.cpu` | `sumaenima-server:cpu` |

The ambiguous tag `sumaenima-server:latest` **must not be used**. See §6 for the 28/09 incident where a tag collision caused the GPU worker to run CPU-only binaries.

---

## 3. Endpoints

| Method | Endpoint | Function |
|---|---|---|
| `GET` | `/v1/health` | Process liveness + `device` (`cuda`/`cpu`) and `device_count` |
| `GET` | `/v1/ready` | **Semantic readiness**: `503` if this build requires GPU and is not running CUDA |
| `POST` | `/v1/transcribe` | Batch audio transcription (JSON PCM 16kHz s16le Base64) |
| `WS` | `/ws/transcribe` | Bidirectional real-time streaming STT (AudioWorklet) |

### Web Client Audio Route (Fixed 29/09/2026)

The web recorder uses `wss://<host>/api/ws/transcribe`. This path is routed by the **edge Nginx DIRECTLY to this worker** (`100.82.51.112:9090`), and **not** to kavure's API:

| Rationale | Detail |
|---|---|
| **Why direct** | kavure runs the `:cpu` image **without model weights mounted** (`MODEL_PATH` pointed to a non-existent directory) — returning `Failed to auto-load model`. |
| **Protocol Safety** | Shares the **identical binary and WebSocket handler** (`app/server/src/ws.rs`) as the frontend expects — running where the GPU resides. **Zero protocol drift.** |
| **Verification** | Verified using live speech test (`Front_Center.wav`) over public Funnel URL: `TRANSCRIPT (final=True): 'Front Center'` + `DRAIN_COMPLETE`. |

> **Why `/v1/ready` exists:** `/v1/health` merely reports process liveness — a CPU-only binary returns `200`. `/v1/ready` verifies hardware acceleration matching the build, utilized by the `gpu.yml` healthcheck. See §8.

---

## 4. Integration Documentation

For guides on how agents and remote clients consume the API:
- [`docs/transcricao-remota-steniorec.md`](../../docs/transcricao-remota-steniorec.md) — Remote integration manual and Python client script.
- Sumænimá Hub repository: `scripts/st-transcribe/` (official Rust CLI tool).

---

## 5. Incident: Boot-Race Flapping (27/09/2026, Remediated 29/09)

**Symptom:** StênioREC experienced **~26 hours of downtime**. Tailnet clients received connection refused on port 9090.

**Root Cause:** Three cascading configuration bugs:
1. `sumaenima-gpu.service` was a **user unit** with only `After=network.target` → firing ~40s before the tailnet was operational.
2. `sumaenima-ctl` **swallowed errors**: A failing `docker compose up` printed output followed by a successful `echo`, returning exit code 0 → systemd reported `status=0/SUCCESS` despite container death.
3. `gpu.yml` had `restart: "no"` → Docker never attempted restarts.

**Remediation:** Migrated to native **Rust supervisor** (`app/gpu-supervisor/`), systemd system unit with `Type=simple` + `Restart=always`, event-driven container lifecycle monitoring.

> ⚠️ **Key Architectural Finding:** Overlay networks configured as *attachable* are instantiated **lazily on the worker node at attach time** (upstream commit [moby/moby c379d26](https://github.com/moby/moby/commit/c379d2681ffe8495a888fb1d0f14973fbdbdc969)). The worker node requests attachment from the manager, which schedules a task. Seeing `network not found` prior to container attachment is expected behavior. The correct check is **Swarm session readiness** + **retrying `docker compose up`**.

---

## 6. Incident: Tag Collision (`:cpu` Leaked into GPU Role) — 28/09/2026

**Symptom:** StênioREC booted, reported `/v1/health` 200, but transcribed **on CPU** (~20s per segment, 400% CPU usage, idle GPU). **Violated [ADR-020 (GPU-Only)](../../../../homelab/sumaenimahub/sumaenima-hub/docs/adr/020-gpu-only.md)**.

**Root Cause:** Tag `sumaenima-server:latest` was **shared** across both build roles. Building kavure's CPU image locally on psicopompo overwrote the local tag, leaving the CUDA image dangling, which was subsequently purged by post-build image cleanup.

**Resolution:** Strict explicit tags (`:cuda` / `:cpu`), scoped image pruning (`until=168h`), and deployment scripts enforcing image contracts.

---

## 7. Boot-Race Audit Across 6 Nodes (29/09/2026)

| Node | `tailscaled-wait` | Docker Waits for TS | Swarm Role | Session Failures Since Boot |
|---|---|---|---|---|
| psicopompo | ✅ (nfs-server, wol-relay, sumaenima-gpu) | ❌ | worker | 24 (resolved) |
| kavure | ❌ | ✅ (`nfs-ordering.conf`) | manager | 4 |
| ybyra | ❌ | ✅ | worker | — |
| ybytu | ❌ | ❌ | inactive | — |
| kuaray | ❌ | ❌ | `pending` (under review) | — |

---

## 8. ADR-020 (GPU-Only) Enforcement in Code — 29/09/2026

[ADR-020](../../../../homelab/sumaenimahub/sumaenima-hub/docs/adr/020-gpu-only.md) mandates *hard-fail on startup* and *required NVML initialization*. Upstream `whisper.cpp` silently falls back to CPU when a GPU is missing.

**Implementation (`app/server/src/device.rs`):**

| Requirement | Implementation |
|---|---|
| Hard-Fail (Exit Code 1) | `device::enforce()` called in `main()` prior to any workload execution |
| Mandatory NVML | `nvml-wrapper` crate — `Nvml::init()` + `device_count()` validation |
| Zero CPU Fallback | Guard activated conditionally on `feature = "cuda"` builds |
| Active Probing | `/v1/ready` (returns 503 if device ≠ cuda) consumed by compose healthcheck |

**Validation Runs (29/09):**
```bash
$ docker run --rm --runtime nvidia -e NVIDIA_VISIBLE_DEVICES=none sumaenima-server:cuda
WARN  [Device] NVML initialised but reported 0 devices
ERROR ADR-020 violation: this build requires an NVIDIA GPU, but NVML reports
      none. CPU fallback is forbidden. Refusing to start.
exit_code=1                                        ← Exit Code 1 as mandated

$ docker run --rm sumaenima-server:cpu             ← kavure (CPU build): Starts cleanly
[Main] Listening on http://0.0.0.0:9098

$ curl -s http://127.0.0.1:9090/v1/ready
{"device":"cuda","device_count":1,"ready":true}    ← HTTP 200
```
