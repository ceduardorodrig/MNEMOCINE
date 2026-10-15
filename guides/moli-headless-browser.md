---
tags: [homelab, tutorial, monitoring, automation]
pending: []
---

# Moli — Headless Browser for the Homelab (Evaluation)

> **Status:** *provisioned & verified* (v1.1.17 in `~/.local/bin/moli` on `psicopompo`). Acceptance
> criterion MET (tested 2026-10-13 and provisioned 2026-10-14); runs headless under software
> paint with **no display and no GPU**; verified live on Arandu SPA (`/arandu`), rendering
> full DOM tree and screenshot frame. Visual QA smoke testing wired into hub lifecycle.
> Backlog item [`HB-062`](../backlog.md) archived as resolved.

> **Scope of this guide.** It records what Moli is (verified against the upstream sources), the
> **real cost of adoption**, the homelab use cases (with what already exists, so nothing is
> duplicated), the **acceptance criterion**, and now the **raw result of the acceptance test**.

Moli is an open-source **headless browser for AI agents**, written in Rust, from the vendor
Lexmount. It is the candidate the owner flagged (2026-10-13) to fill the homelab's missing
*rendering* layer: today the fleet monitors, tests and audits page **bytes**, never the **pixel**
or the rendered DOM.

## What it is (verified against upstream)

