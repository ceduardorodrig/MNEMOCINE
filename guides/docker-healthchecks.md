---
tags: [homelab, docker, monitoring, tutorial]
---

# Container Healthchecks (Homelab Standard)

**Rule:** Every Docker service must have an explicit **healthcheck** — enabling `autoheal` to restart unhealthy containers. The only documented exception is **distroless** images (which lack an internal shell), covered instead by an **external watchdog**.

## Standard Specification

```yaml
healthcheck:
  test:
    - CMD-SHELL
    - <command>
  interval: 60s
  timeout: 10s
  retries: 3
  start_period: 30s   # 40s for slower applications
```

Application rules:

- **Always test the check command INSIDE the container before applying** — listening ports, interface binds, and installed binaries vary by image (e.g., `glances` and `node-exporter` listen on the Tailnet IP rather than localhost; `wordpress`, `flaresolverr`, and `npm` only bundle `curl`; `crafty` only includes `bash`).
- Prefer `wget -q -O /dev/null <url>`; fall back to `curl -fsS -o /dev/null <url>` when wget is missing; use `nc -z 127.0.0.1 <port>` for TCP services without HTTP; `bash -c 'exec 3<>/dev/tcp/127.0.0.1/<port>'` as a last resort; and `valkey-cli ping` / `redis-cli ping` for key-value stores.
- Place the block **immediately after the `image:` key** in the service definition (a safe convention preventing multi-line indentation errors) and **validate the YAML syntax** (`docker compose config -q`) prior to redeploying.
- Create a backup copy of the compose file before editing (`*.bak-YYYYMMDD-healthcheck`).

## Exception: Distroless Containers → External Watchdog *(Historical Context)*

`dnscrypt-proxy` (kavure) ran on an image **without a shell** → it could not execute an in-container healthcheck. It was monitored by [`scripts/dns-watchdog`](../../scripts/dns-watchdog/) (Rust) via `hl-dns-watchdog.timer` (2 min) on kavure — covering frozen process states. **Since 2026-10-08**, dnscrypt-proxy is disabled, and the same watchdog monitors **native `unbound`** via `--service unbound` (systemd alone cannot detect a "running but unresponsive" daemon; the probe with a unique test label also catches broken upstream links).

## Coverage Status (2026-10-07)

| Host | With Healthcheck | Pending |
|---|---|---|
| **kavure** | 14 (monitoring, searxng, HA, navidrome, node-exporter, glances, dockerproxy, crafty, pihole…) + `unbound` via watchdog (10/08) + `sae-core_backup` (Swarm) | — (see orphaned task below) |
| **kuaray** | 16 (miracena-*, *arr, transmission, syncthing, glances, promtail, node-exporter, dockerproxy) | — |
| **ybytu** | 8 (adguardhome, changedetection, glances, promtail, node-exporter, ntfy, dockerproxy, homepage, uptime-kuma) | — |
| **ybyra** | 6 (glances, promtail, node-exporter, dockerproxy, edge proxy/tunnel, **umami** via Swarm) | — |
| **psicopompo** | 5 (registry, glances, promtail, node-exporter, dockerproxy) | — |

> **Swarm Services:** `sae-core_backup` and `sae-edge_umami` received healthchecks **inside the stack file** (`provisioning/stacks/{core,edge}.yml`) **and** via surgical `docker service update`.

> **Standardized `autoheal` (2026-10-07):** ybyra previously used `AUTOHEAL_CONTAINER_LABEL=autoheal` (only restarting containers with this label), meaning new healthchecks did **not** trigger restarts. It now uses `all`, matching the other 4 hosts, and received a managed `compose.yml` (`/home/ubuntu/homelab/autoheal/`).

### ⚠️ Identified Orphan: `sae-core_asciline`

The Swarm service `sae-core_asciline` (image `sumaenima-asciline-launch:latest`, port 8766, provisioned **2026-09-29**) **does not exist in the current `core.yml`** — it is a remnant of an earlier stack iteration (referred to in legacy docs as `n`/`sae-core_n`). It remains **without a healthcheck** until its final state is determined (removal, similar to `datavis`). It was left untouched during this pass.

> **Compose files created during this pass** (migrating former `docker run` commands): `dockerproxy` (ybytu, ybyra, psicopompo), `glances` (ybyra, psicopompo), `node-exporter` (psicopompo), and `adguardhome` (ybytu). All now adhere to config-as-code standards.

## Stenio Governance Enforcement (`INFRA-COMPOSE-HEALTHCHECK` Rule — 2026-10-07)

The governance engine contains a native sibling rule to `INFRA-COMPOSE-RESTART` (in `infra.rs` via `serde_yaml`): it iterates through `services:` and requires, **per service**, either a `healthcheck` **or** an explicit label exception for *distroless* images:

```yaml
    labels:
      homelab.healthcheck: watchdog
```

**Coverage:** The `homelab` scope audits the vault tree **and** the **NAS mirror** (`/mnt/BACKUP/configs-homelab`, maintained by `config-backup`) — without this, the rule would find no live compose files (the vault contains 0). Only **structural compose checks** run against the mirror (rules matching `SEC-*` are excluded on captured runtime configs), and `golden/` directories are ignored to prevent duplicate alerts. Mirror scanning triggers only when targeting the live vault (external `--path` checks do not sweep the NAS).

- **Severity:** `Warning` — non-blocking quality gate. Can be promoted to `Error` once all mirror copies are aligned and warning counts reach zero.
- **Status (2026-10-07, updated):** Dropped from ~60 → **30 warnings**. The root cause on psicopompo was identified and resolved: `config-backup` was previously mirroring `/mnt/NVME_PCI/homelab` (stale September copies lacking healthchecks) instead of `/home/edu/homelab` where live composes reside — see [`../backups/config-backup.md`](../backups/config-backup.md). Remaining warnings stem from **legacy/duplicate** stacks (`psicopompo/homelab/{autoheal,watchtower,winboat}` — services no longer hosted there), repo templates (`sumaenimahub/.../docker-compose.yml`), and images **natively embedding** `HEALTHCHECK` (e.g., `valheim`).
- **Validation:** Synthetic tests (`--path` external target) confirm the rule triggers **only** on services missing both `healthcheck` and the exemption label. `cargo test` 20/20, `--self-test` 60/60, `--guardian` zero integrity violations.

## Useful Commands

```bash
# Identify containers lacking a healthcheck
for c in $(docker ps --format '{{.Names}}'); do
  docker inspect --format '{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}NONE{{end}}' "$c"
done

# Check available probing binaries inside a container
docker exec <c> sh -c 'for b in wget curl nc bash; do command -v $b; done'
```
