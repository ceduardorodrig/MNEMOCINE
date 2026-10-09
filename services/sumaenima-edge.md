---
tags: [homelab, service, docker, compose, tailscale, ybyra]
---

# Sumænimá Hub — Edge (Stack `sae-edge`)

> Documentation of the **homelab operational boundary** for Sumænimá Hub Edge: ingress routing, stack topology, **failover mechanics** to kavure, and runbook insights from the **ybyra cloud rebuild** (08/10/2026). Application internals live in the `SUMAENIMA-HUB` repository (`docs/deployment.md`).

## Overview

Sumænimá Hub serves public ingress via **`https://sumaenima.chimaera-heptatonic.ts.net`** (Tailscale Funnel). Two coordinated Docker Swarm stacks deliver the service:

| Stack | Host | Services | Role |
|---|---|---|---|
| **`sae-core`** | kavure | api, db (Postgres), valkey, backup, **umami-db** | Core state & business logic |
| **`sae-edge`** | **ybyra** (Primary) | `proxy` (nginx), `tunnel` (Funnel), `umami` | Public edge ingress & telemetry |

```
Internet ──► Tailscale Funnel ("sumaenima" node) ──► Tunnel Container ──► proxy:80 (nginx)
                                                                           ├── /          → SPA (/var/www/sumaenima)
                                                                           ├── /api/      → sae-core_api (overlay)
                                                                           └── /umami/    → umami (edge)
```

## The `sae-edge` Stack

- **`proxy`** — Nginx (`nginx-sumaenima`). Binds port **80** in `mode: host`. Routes frontend SPA, `/api/` endpoints, and `/umami/`. Configuration via bind mount: `/home/ubuntu/homelab/sumaenima/nginx.conf`.
- **`tunnel`** — `tailscale/tailscale`. Registers node **`sumaenima`** and enables public **Funnel**. Tailscale daemon state **persists in the `tailscale-state` volume** (⚠️ see operational lessons).
- **`umami`** — Analytics engine (`sumaenima-umami:latest`).
- **`*-standby`** — Replicas provisioned **on kavure** (`node.labels.edge_backup == true`), defaulting to `replicas: 0` — activated exclusively during **failover events**.

> Scheduling constraints: `proxy`/`tunnel`/`umami` require `node.labels.role == primary` (currently **ybyra**); `-standby` variants require `edge_backup == true` (currently **kavure**).

## Edge Failover (Kavure Assumes Edge Ingress)

Validated on **08/10/2026**. On **Swarm Manager (kavure)**:

```bash
# 1) Scale standby online FIRST and verify health
docker service scale sae-edge_proxy-standby=1 sae-edge_tunnel-standby=1 sae-edge_umami-standby=1
curl -sI https://sumaenima-1.chimaera-heptatonic.ts.net    # Returns ~200

# 2) Scale down primary (ybyra)
docker service scale sae-edge_proxy=0 sae-edge_tunnel=0 sae-edge_umami=0
```

**Operational Nuances:**
- Standby registers node **`sumaenima-1`** (canonical name `sumaenima` belongs to primary) → **public URL drifts** during failover. For primary to reclaim canonical hostname, **purge obsolete `sumaenima*` nodes** in Tailscale admin console prior to launching tunnel.
- Standby requires a **valid, unexpired Tailscale auth key** (see [`network/tailscale.md`](../network/tailscale.md)).
- Registered tunnel nodes are not ephemeral by default → purge via Tailscale console after drills (or generate ephemeral auth keys).

## Deployment

`scripts/deploy-swarm.sh` (in `SUMAENIMA-HUB` repository on psicopompo) executes `set -a; source .env` and runs remote `docker stack deploy` targeting kavure. It builds `nginx-sumaenima` and `sumaenima-server` locally and pushes to the internal **registry** (`psicopompo…:5000`). `edge.yml` points to `psicopompo…:5000/nginx-sumaenima:latest`.

> ✅ **Resolved (08/10/2026):** `sumaenima-umami` **published to internal registry** (`sha256:1c05593d…`) and referenced in `edge.yml`; service spec updated via `docker service update --image …`.
>
> ✅ **Swarm Config Immutability:** Docker Swarm configs are **immutable** and require **versioned names** (Docker official guideline). `nginx-conf-standby` was renamed to **`nginx-conf-standby-20261008`** → `docker stack deploy` executed cleanly, bringing deployed configs into parity with source files (`sha256 862b195a…`). **Convention:** When updating config files, **bump the version/date suffix**.

## Operational Runbook Lessons: Ybyra Rebuild (08/10/2026)

Detailed procedure: [`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md). Key findings:

| Finding | Remediation & Impact |
|---|---|
| **Tailscale State in Volume** | The `sumaenima` node lived inside container volume `tailscale-state`. Rebuilding the host purges the state → tunnel re-registers and requires a valid **`TS_AUTH_KEY`**. |
| **`TS_AUTH_KEY` Freshness** | Stored service specs retained expired keys. Updated via `docker service update --env-rm/--env-add` to restore connectivity. |
| **Autoheal vs Slow Healthcheck** | ybyra's `autoheal` ran with `AUTOHEAL_CONTAINER_LABEL=all` and restarted Umami before its initial startup (~60s). **Fixed:** Extended `start_period` from **30s → 120s** in `edge.yml`. |
| **Registry Mirroring** | Published `sumaenima-umami` to central registry — ensuring host rebuilds pull cleanly without manual Docker builds. |
| **Swarm Config Drift** | Versioned names (`nginx-conf-standby-20261008`) deployed successfully. |
| **Recovery Efficiency** | Full teardown, rebuild, and restoration took ~1h while public ingress remained online (kavure failover). Enabled by: **mirrored configs**, **sops secret vault**, and **Swarm single-token rejoin**. |

## Key File Locations

| Asset | Path |
|---|---|
| Edge Stack Source | `SUMAENIMA-HUB/provisioning/stacks/edge.yml` |
| Core Stack Source | `SUMAENIMA-HUB/provisioning/stacks/core.yml` |
| Nginx Config (Primary) | `ybyra:/home/ubuntu/homelab/sumaenima/nginx.conf` |
| Frontend SPA Build | `ybyra:/var/www/sumaenima` (manual backup cadence) |
| Environment Secrets | sops store (`sops-decrypt.sh` → `sumaenima.env`) |
| Deployment Script | `SUMAENIMA-HUB/scripts/deploy-swarm.sh` |

## References

- [`servers/ybyra.md`](../servers/ybyra.md) · [`servers/kavure.md`](../servers/kavure.md)
- [`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md) — Host rebuild guide
- [`network/tailscale.md`](../network/tailscale.md) — Auth keys and Funnel mechanics
- [`guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) — sops secret store
