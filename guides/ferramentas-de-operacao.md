---
tags: [homelab, governance, stenio, tooling, rust, tutorial]
pending: []
---

# Operational Tooling — Single Source of Truth in Repository

How (and why) **all code executing under `/usr/local/bin`** resides in the **`MNEMOCINE-OPS`** repository (private — `github.com/ceduardorodrig/MNEMOCINE-OPS`), cloned at `/mnt/NVME_PCI/homelab/mnemocine-ops`, under `provisioning/`. Established **2026-09-29**; **moved out of the product repo `SUMAENIMA-HUB` on 2026-10-12** (the homelab is larger than the product running on it — see `backlog.md` HB-014). The `provisioning/` root is required by the `stenio --tools` engine.

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
| **`/usr/local/bin`** | **Strictly binaries and scripts deployed from `MNEMOCINE-OPS/provisioning/`** |

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

## Service Naming Convention (`hl-` prefix)

Canonized **2026-10-12**: every **Mnemocine infrastructure service** (a systemd unit — service
or timer — or a Docker/Compose service owned by the homelab) carries the **`hl-`** prefix
(*homelab*). The rule resolves three otherwise-colliding namespaces:

| Entities | Naming | Examples |
|---|---|---|
| **Mnemocine infrastructure services** | `hl-<role>` | `hl-config-backup.timer`, `hl-infer.service`, `hl-scryfall-mirror.timer` |
| **Hosts** | keep the **Tupi-Guarani** name | `psicopompo`, `kavure`, `kururu` |
| **SUMÆNIMÁ products** | keep the **brand** name | `sae-core_api`, `sae-edge_proxy`, `sumaenima-swarm.service` |
| **Upstream / third-party** | keep the vendor name | `ollama.service`, `punktfunk-host.service` |

The prefix lives on the **unit/service**, never on the **binary**: `hl-minecraft-status.service`
runs `/usr/local/bin/minecraft-status`; `hl-wol-relay.service` runs `/usr/local/bin/wol-relay`.
Renaming a unit is therefore **runtime-transparent** to the executable and to consumers that
reach it by port (Homepage `siteMonitor`, Prometheus targets).

> **Static enforcement** is shipped by `HOMELAB-NAMING-SERVICE` (2026-10-13); the dynamic
> counterpart is `stenio --reconcile` (the catalogue in [`../services-catalog.md`](../services-catalog.md)
> is the declaration it checks reality against).

### Fleet migration (HB-019, 2026-10-13)

| Host(s) | Before | After | Kind |
|---|---|---|---|
| kavure | `minecraft-status.service` | `hl-minecraft-status.service` | daemon (`:9095`) |
| kavure | `unbound-status.service` | `hl-unbound-status.service` | daemon (`:9097`) |
| psicopompo, kavure | `wol-relay.service` | `hl-wol-relay.service` | daemon (`:9096`) |
| ybytu | `wol-dispatcher.service` | `hl-wol-dispatcher.service` | daemon (`:9096`) |
| kavure, kuaray | `nic-power-tuning.service` | `hl-nic-power-tuning.service` | oneshot (boot) |
| ybytu | `tailscale-gro.service` | `hl-tailscale-gro.service` | oneshot (boot) |
| psicopompo | `docker-prune.{service,timer}` | `hl-docker-prune.{service,timer}` | oneshot + timer |
| psicopompo (user) | `homelab-sftp-mount.{service,timer}` | `hl-sftp-mount.{service,timer}` | oneshot + timer |
| psicopompo (user) | `rclone-mount.service` | `hl-rclone-mount.service` | daemon (FUSE) |

**Deliberately not prefixed** (not homelab infrastructure *services*):

- Templates / helpers with an instance or trigger namespace: `wol@<iface>.service` (NIC WoL
  persistence, enabled as `wol@eno1` / `wol@enp1s0`), `notify-backup-failure@<unit>.service`
  (referenced by `OnFailure=`), `hollyland-fix@.service` (udev-triggered, personal device).
- Host tuning helpers excluded from the catalogue: `tailscaled-wait.service`,
  `disable-acpi-spurious-wakeup.service`.
- SUMÆNIMÁ products and upstream/third-party units — see the table above.

## See Also

- [`stenio-ci-unificado.md`](stenio-ci-unificado.md) — Unified CI integration
- [`../backups/config-backup.md`](../backups/config-backup.md) — Host configuration mirroring
