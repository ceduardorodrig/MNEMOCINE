---
tags: [homelab, governance, ci, stenio, github, rust]
---

# Unified Stênio in CI

How **any** repository in the ecosystem audits its governance using **StenioSentinel**, without compiling Rust from source and without duplicating CI configurations.

Established on **2026-09-29**.

## The Problem Solved

Previously, every repository using Stênio had its own bespoke CI workflow that:

1. Cloned the engine source from another repository and executed `cargo build --release` — taking **~1 minute per CI run** per repo;
2. **Broke** whenever the engine workspace path was updated;
3. Froze individual repositories on diverging versions of the governance engine.

The specific failure case: The resume/CV repository (`ceduardorodrig`) CI attempted to compile `sumaenima-hub/scripts/steniocheck-rs`, which had been deleted in commit `70d7132`. It failed with `error: manifest path ... does not exist`. Furthermore, earlier runs had been falsely marked green because stale checkouts masked the underlying failures.

## Unified Architecture

```
STENIO-SENTINEL (Engine Repository, PUBLIC)
├── .github/workflows/release.yml              ← Builds and publishes binary
│      Trigger: Push of tag v*.*.*
│      Assets: stenio + stenio.sha256
└── .github/actions/stenio-check/action.yml    ← Reusable composite action
       Downloads release binary and executes audit

CONSUMERS (Any ecosystem repository)
└── .github/workflows/ci.yml
       - uses: ceduardorodrig/STENIO-SENTINEL/.github/actions/stenio-check@v1
         with:
           scope: all
```

**Results:** CI completes in **~9 seconds** (download only), enforces a single shared engine version across repositories, and upgrading the engine across all projects requires only publishing a GitHub tag.

## Repository Configuration

```yaml
name: ci

on: [push, pull_request]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  check:
    name: Governance Audit (Rust Native)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: StenioSentinel — audit repository
        uses: ceduardorodrig/STENIO-SENTINEL/.github/actions/stenio-check@v1
        with:
          scope: all
          path: .
          github-format: "true"
```

### Action Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `scope` | ✅ | — | `hub`, `homelab`, `vault`, `cv`, `fork`, `mirror`, `all` |
| `path` | ❌ | `.` | Target directory to audit |
| `strict` | ❌ | `false` | Fail on warnings in addition to errors |
| `github-format` | ❌ | `true` | Emits `::error` and `::warning` annotations on PRs |
| `version` | ❌ | latest release | Pin to a specific binary release (e.g. `v4.0.0`) |

### Scope Selection Matrix

| Repository | Recommended Scope |
|---|---|
| `SUMAENIMA-HUB` | `hub` |
| `ceduardorodrig` (CV / Resume) | `cv` |
| `MNEMOCINE` / Vault | `vault` or `homelab` |
| `MNEMOCINE-CONFIGS` (Generated mirror) | `mirror` |
| `macrokey-driver` (Upstream fork) | `fork` |
| Tier A Generic Projects (Rust/C) | `all` |

> ⚠️ **`MNEMOCINE-CONFIGS` does NOT use `homelab`.** It is an automated runtime state snapshot of hosts, not human-authored homelab documentation.

## Tagging Conventions

| Tag Ref | Target | Example |
|---|---|---|
| **`v1`** (Major floating branch) | The **Composite Action** — updated on every release | `uses: …/stenio-check@v1` |
| **`vX.Y.Z`** (Immutable SemVer) | The **Binary Release Asset** | `releases/download/v4.0.0/stenio` |

The `v1` tag represents the action interface contract, distinct from binary engine SemVer tags. `release.yml` automatically updates the `v1` floating pointer on new releases.

## Publishing a New Engine Release

```console
$ cd governance/stenio
$ # 1. Bump version in Cargo.toml following SemVer policies
$ cargo build --release && ./target/release/stenio --self-test && ./target/release/stenio --guardian
$ git commit -am "release: vX.Y.Z"
$ git tag -a vX.Y.Z -m "release vX.Y.Z" && git push origin main vX.Y.Z
```

## Covered Repositories

| Repository | Scope | Status |
|---|---|---|
| `STENIO-SENTINEL` | Self-test | ✅ Engine v4.0.0 |
| `ceduardorodrig` (CV) | `cv` | ✅ Passing |
| `WITH-SMOOTH-MOTION` | `all` | ✅ Passing |
| `MCMOJAVE-CURSOR-UNIFIED` | `all` | ✅ Passing |
| `KURURU-TAB3LITE-LINUX` | `all` | ✅ Passing |
| `MNEMOCINE` | `homelab` | ✅ Passing |
| `MNEMOCINE-CONFIGS` | `mirror` | ✅ Passing |
| `macrokey-driver` | `fork` | ✅ Passing |

### Handling Upstream Forks (`scope: fork`)

`macrokey-driver` is a Python-based fork of `nonatofabio/macrokey-driver` containing local hardware fixes. Running `--scope all` triggers numerous `ARCH-NO-PYTHON` errors. Third-party upstream code is exempt from strict Rust rewrites: `--scope fork` enforces security (`SEC-*`), documentation, and licenses while relaxing internal architectural rules.

## Security Controls

- The engine repository is **public** — downloading binaries requires no personal access tokens or deploy keys.
- Binaries are validated via **SHA256 checksum** prior to execution.
- Releases require passing `--self-test` and `--guardian` passes before publication.

## See Also

- [`../governance/release-policy.md`](../governance/release-policy.md) — SemVer release standards
- [`../governance/stenio/README.md`](../governance/stenio/README.md) — Engine architecture
