---
tags: [homelab, service, comfyui, gpu, psicopompo]
pending: [HB-036]
---

# ComfyUI (Diffusion Image Generation)

Image-generation engine — a **batch** consumer of the single RTX 5050 on psicopompo. It touches the
GPU only through [`hl-infer`](hl-infer.md) (ADR-020, no CPU fallback).

**Server:** psicopompo · **Port:** `8188` · **Bind:** `127.0.0.1` + `100.82.51.112` (never `0.0.0.0`)
**Compose:** `/home/edu/homelab/comfyui/compose.yml`
**Image:** `obeliks/comfyui:master-cu130@sha256:a1d2d28b…` — **community image** (ComfyUI publishes no
official one; cited in the compose header), running upstream ComfyUI 0.39.0 / torch 2.14.1+cu130
**Firewall:** `ufw allow in on tailscale0 to any port 8188 proto tcp comment 'ComfyUI via Tailnet'`

## GPU policy (the important part)

It is a **registered consumer** ([`network/gpu-consumers.txt`](../network/gpu-consumers.txt)).

> ✅ **It can stay up.** Idle it holds only a **~84 MiB CUDA context**, which the gateway classifies
> as `idle_context` (tolerated, still reported) — not drift. So the container runs with
> `restart: unless-stopped` and the UI is available whenever you want it.
>
> ⚠️ **Generating is the part that needs a lease.** Loading a model costs gigabytes, and that *is*
> drift unless leased. Two consequences:
> 1. A **caller** must lease (`kind: image_gen`) before triggering a generation — and pass the
>    **`process: "python"`** hint, because the driver reports ComfyUI's process as `python`, not as
>    `comfyui`.
> 2. **Interactive use by a human is ALLOWED outside the batch windows** — decided by the owner
> 2026-10-14 via an `other`-kind lease, verified live at 11:16 (admitted, released, ledger clean).

The recipe (verified live):

```bash
# 1. lease (batch: image_gen drains only inside the gateway windows)
curl -s -X POST 'http://127.0.0.1:9095/v1/jobs?wait_secs=600' -H 'content-type: application/json' \
  -d '{"kind":"image_gen","required_bytes":6442450944,"label":"comfyui-sdxl","process":"python"}'
# 2. start the consumer
docker compose -f /home/edu/homelab/comfyui/compose.yml up -d
# 3. generate… then free VRAM and release
curl -s -X POST http://127.0.0.1:8188/free -H 'content-type: application/json' -d '{"unload_models":true,"free_memory":true}'
curl -s -X POST http://127.0.0.1:9095/v1/jobs/<id>/release
docker compose -f /home/edu/homelab/comfyui/compose.yml stop
```

Batch windows are `06:00-07:00, 12:00-13:00, 18:00-19:00, 00:00-01:00`; the ~1.4 GiB **owner reserve**
is shielded from `image_gen`, so autonomous generation can never push the owner out of their GPU.

## Models — the 8 GB checkpoint decision (HB-036)

**Not shipped** — the service serves its UI/API with an empty model store. Weights live under the
bind mount `/mnt/NVME_PCI/comfyui/models/<subdir>/`, deliberately **outside** the `config-backup`
roots so multi-GB checkpoints are never mirrored. Adding a model is a file drop (no rebuild).
ComfyUI resolves the store as `/app/models` (verified live):

| ComfyUI folder | Host path | Loaded by |
|---|---|---|
| `checkpoints/` | `/mnt/NVME_PCI/comfyui/models/checkpoints` | `CheckpointLoaderSimple` (all-in-one SDXL / SD 1.5) |
| `diffusion_models/` (`unet/`) | `/mnt/NVME_PCI/comfyui/models/diffusion_models` | `UNETLoader` (Flux / SD3 transformer-only) |
| `text_encoders/` (`clip/`) | `/mnt/NVME_PCI/comfyui/models/text_encoders` | `DualCLIPLoader` / `TripleCLIPLoader` / `CLIPLoader` |
| `vae/` | `/mnt/NVME_PCI/comfyui/models/vae` | `VAELoader` |