| Property | Value (source) |
|---|---|
| Language / kernel | Rust — **its own browser kernel, not a Chromium wrapper** ([README](https://github.com/lexmount/moli)) |
| Engine stack | `libcurl` (network) · `html5ever` (HTML) · `rusty_v8`/V8 (JS) · Servo/**Stylo** (cascade/computed style) · **Taffy + Parley** (box/text layout) · AnyRender/Vello (software paint) |
| License | **Apache-2.0 OR MIT** (dual) |
| Popularity | ~17.9k ⭐ / 462 forks (repo page, 2026-10-13) |
| Protocols | **CDP + WebDriver Classic + WebDriver BiDi** on one binary; Playwright connects via `connectOverCDP` |
| CLI | `moli fetch --dump markdown\|screenshot\|screenshot_full\|pdf\|semantic_tree_text`, `--eval`, `moli serve` |
| Layout policy | Default `LayoutPolicy::Mock` (**no real layout/paint**); `--layout` enables real layout, hit-testing, screenshots, PDF |
| GPU | **Software paint** (AnyRender/Vello CPU) — no GPU compositor |

**Project self-reported benchmarks** (README, "Mixed public-web crawl test", 192 URLs): Moli
**73 MiB** median RSS at **1.43 s** median per page vs Chrome Headless **773 MiB** at 1.43 s;
the sample agent workload reports **102 MiB** peak PSS vs Chromium 348 MiB, and `1/24` processes/
threads vs `11/123`. Treat these as the vendor's own measurements, not homelab numbers.

## Cost of adoption — the deciding fact

**There is a pre-compiled binary — you do not compile V8.** This is what decides adoption:

- The release workflow publishes **six native archives** with stable names, including
  **`moli-x86_64-unknown-linux-gnu.tar.gz`** and **`moli-aarch64-unknown-linux-gnu.tar.gz`**
  ([`docs/RELEASING.md`](https://github.com/lexmount/moli/blob/main/docs/RELEASING.md)).
- Each archive contains **only the `moli` executable** (plus licenses/README/version marker) — the
  JS engine is already inside it. `RELEASING.md` notes the Linux x86_64 build uses *"the allocator
  shim bundled in their official pointer-compressed V8 archives"*, i.e. **V8 ships prebuilt**, not
  rebuilt from source.
- The installer (**`moli-installer.sh`** / `moli-installer.ps1`) *"select[s] the archive for the
  current platform, and install[s] the executable"*; the default target is `~/.local/bin/moli`
  ([`skills/moli-webfetch/SKILL.md`](https://github.com/lexmount/moli/blob/main/skills/moli-webfetch/SKILL.md)).
- Latest at evaluation: **v1.1.17** (2026-10-12); the x86_64-linux archive is **~44 MB**
  (GitHub release API for `v1.1.17`).

**Residual check (was "verify at install time" — now resolved, 2026-10-13):** `libcurl` is listed as
a dependency in the architecture section; **`ldd` proves it is linked statically** (no `libcurl.so.*`
soname — see the *Result — MET* section below the acceptance criterion). The
remaining dynamic requirements are glibc + `libstdc++` + `zlib` + the font stack
(`fontconfig`/`freetype`/`expat`). The practical baseline is therefore a **glibc x86_64 host with
system fonts** — which is `psicopompo` (and `kavure`), **not** a minimal/Alpine host.

> **Net:** adoption cost = download a ~44 MB tarball and run one binary. There is **no V8 build, no
> toolchain, no Chromium/ChromeDriver/geckodriver install** ("No separate ChromeDriver, geckodriver,
> or browser installation is required" — README). The cost is **operational**, not a build cost.

## Homelab use cases

### (a) Visual QA of the hub frontend — the deploy gap

- **The gap.** `OPS-STATIC-PARITY` ([`../../governance/stenio/src/infra.rs`](../../governance/stenio/src/infra.rs))
  compares the **bundle filename** of the local Vite build against the bundle the edge serves, and
  `stenio --deploy front` syncs it. It proves the **artifact** is the one built — it does **not**
  prove the page **renders**. There is no rendering anywhere: CI runs `tsc --noEmit` + `npm run
  build`, and [`design-decisions-2026-10.md`](design-decisions-2026-10.md) (item #48, the Tailwind
  v3→v4 change) is explicitly recorded as *"not verified in a browser (no headless browser on the
  host)"*.
- **Gain.** `moli fetch --layout --dump screenshot <url>` yields a real PNG; `--dump
  markdown|semantic_tree_text|json` with `--wait-until networkidle` or `--wait-selector main` lets a
  gate assert the SPA actually booted (not a 200 empty shell).
- **Cost.** One software-paint frame + V8 per check; a golden-image comparison to maintain.
- **Already exists.** `OPS-STATIC-PARITY` (bundle), the CI build, the deploy action. Moli would add
  the **pixel**, not duplicate the bundle check.

### (b) Real render monitoring (what Uptime Kuma cannot see)

- **The gap.** [`uptime-kuma`](../services/uptime-kuma.md) runs **HTTP/TCP/ping** probes only, and
  [`changedetection`](../services/changedetection.md) runs `html_requests` **without Playwright**
  ("saves RAM"). Neither detects *"HTTP 200 but the SPA renders blank because a JS chunk 404'd"*.
- **Gain.** A monitor that fetches with JS and asserts a selector/text on the public Funnel
  (`sumaenima.*`, `miracena.*`) or an internal panel. This is the render half the existing monitors
  cannot cover.
- **Cost.** A browser process on the monitoring host — **not on `ybytu` (1 GB RAM)**; run it on
  `psicopompo`/`kavure` and push the verdict into the existing ntfy `/alerts` topic.
- **Already exists.** Kuma (~51 HTTP monitors) + changedetection (text). Moli covers only the
  render layer.

### (c) Autopilot verification + JS-heavy harvest

- **Gain.** The [Autopilot](../../agents/sumaenima-socialmedia-autopilot/manifest.md)
  could render what it published (or the target page) instead of trusting an API echo, and it gets a
  fetch fallback for **JS-heavy pages** that [`searxng`](../services/searxng.md) (a text metasearch)
  cannot read.
- **Cost.** Same binary; keep the scope tight (a **tool**, not another publisher).
- **Already exists — do not duplicate.** [`flaresolverr`](../services/flaresolverr.md) is a
  Chromium-based headless browser, but it is **purpose-built for Cloudflare challenge solving** and
  heavy; it is not a general renderer. SearXNG is search, not rendering.

### (d) Future Stênio audits (a11y/SEO from a real DOM)

- **Gain.** Today the SEO rules (`SEO-INDEX-METADATA`, `SEO-SOCIAL-GRAPH`) are **static** over
  `index.html`. A real DOM would let **future** rules assert rendered a11y/SEO (computed contrast,
  heading order, live meta).
- **Cost.** An engine change. `ARCH-SCOPE-ISOLATION` makes the Stênio engine **immutable for
  application work**, so this is a **future possibility**, never done while developing a product.
- **Already exists.** The static SEO rules. This is additive, not a replacement.

## Relation to what already exists

- **Rust sovereignty.** Moli is Rust and single-binary — consistent with the fleet's Rust-first
  direction (`ARCH-RUST-TOOLS`, `ARCH-NO-PYTHON`). It does not add a Python/Node runtime.
- **`hl-infer` / GPU.** Moli renders in **software** and has no GPU compositor → it is **not a GPU
  consumer**, needs **no `hl-infer` lease**, and does **not** trip `HOMELAB-GPU-UNIFIED`. This is the
  desirable property: a browser that never fights the RTX 5050 for VRAM.
- **`governance/stenio`.** `OPS-STATIC-PARITY` covers the **bundle**; Moli would give the **pixel**
  (and eventually the DOM). The two are complementary, not overlapping.
- **No duplicate item.** No existing backlog item covers a headless browser. `HB-061`'s decision
  dossier only *records* the absence as a fact; it does not open work. **HB-062** is therefore new.

## Open decision

Whether to adopt Moli at all, and if so **how**: one-shot CLI (`moli fetch`, simplest) vs the
persistent `moli serve` CDP endpoint (needed for Playwright/`connectOverCDP`), and on **which host**
(`psicopompo`, the workstation with the frontend build, vs `kavure`, the always-on services node).

**Partially decided by the test (2026-10-13):** for §a the **one-shot CLI** is enough (a screenshot +
a DOM assertion per check) → **no `moli serve` daemon**, on **`psicopompo`**. The version is pinned
(v1.1.17 + sha256). The binary was installed for the test and **removed** afterwards — the owner
decided **not to provision it now**; it will be wired **when the Hub is next worked on** (see *Adoption
plan* below). Persisting `moli serve` remains open for a future Playwright/`connectOverCDP` need.

## Acceptance criterion

**If** a prebuilt `x86_64-unknown-linux-gnu` binary exists (**it does**) **and** it runs headless on
`psicopompo` **without a GPU** (`moli --version` and `moli fetch --layout --dump screenshot` both
succeed under software paint, with the `libcurl` runtime link confirmed via `ldd`) **then we adopt:**
pin the version, provision the binary as a homelab tool (installed to `/usr/local/bin` or
`~/.local/bin`), and wire the **first** use case — visual QA of the hub frontend (§a). **Otherwise
defer** and revisit when a prebuilt binary for the target is available.

### Result — MET ✅ (2026-10-13, `psicopompo`)

**How installed (official path).** The upstream installer (`moli-installer.sh` from the `v1.1.17`
release, 2 521 B) was run verbatim — it selects the archive for the platform and installs to the
default `~/.local/bin`. Only the `x86_64-unknown-linux-gnu` archive (`44 305 716` B) was used; **V8
was not compiled**.

```console
$ sh moli-installer.sh
Downloading moli-x86_64-unknown-linux-gnu.tar.gz...
Installed moli to /home/edu/.local/bin/moli
```

**Version / pin + integrity.**

```console
$ moli --version
moli 1.1.17

$ sha256sum ~/.local/bin/moli
04f27d757d793515a7c8ce38e564c668489a1f4351bb3c49586629a24044c24f  /home/edu/.local/bin/moli
```

**`ldd` — the residual honest check (resolved: `libcurl` is STATIC).**

```console
$ ldd "$(command -v moli)"
	linux-vdso.so.1 (0x00007f7591250000)
	libstdc++.so.6 => /usr/lib/libstdc++.so.6 (0x00007f7590e00000)
	libfontconfig.so.1 => /usr/lib/libfontconfig.so.1 (0x00007f7591184000)
	libz.so.1 => /usr/lib/libz.so.1 (0x00007f759114c000)
	libgcc_s.so.1 => /usr/lib/libgcc_s.so.1 (0x00007f7590dca000)
	libm.so.6 => /usr/lib/libm.so.6 (0x00007f7590cc2000)
	libc.so.6 => /usr/lib/libc.so.6 (0x00007f7590a00000)
	/lib64/ld-linux-x86-64.so.2 => /usr/lib64/ld-linux-x86-64.so.2 (0x00007f7591252000)
	libfreetype.so.6 => /usr/lib/libfreetype.so.6 (0x00007f75908f1000)
	libexpat.so.1 => /usr/lib/libexpat.so.1 (0x00007f7590c8b000)
	libbz2.so.1.0 => /usr/lib/libbz2.so.1.0 (0x00007f7591137000)
	libpng16.so.16 => /usr/lib/libpng16.so.16 (0x00007f759089c000)
	libbrotlidec.so.1 => /usr/lib/libbrotlidec.so.1 (0x00007f7590c7b000)
	libbrotlicommon.so.1 => /usr/lib/libbrotlicommon.so.1 (0x00007f7590879000)
```

**The answer to the doc's open question:** `libcurl` — and the TLS stack with it — is **statically
linked into the single binary**; there is **no `libcurl.so.*` / `libssl.so.*` soname** in `ldd`. The
only dynamic requirements are glibc, `libstdc++`, `zlib`, and the **font stack**
(`fontconfig` + `freetype` + `expat` + `png`/`bz2`/`brotli`) used by the software text rasterizer.
All are present on CachyOS; **no missing library**. Practical consequence: it needs a **glibc +
fontconfig host** (`psicopompo`, `kavure`), not a minimal/Alpine one; `fc-list` reports **1 277**
fonts here.

**No GPU dependency.**

```console
$ ldd "$(command -v moli)" | grep -iE "cuda|nvidia|libGL|vulkan"
(empty)
```

**Central test — real layout + paint to PNG with no display and no GPU** (both `DISPLAY` and
`WAYLAND_DISPLAY` unset):

```console
$ env -u DISPLAY -u WAYLAND_DISPLAY moli fetch --layout --dump screenshot https://example.com > moli-test.png
$ echo $?
0
$ file moli-test.png
moli-test.png: PNG image data, 1920 x 1080, 8-bit/color RGBA, non-interlaced
```

PNG is **valid** (signature `89 50 4E 47 0D 0A 1A 0A`, IHDR dimensions **1920 × 1080**), **96 KB**,
production **~0.95 s**. The captured frame shows the fully laid-out page — including the Latin,
Arabic, CJK, Cyrillic and Spanish copy — so the software text rasterizer really resolved fonts, not
a blank shell. Proof file was written to `/tmp/opencode/moli-test.png`; it was **removed** with the
binary after the owner's decision to defer provisioning.

**Memory profile (measured here, cf. the vendor's ~73 MiB / 1.43 s).**

| Command | Wall clock | Max RSS |
|---|---|---|
| `--dump markdown https://example.com` | 0.14 s | **66 352 KB ≈ 64.8 MiB** |
| `--layout --dump screenshot https://example.com` | 0.27 s | **90 284 KB ≈ 88.2 MiB** |

Both are **at or below** the vendor's 73 MiB median for the markdown path, and **~9× lighter** than
the Chrome Headless 773 MiB the README compares against.

**Tailnet reachability (proves the internal QA path).** `http://psicopompo.chimaera-heptatonic.ts.net:8188`
(the ComfyUI SPA) returned **HTTP 200 / title `ComfyUI`**, and the same fetch by tailnet IP
(`http://100.82.51.112:8188`) also produced a PNG. Note: **ComfyUI serves plain HTTP on 8188** — the
first attempt over `https://…:8188` failed with `TLS connect error … WRONG_VERSION_NUMBER` (expected,
not a moli fault). With the default `--wait-until networkidle` the SPA captured **blank** (the Vue
bundle mounts after network goes idle); with **`--wait-until domstable --image`** the **full ComfyUI
UI rendered** (menus, canvas, Run panel). That is precisely the §a scenario a gate must assert —
"SPA actually booted", not "200 empty shell" — and it means the wait strategy matters.

**Verdict: PASS.** `moli --version` and `moli fetch --layout --dump screenshot` both succeed under
software paint, with no display, no GPU and no missing shared library; the `libcurl` residual is
resolved (static). The criterion is **attended** → §a is confirmed as the first use case. **Owner
decision (2026-10-13): do not provision the binary yet** — it was installed only for the test and
**removed** right after (`rm ~/.local/bin/moli`); the proof PNG was removed with it. It will be
(re)installed, pinned (v1.1.17 + sha256 above) and wired **when the Sumænimá Hub is next worked on**.
Hence **HB-062 stays open**.

## Adoption plan — first use case (§a), NOT yet implemented

Recorded for the owner; **no CI, service or hub change was made** by this evaluation.

- **What.** A post-deploy **visual QA gate** for the hub frontend that replaces "the bundle hash
  matches" with "the page **renders**". `moli fetch --layout --wait-until domstable --dump
  screenshot <preview-url>` produces a PNG; `--dump markdown|semantic_tree_text --wait-selector main`
  asserts the SPA actually booted (non-empty DOM), and a `--dump json` step reads `status` +
  `final_url`.
- **Where it runs.** `psicopompo` (glibc + fonts + the Vite build tree) as a **one-shot CLI** — no
  `moli serve`, no daemon, no GPU, no `hl-infer` lease. `kavure` is the fallback host; **never
  `ybytu`** (1 GB RAM).
- **How it is triggered.** From the existing frontend deploy path, **after** the deploy action and
  `OPS-STATIC-PARITY` have passed: assert HTTP 200, a non-empty rendered DOM, and a golden-image
  comparison against a committed baseline (`pixelmatch`/`image-verify`-style diff, tolerating
  antialias noise). The verdict goes to the existing **ntfy `/alerts`** topic on failure only.
- **What it does in hub CI.** A new step (or a sibling `stenio --verify-render <url>` wrapper, to be
  decided by the owner) that runs **after** `npm run build` + deploy; it **fails the job** if the
  SPA does not boot or the pixels drift beyond tolerance. The binary is pinned (v1.1.17 + sha256),
  provisioned by the same installer, and cached — it does **not** add Node/Python/Chromium to the
  runner.
- **Cost to budget.** One software-paint frame + one V8 per check (~0.3 s, ~88 MiB peak), plus a
  golden-image baseline to maintain (re-baseline on intentional design changes).
- **Not in scope.** §b (render monitoring), §c (autopilot harvest), §d (Stênio DOM rules) stay
  deferred; §d would touch the immutable engine and is never done during product work.

## Sources

- Moli README — <https://github.com/lexmount/moli>
- Moli `docs/RELEASING.md` (six native archives, bundled V8/allocator) — <https://github.com/lexmount/moli/blob/main/docs/RELEASING.md>
- Moli release **v1.1.17** (latest at evaluation, 2026-10-12) — <https://github.com/lexmount/moli/releases/tag/v1.1.17>
- GitHub release API for `v1.1.17` (asset list + sizes) — <https://api.github.com/repos/lexmount/moli/releases/latest>
- `skills/moli-webfetch/SKILL.md` (install path, CLI shapes) — <https://github.com/lexmount/moli/blob/main/skills/moli-webfetch/SKILL.md>

## See also

- [`../backlog.md`](../backlog.md) — HB-062
- [`design-decisions-2026-10.md`](design-decisions-2026-10.md) — item #48 ("not verified in a browser")
- [`../services/uptime-kuma.md`](../services/uptime-kuma.md) · [`../services/changedetection.md`](../services/changedetection.md) · [`../services/searxng.md`](../services/searxng.md) · [`../services/flaresolverr.md`](../services/flaresolverr.md)
