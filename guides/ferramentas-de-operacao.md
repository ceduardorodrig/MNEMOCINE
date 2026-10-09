---
tags: [homelab, governance, stenio, tooling, rust, guides]
---

# Operational Tooling — Single Source of Truth in Repository

How (and why) **all code executing under `/usr/local/bin`** resides in `SUMAENIMA-HUB/provisioning/`. Established on **2026-09-29**.

## The Problem

Operational scripts previously lived **exclusively on individual hosts**, uncommitted to any version control repository:

- **Invisible to Quality Gates** — Stenio audits source code repositories, not external server filesystems;
- **No Git Diffs** — No audit trail or revision history existed to compare changes;
- **Unreviewed Mutations** — Modifying backup or system automation bypassed Pull Request reviews.

Measured historical incidents:

| Incident | Consequence |
|---|---|
| **`smart-metrics.py`** violated `ARCH-NO-PYTHON` across **3 nodes** | Remained undetected for weeks |
| **`scryfall-prefetch`** lived in `/tmp` | Purged during a reboot; mirror cache coverage was **frozen at 62% for ~1 month** |
| Corrupted **`scryfall-prefetch`** installation | Lack of version diffs masked the operational failure |

## The Standard Rule

| Location | Contents |
|---|---|
| **`provisioning/scripts/`** | Shell scripts and tool wrappers |
| **`provisioning/<crate>/`** | Rust operational tools (compiled and distributed as standalone binaries) |
| **`provisioning/systemd/`** | Systemd service units and timers |
| **`/usr/local/bin`** | **Strictly binaries and scripts deployed from `provisioning/`** |

> Applies across all 5 active nodes: psicopompo, kavure, kuaray, ybyra, ybytu.

## Operations Manual

```console
# List registered tools and host distribution
$ ./provisioning/scripts/install-homelab-tools.sh --list

# Audit hosts for unmanaged binaries (crucial governance command)
$ ./provisioning/scripts/install-homelab-tools.sh --audit
$ stenio --tools --path .        # Equivalent check via native StenioSentinel

# Install tools
$ ./provisioning/scripts/install-homelab-tools.sh smart-metrics
$ ./provisioning/scripts/install-homelab-tools.sh --host kavure --all
$ ./provisioning/scripts/install-homelab-tools.sh --uninstall
```

## Rust Tool Compilation and Distribution

Binaries are **compiled once on psicopompo** (the dedicated build node, per ADR-026) and distributed over SSH/SCP. Target hosts **do not require Rust toolchains installed**.

```
provisioning/<crate>/  ──cargo build──►  target/release/<tool>
                                              │
                               install-homelab-tools.sh (scp)
                                              ▼
                                    /usr/local/bin/<tool>
```

## Quality Gates

Three distinct governance layers prevent regressions:

| Gate Check | Scope of Detection |
|---|---|
| **`stenio --tools`** | Detects orphaned binaries in `/usr/local/bin` that are missing from the repository manifest |
| **`stenio --diff`** | Enforces codebase standards (no unbounded channels, no raw panics, no unwrap) |
| **`stenio --scope homelab`** | Validates homelab infrastructure documentation, mount flags, and compose integrity |

> **How `--tools` Operates:** Cross-references `/usr/local/bin` across cluster nodes against the manifest declared in `install-homelab-tools.sh`. Because the engine reads the installer script dynamically at runtime, the audit and installation targets never diverge.

## Documented Systemd Traps

Encountered and recorded to prevent silent failure recurrences:

| Directive | Observed Behavior | Remediation |
|---|---|---|
| `RuntimeMaxSec=` with `Type=oneshot` | Ignored by systemd with boot warning: *"has no effect in combination with Type=oneshot"*. | Implement execution timeouts inside the script wrapper |
| `Restart=` with `Type=oneshot` | Has no effect on oneshot units. | Use `Type=simple` for restartable daemons |
| `OnFailure=` pointing to missing unit template | Fails silently without notification. | Verify alert handler units (e.g. `notify-backup-failure@`) exist prior to referencing |
| `User=root` running SOPS decryption | The age private key is mode `0600` owned by user; root cannot access user home paths. | Set unit `User=` to the secret owner |

## Python Deprecation in Operations

The `ARCH-NO-PYTHON` invariant mandates replacing Python scripts with native Rust binaries for internal infrastructure:

| Legacy Script | Rust Native Replacement |
|---|---|
| `smart-metrics.py` (+ `.sh` driver) | Crate **`smart-metrics`** + versioned shell wrapper |
| `scryfall-prefetch` (`/tmp` Python script) | Crate **`scryfall-prefetch`** + systemd timer |
| `scryfall-sync` (`python3 -c json.load`) | Crate **`scryfall-sync`** |
| `zomboid-save` (87 lines of Python RCON) | Crate **`zomboid-ctl`** |

### Upstream Vendor Tools — `VENDOR_TOOLS` Manifest (2026-10-06)

Common CLI utilities (`bat`, `fd`, `ripgrep`) are installed via native package managers (pacman on Arch/CachyOS, apt on Ubuntu/Debian). However, five utilities lack native Ubuntu packages: `dust`, `procs`, `btm`, `ouch`, and `tokei`.

To prevent false-positive orphan reports in `stenio --tools`, the installer includes a `VENDOR_TOOLS` catalog specifying upstream precompiled binaries or `cargo:<crate>` sources. The engine parses this catalog dynamically, registering them as authorized third-party assets without requiring engine modifications.

### Shell Integrations — `zoxide` and `atuin`

CLI history and navigation hooks are registered in interactive shell configurations:
- **psicopompo (fish):** `~/.config/fish/config.fish` (`zoxide init fish | source` + `atuin init fish | source`).
- **kavure, kuaray, ybytu, ybyra (bash):** `~/.bashrc` (`eval "$(zoxide init bash)"`).

### Tailnet SSH Configuration (2026-10-06)

Host definitions in `~/.ssh/config` point strictly to **Tailnet IPs** (`100.66.224.34` for ybyra, `100.117.164.8` for ybytu) rather than public cloud interfaces, ensuring deterministic latency and avoiding external firewall rate-limits during `stenio --tools` cluster sweeps.

## See Also

- [`stenio-ci-unificado.md`](stenio-ci-unificado.md) — Unified CI integration
- [`../backups/config-backup.md`](../backups/config-backup.md) — Host configuration mirroring