The image is fully capable offline: `GET /object_info` exposes **673 node classes**, including every
loader a checkpoint needs (`CheckpointLoaderSimple`, `UNETLoader` with `fp8_e4m3fn`, `DualCLIPLoader`
for `sdxl`/`sd3`/`flux`, `TripleCLIPLoader`, `VAELoader`, `KSampler`, `ModelSamplingFlux`/`SD3`,
`SaveImage`) — no custom node is required for the models below.

### What actually fits in 8 GB

The GPU is an **RTX 5050, 8 GB**. At rest the gateway measures **6.75 GiB effective-free** for a
batch job (total 8.55 GB − owner reserve − desktop baseline; `GET /v1/queue` →
`effective_free_bytes = 7243563008`). ComfyUI can *run* anything by streaming weights from the host's
48 GB of RAM ("as low as **4 GB VRAM + 8 GB RAM**", upstream README), so the question is not "does it
load" but **how much streams over PCIe and how slow it gets**.

| Model | Weights on disk | Fits the 6.75 GiB batch headroom? | Speed @1024² | Workflow | Licence |
|---|---|---|---|---|---|
| **SDXL base 1.0 (fp16)** | **6.94 GB** all-in-one (UNet 5.14 + OpenCLIP-G 1.39 + CLIP-L 0.25 + VAE 0.17) | **Yes** — 5.1 GB UNet resident, text encoders offloaded to RAM | seconds | `CheckpointLoaderSimple` + stock nodes (already present) | CreativeML OpenRAIL++-M |
| SD 1.5 (fp16) | 4.27 GB ckpt / ≈2.1 GB fp16 pieces (UNet 1.72 + TE 0.25 + VAE 0.17) | Yes, trivially | ~1–2 s | `CheckpointLoaderSimple` | CreativeML OpenRAIL-M |
| SD 3.5 medium | 5.11 GB transformer + T5-XXL fp8 4.89 + clip_g 1.39 + clip_l 0.25 + VAE 0.17 ≈ **11.7 GB** | transformer yes; **the 4.9 GB T5-XXL must stay in RAM and stream** | ~10–25 s | `UNETLoader` + `DualCLIPLoader`/`TripleCLIPLoader` + separate VAE | Stability Community (free <$1M) |
| Flux.1 dev (fp8) | **17.2 GB** single-file (UNet ≈11.9 GB) + t5xxl 4.89 + clip_l + ae | **No** — 11.9 GB UNet ≫ 6.75 GiB → constant weight streaming | tens of s – minutes | `UNETLoader` + `DualCLIPLoader` + separate VAE | **FluxDev Non-Commercial** |
| Flux.1 schnell (fp8) | same 12 B weights (≈17 GB) | No (streams), but only 4 steps | seconds – tens of s | as Flux dev | Apache-2.0 |

