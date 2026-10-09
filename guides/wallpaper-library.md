---
tags: [homelab, tutorial, psicopompo, wallpaper, gpu, nvidia]
created: 2026-09-27
updated: 2026-09-27
---

# Wallpaper Library — Organization & Upscaling Pipeline (psicopompo)

Operational playbook for managing the wallpaper collection on `psicopompo`: resolution and orientation classification, upscaling sub-4K imagery via GPU, and production failure modes documented on 2026-09-27.

**Storage Root:** `/home/edu/Pictures/PAREDEDEPAPEL/`  
**Automation Script:** [`scripts/wallpaper-pipeline.sh`](../scripts/wallpaper-pipeline.sh)

> ℹ️ **Backup Coverage:** The collection is included in the canonical backup pipeline (`config-backup` → NAS mirror, Snapper snapshots, Restic, Google Drive).

> ⚠️ **Critical Rule:** Always invoke the model at its **native scale** (`-s 4` for `realesrgan-x4plus`). Invoking `-s 2` with an x4 model corrupts image tiles (see Pitfall 1).

---

## Canonical Hierarchy

```
PAREDEDEPAPEL/
├── wallpaper-pc/               # >=4K landscape or square images (Desktop monitors)
├── wallpaper-celular-tablet/   # >=4K vertical orientation (Mobile / Tablet)
└── menores-4k/                 # <4K — Processing queue for upscaling (Transient)
```

Root directories must contain only these three operational folders.

## Classification Criteria

**4K Specification:** `width >= 3840 AND height >= 2160` (UHD). `5120x2880` qualifies; `3840x1920` fails the vertical bound.

**Orientation:** Evaluated using **rendered display dimensions**, factoring in EXIF orientation tags:
- `width >= height` $\rightarrow$ `wallpaper-pc` (square wallpapers are categorized as PC).
- `height > width` $\rightarrow$ `wallpaper-celular-tablet`.

---

## Documented Pitfalls & Failure Modes

### 1. Invoking `-s 2` on an x4 Model Corrupts Tiles 🔴

`realesrgan-x4plus` is an architectural **x4 model**. Passing `-s 2` forces the binary to run the x4 neural network and downscale internally. This breaks tile boundaries against the downscaling grid, causing images to appear diced into misaligned blocks.

**Remediation:** Always upscale at the model's native scale (`-s 4`) and downscale subsequently via Lanczos if needed.

```bash
# Correct: Native x4 inference
realesrgan-ncnn-vulkan -i in/ -o out/ -s 4 -n realesrgan-x4plus -f jpg

# Forbidden: Destroys tile alignment
realesrgan-ncnn-vulkan -i in/ -o out/ -s 2 -n realesrgan-x4plus -f jpg
```

### 2. EXIF Orientation Tags Invalidate Raw Image Headers

Standard PIL or image header probes read raw pixel matrices. However, JPEGs frequently contain EXIF tag `0x0112` instructing display viewers to rotate the image by 90° or 270°.

Always resolve orientation before classification:
```bash
orient=$(identify -format '%[orientation]' "$file")
case "$orient" in RightTop|LeftBottom) read w h < <(echo "$h $w");; esac
```

### 3. Upscalers Strip EXIF Metadata

`realesrgan-ncnn-vulkan` operates on raw pixel buffers and drops EXIF headers. An image displaying in landscape orientation via EXIF rotation will upscale to portrait if the orientation tag is stripped.

**Remediation:** Normalize rotations into the underlying pixel matrix prior to inference:
```bash
magick "$file" -auto-orient "$normalized_file"
```

### 4. Neural Network Hallucinations on Flat / Minimalist Art 🟠

On vector art, logos, or retro pixel art, diffusion and ESRGAN models hallucinate noisy textures over flat color fields.

**Objective Heuristic:** Compare `file_size_bytes / total_pixels`. For images below `0.02 bytes/pixel`, bypass AI models and apply **Lanczos filtering**:
```bash
magick original.png -filter Lanczos -resize 400% output.png
```
This preserves vector lines and reduces file sizes from ~100 MB down to ~3 MB with higher PSNR fidelity.

### 5. Tile Parameter `-t` Exceeding 512 Triggers Segmentation Faults

Tile sizes of 1024, 2048, or higher crash the Vulkan runtime. Restrict `-t` to 200 (default) or 512.

### 6. Format Preservation

Omitting `-f` converts all outputs to uncompressed PNG, causing 4K wallpapers to balloon to ~15 MB. Process in batches with explicit `-f jpg` for photographic content.

### 7. ICC Color Profile Preservation

The Vulkan upscaler drops color profiles. Preserve Adobe RGB and Display P3 profiles across processing to avoid color shifting.

### 8. VRAM Constraints (RTX 5050, 8 GB)

Each worker process consumes ~2.5–3 GB VRAM. Concurrency must be capped at **2 concurrent workers** to prevent Vulkan out-of-memory errors (`vkAllocateMemory failed -2`).

---

## Automation Pipeline

Execute the standard pipeline wrapper:

```bash
PIPELINE=/mnt/NVME_PCI/agentic-ai/mnemocine/scripts/wallpaper-pipeline.sh
ROOT=~/Pictures/PAREDEDEPAPEL

"$PIPELINE" report "$ROOT"              # 0) Audit inventory (dry-run)
"$PIPELINE" normalize "$ROOT" --apply   # 1) Bake EXIF rotations into pixels
"$PIPELINE" organize "$ROOT" --apply    # 2) Sort into canonical directories
"$PIPELINE" upscale "$ROOT"             # 3) Upscale sub-4K images via GPU
"$PIPELINE" organize "$ROOT" --apply    # 4) Final sort and cleanup
```

## References

- [`backups/strategy.md`](../backups/strategy.md) — Homelab backup topology
- [`servers/psicopompo.md`](../servers/psicopompo.md) — Host specifications (RTX 5050)
- Real-ESRGAN Vulkan: <https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan>
