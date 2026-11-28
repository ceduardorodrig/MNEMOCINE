---
tags: [homelab, backup, config, automation, meta]
pending: []
---

# `homelab-docs-sync` — Public Documentation Repository Publisher (Vault → Public)

Publishes GitHub repositories whose **source of truth is the Obsidian vault**.
Unified execution engine (`homelab-docs-sync` script) leveraging **per-repository profiles**; superseded `mnemocine-docs-sync` on **06/10/2026** upon onboarding the curriculum-vitae pipeline.

| Public Repository | Vault Source | Working Clone | Stênio Gate Scope | Schedule |
|---|---|---|---|---|
| [`ceduardorodrig/MNEMOCINE`](https://github.com/ceduardorodrig/MNEMOCINE) | `agentic-ai/mnemocine` | `homelab/mnemocine` | `--scope homelab` | **04:45** |
| [`ceduardorodrig/ceduardorodrig`](https://github.com/ceduardorodrig/ceduardorodrig) | `agentic-ai/curriculum-vitae` | `homelab/ceduardorodrig` | `--scope cv` | **04:40** |

## Pipeline Architecture

```
Vault (Source of Truth)                       Working Tree Mirror               Public Destination
/mnt/NVME_PCI/agentic-ai/<proj>  ──rsync──>  /mnt/NVME_PCI/homelab/<repo>  ──git push──>  PUBLIC Repo
                                                                     │
                                                             StênioSentinel Gate
                                                               PRIOR to git push
```

> ⚠️ **Destinations are PUBLIC.** The Stênio quality gate executes **strictly before** any push: an accidentally leaked credential or private secret published here is compromised irreversibly.

| Component | Path |
|---|---|
| Script | `/usr/local/bin/homelab-docs-sync` (versioned in `MNEMOCINE-OPS/provisioning/scripts/`) |
| Systemd Units | `hl-mnemocine-docs-sync.{service,timer}` and `hl-ceduardorodrig-docs-sync.{service,timer}` (in `MNEMOCINE-OPS/provisioning/systemd/`) |
| Schedule | **04:40** (CV) and **04:45** (Mnemocine), daily, `Persistent=true`, **executes as user `edu`** |
| Logs | `~/.local/state/<repo>-docs-sync.log` + systemd journal |
| Telemetry & Alerts | ntfy `/backup` on gate failure or git push errors |

**Execution Window Rationale (04:40 / 04:45):** Both sync jobs execute **prior** to `config-backup` (05:00). Publishing documentation first ensures the private NAS mirror captures an **already reconciled** state rather than a mid-flight mutation. Staggered 5-minute intervals prevent resource contention.

## Unified Engine Architecture (Repository Profiles)

A `case` dispatcher at the head of `homelab-docs-sync` declares per repository: `VAULT_SRC`, `REPO_DST`, `SCOPE` (gate target), `EXCLUDES`, and commit message formatting. The core engine is unified — resolving a bug fixes all managed repositories simultaneously.

Profile exclusions are sensitive: `rsync --delete` purges files present only in the destination git tree. For **curriculum-vitae**, exclusions include `.git`, `.github` (repository CI), `.gitignore`, and `steniocheck.toml`. For **mnemocine**, exclusions additionally encompass `README.md`, `AGENTS.md`, `LICENSE*`, and secret file patterns.

## Execution as User `edu` (Non-Root)

Push operations authenticate via the **git credential store** (`~/.git-credentials`, permissions 0600, owner `edu`). The root user lacks these credentials, and invoking git as root in a user-owned repository corrupts file ownership metadata. The script requires zero administrative privileges: all target workspaces belong to `edu`.

## 🐛 Hard-Won Lessons & Non-Regression Rules

Five critical bugs resolved on 30/09/2026 and **guarded** within the unified engine:

| # | Bug | Consequence |
|---|---|---|
| 1 | **`rsync --delete` wiped `.github/`** | Destroyed the repository CI workflow protecting the push branch. `.github/` lives strictly in the git repo. |
| 2 | **Omission of `git pull`** | Pushes rejected by upstream — or worse, reintroduced pruned secrets. |
| 3 | **Generic `--path` gate validation** | Validated wrong scope; must target specific domain (`homelab` or `cv`). |
| 4 | **Logging to `/var/log`** | User `edu` lacks write permissions → failed at script initialization. |
| 5 | **Missing clean working tree guard** | Manual edits in the mirror were overwritten silently. |

## Workflow Steps

1. Enforces clean working tree (`git status --porcelain` empty) — aborts if dirty.
2. Performs `git fetch` and fast-forwards if behind `origin/main`.
3. Executes `rsync -a --delete` from vault → working clone, respecting profile exclusions.
4. **Mandatory Quality Gate:** `stenio --scope <scope> --path <repo> --strict` — any ERROR aborts execution and dispatches an alert to ntfy (warnings do not block). Without `--strict` the command exits 0 on errors. The clone directory must keep its queue name (`mnemocine`), otherwise the backlog and publication rules do not apply.
5. Stages changes: `git add -A`; exits cleanly if zero changes exist.
6. Commits: `docs(<repo>): auto-sync documentation updates (<timestamp>)` and pushes to GitHub.

### Publication guard (HB-089) — `MNEMOCINE-OPS` PR #29, installed on psicopompo 2026-11-27

For the `mnemocine` profile, `publication-guard` runs after step 5 and before the commit. It blocks changed files
whose path looks client-private, files marked `publish: false` or tagged `client`, and personal data (CPF, CNPJ,
+55 phone, `R$` amount, e-mail, proposal or confidential wording) that is not already public. It prints paths and
classes only, alerts on ntfy and restores the mirror clone; it fails closed. Install both files together:
`install-homelab-tools.sh --host psicopompo publication-guard homelab-docs-sync`. To publish a deliberate new
value, review it and commit it to the public repo by hand once; from then on it counts as already public.

Verified 2026-11-27 after the install: `--check` PASS, and a dry run on a throwaway clone of the mirror with the
current vault delta passed (`publication-guard: PASS files=35 findings=0`). Rollback:
`sudo install -m 0755 /usr/local/bin/homelab-docs-sync.prev-i1 /usr/local/bin/homelab-docs-sync`.

### Strict gate (GB-343) — `MNEMOCINE-OPS` PR #37, installed on psicopompo 2026-11-27

Verified 2026-11-27 on throwaway clones with a local bare remote: a planted `DOC-PUBLISH-OPEN-WEAKNESS` row blocked
the sync (nothing pushed, clone restored) and the current vault passed (0 errors). Regression test:
`provisioning/tests/docs-sync-strict-test.sh`. A reference from this folder to a file outside it does not resolve in
the published tree, so test a change on the mirror copy and not only on the vault. Rollback:
`sudo install -m 0755 /usr/local/bin/homelab-docs-sync.prev-o4 /usr/local/bin/homelab-docs-sync`.

## Operation

```bash
# Manual trigger
sudo systemctl start hl-ceduardorodrig-docs-sync.service
sudo systemctl start hl-mnemocine-docs-sync.service
systemctl status hl-ceduardorodrig-docs-sync.service -n 20

# Check timer schedule
systemctl list-timers 'hl-*-docs-sync.timer'

# Inspect logs
tail -30 ~/.local/state/ceduardorodrig-docs-sync.log
tail -30 ~/.local/state/mnemocine-docs-sync.log

# Dry-run rsync verification (non-destructive)
rsync -an --delete --exclude=.github --exclude=.gitignore --exclude=steniocheck.toml \
  /mnt/NVME_PCI/agentic-ai/curriculum-vitae/ /mnt/NVME_PCI/homelab/ceduardorodrig/
```

## Golden Rules

- **Never edit `/mnt/NVME_PCI/homelab/<repo>` manually.** It is strictly a build workspace; the Obsidian vault is the sole source of truth. Uncommitted changes abort syncs to protect unsaved work.
- **Never bypass the Stênio quality gate.** Repositories are public.
- **Secrets reside strictly in the SOPS vault** ([`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md)).
- **Software source code repositories are out of scope:** Standalone tools (`with-smooth-motion`, `macrokey-driver`, `mcmojave-cursor-unified`, `kururu-tab3lite-linux`, `mnemocine-acl`, `sumaenimahub`) maintain their primary source in their respective Git working trees. `homelab-docs-sync` governs documentation repositories exclusively.

## See also
- [`config-backup.md`](config-backup.md) — Private backup pipeline (NAS + private git)
- [`strategy.md`](strategy.md) — Comprehensive backup strategy
- [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) — Secret management
- [`../guides/stenio-ci-unificado.md`](../guides/stenio-ci-unificado.md) — CI pipeline for `MNEMOCINE`