Sources: exact file sizes from the Hugging Face model APIs for `stabilityai/stable-diffusion-xl-base-1.0`,
`stable-diffusion-v1-5/stable-diffusion-v1-5`, `stabilityai/stable-diffusion-3.5-medium` and
`Comfy-Org/flux1-dev`; the "12 B params / ≈23 GB fp16 / fp8 checkpoint" guidance from the
[ComfyUI Flux.1 tutorial](https://docs.comfy.org/tutorials/flux/flux-1-text-to-image); the
"4 GB VRAM + 8 GB RAM via weight streaming" claim from the
[upstream ComfyUI README](https://github.com/comfyanonymous/ComfyUI); VRAM headroom measured live.

### Decision

**Recommended (primary): SDXL base 1.0, fp16.**

- **Repo / file:** `stabilityai/stable-diffusion-xl-base-1.0` → **`sd_xl_base_1.0.safetensors`** (6.94 GB)
- **Licence:** CreativeML Open RAIL++-M
- **Destination:** `/mnt/NVME_PCI/comfyui/models/checkpoints/sd_xl_base_1.0.safetensors`
- **Why:** it is the **realistic ceiling for 8 GB**. The 5.1 GB fp16 UNet runs largely resident in the
  6.75 GiB batch headroom (only the text encoders are offloaded), so a 1024² image takes **seconds,
  not minutes**. It is a single all-in-one file → the stock `CheckpointLoaderSimple` → `KSampler` →
  `VAEDecode` graph this image already exposes, with no extra encoders or VAEs to fetch. Best
  quality-per-effort that actually fits.

**Fallback (a guaranteed floor): SD 1.5, fp16.**

- **Repo / file:** `stable-diffusion-v1-5/stable-diffusion-v1-5` → `v1-5-pruned-emaonly.safetensors`
  (4.27 GB), or the fp16 pieces (≈2.1 GB)
- **Licence:** CreativeML Open RAIL-M · **Destination:** `.../models/checkpoints/`
- **Why:** ≈2 GB resident, so it fits even while the owner is gaming; ~1–2 s/image. The floor that
  always runs.

**Considered and rejected as the *first* checkpoint:** SD 3.5 medium (better typography/prompt
following, but drags a 4.9 GB T5-XXL that must stream from RAM and needs a multi-loader workflow);
Flux.1 dev (11.9 GB UNet cannot fit → everything streams, plus a **non-commercial** licence); Flux.1
schnell (Apache-2.0 and fast at 4 steps, but still streams 12 B weights — a later upgrade, not the
first pick); SD 1.5 (quality ceiling too low to be the primary).

> **Do not download yet.** The item is the *decision*, to be taken deliberately by the owner — not
> the fetch.

### The lease a generation must take

A generation loads a model (gigabytes) — that **is** drift unless leased. The caller takes an
`image_gen` lease and **must pass the `process: "python"` hint**, because the driver reports
ComfyUI's process as `python`, not as `comfyui` (verified: `GET /v1/gpu/consumers` →
`{"pid":…,"name":"python","used_bytes":88080384,"status":"idle_context"}`).

```bash
# SDXL fp16: UNet 5.1 GB + ~0.9 GB activations ≈ 6 GiB — fits the 6.75 GiB batch headroom.
curl -s -X POST 'http://127.0.0.1:9095/v1/jobs?wait_secs=600' \
  -H 'content-type: application/json' \
  -d '{"kind":"image_gen","required_bytes":6442450944,"label":"comfyui-sdxl","process":"python"}'
# → 201 admitted (inside a batch window) ; 202 queued = WAIT, never generate
```

`required_bytes` is declared honestly for the **chosen** checkpoint: **6 GiB (`6442450944`)** for SDXL
fp16, **2 GiB (`2147483648`)** for the SD 1.5 fallback — an fp16 SDXL UNet is 5.1 GB, so declaring
less would over-commit the device. Batch windows and the owner reserve still apply.

## Operational notes

- **Stop is SIGKILL** (exit 137): ComfyUI ignores SIGTERM; its SQLite asset DB is crash-safe (WAL).
- `COMFYUI_EXTRA_ARGS=--disable-partner-nodes` — no outbound paid Comfy API calls, no model auto-downloads.
- The UI is reachable over the tailnet only, and interactive use **outside the batch windows** would
  need an `other`-kind lease (lowest priority, window-free) — a policy decision (HB-036).

---

## Status 2026-10-14 (HB-036 re-scoped)

**(a) Weights + on-demand runtime — ✅ verified.** `sd_xl_base_1.0.safetensors` (6.9 GB) is in
`models/checkpoints/` since 2026-10-13 15:03, and the container runs on demand
(`restart: unless-stopped`) without a permanent VRAM claim — the ledger stays honest when it is idle.

**(b) Interactive use — ✅ DECIDED by the owner on 2026-10-14: an `other`-kind lease is allowed, outside
the batch windows.** The gateway serves `other` whenever the measured VRAM allows (it ignores the
batch windows), so a human may work at any hour. Verified live at **11:16** — outside every batch
window (06–07, 12–13, 18–19, 00–01) — with `kind: other`, `required_bytes: 6 GiB`,
`process: "python"`: state **`admitted`** (`job-000001`), then released, and the ledger returned to
`{"unmanaged":0,"leases":[]}` (the ComfyUI process back to 88 MB idle). Rationale for the record:
ComfyUI is a *tool for a person*, not only a pipeline stage, and the VRAM ledger — not a fixed
schedule — is what actually protects the GPU: the gateway admits a job only when the measured free
VRAM fits it. The cost, accepted knowingly: a human lease can delay the autopilot's `image_gen`
jobs, since `other` has the lowest priority but is still admitted when VRAM fits.

**(c) ComfyUI as an image source for the autopilot — ⚠️ open, and adjacent to HB-032/HB-037.** Wiring
generated imagery into the publishing path is the same integration surface as the per-persona
`visual` block, so the two should land together rather than as two divergent designs.
