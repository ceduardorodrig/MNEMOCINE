---
tags: [homelab, tutorial, docker, registry, psicopompo, storage]
---

# Docker Image Registry (Sumænimá)

Private image registry serving as the **single source of truth** for Docker Swarm service images. Hosted on **psicopompo** (the build node), accessible across the Tailnet with **TLS + authentication**.

## Rationale & Architecture

Docker's official documentation is clear ([Deploy a stack to a swarm](https://docs.docker.com/engine/swarm/stack-deploy/)):

> *"Because a swarm consists of multiple Docker Engines, **a registry is required** to distribute images to all of them."*

The symptom of operating without a centralized registry manifested during every deployment via the Docker CLI warning:

> `image X could not be accessed on a registry to record its digest. Each node will access X independently, possibly leading to **different nodes running different versions** of the image.`

**Consequence experienced on 2026-09-29:** `deploy-swarm.sh` failed to update the API container — the `:cpu` image had changed its contents while preserving the tag, and without a registry, Swarm could not detect the revision. A manual sequence of `docker save | ssh | docker load` + `--force` was required to recover.

## Topology

| Property | Value |
|---|---|
| Host | **psicopompo** (`100.82.51.112`) |
| Image | `registry:3` |
| Port | `5000/tcp` — **restricted to loopback + Tailnet only** (never `0.0.0.0`) |
| Storage | `/mnt/NVME_PCI/registry` (bind mount — requires single-replica constraint) |
| Configuration | `~/homelab/registry/compose.yml` |
| URL | `https://psicopompo.chimaera-heptatonic.ts.net:5000` |

## Security Model (Distribution Specs)

| Requirement | Implementation |
|---|---|
| **Mandatory TLS** | *"A production-ready registry **must** be protected by TLS"* — certificates provisioned via **`tailscale cert`** (Let's Encrypt, natively trusted across cluster nodes) |
| **Auth Requires TLS** | *"You cannot use authentication with schemes that send credentials in clear text"* — TLS is enforced ahead of htpasswd |
| **Bcrypt htpasswd** | `$2y$` bcrypt hash derived from the SOPS vault — `registry:3` strictly requires bcrypt |
| **Private Network Bind** | Bound exclusively to Tailnet and loopback interfaces (governed by [`network/ports.md`](../network/ports.md)) |

### Credential Storage in SOPS Vault (2026-09-29)

| Secret Item | Location |
|---|---|
| Username | `REGISTRY_USER` (`sae`) in SOPS store |
| Password | `REGISTRY_PASSWORD` in SOPS store |
| Bcrypt Hash | `auth/htpasswd` (permissions `0600`) — **derived artifact**, not source of truth |
| Authenticated Nodes | `~/.docker/config.json` on psicopompo, kavure, and ybyra |

The plaintext credential file `auth/registry-password.txt` **was removed on 2026-09-29** — credentials reside exclusively in the encrypted vault ([`guides/secrets-centralizados.md`](secrets-centralizados.md)). The `deploy-swarm.sh` script does not parse plaintext passwords: it relies on `--with-registry-auth` against pre-authenticated daemon nodes.

```console
# Read password from encrypted vault
$ /mnt/NVME_PCI/secrets/sops-decrypt.sh REGISTRY_PASSWORD

# Regenerate htpasswd on a new host (registry strictly requires bcrypt)
$ docker run --rm httpd:2-alpine htpasswd -Bbn "$REGISTRY_USER" "$REGISTRY_PASSWORD" \
    > ~/homelab/registry/auth/htpasswd && chmod 600 ~/homelab/registry/auth/htpasswd
```

> **Note:** `htpasswd` is not installed on psicopompo's base OS; generation uses the official `httpd:2-alpine` container.

## Operations

```console
# Check service status
$ docker compose -f ~/homelab/registry/compose.yml ps

# Health probe (protected registry returns 401 Unauthorized without credentials)
$ curl -s -o /dev/null -w '%{http_code}\n' https://psicopompo.chimaera-heptatonic.ts.net:5000/v2/     # 401
$ curl -s -u "sae:$(/mnt/NVME_PCI/secrets/sops-decrypt.sh REGISTRY_PASSWORD)" \
       https://psicopompo.chimaera-heptatonic.ts.net:5000/v2/_catalog                                  # list catalog

# Tag and publish an image
$ docker tag my-image:tag psicopompo.chimaera-heptatonic.ts.net:5000/my-image:tag
$ docker push psicopompo.chimaera-heptatonic.ts.net:5000/my-image:tag

# Login on a new node (securely piped from SOPS, never exposed in shell history)
$ /mnt/NVME_PCI/secrets/sops-decrypt.sh REGISTRY_PASSWORD \
    | docker login psicopompo.chimaera-heptatonic.ts.net:5000 -u sae --password-stdin
```

## Deployment Pipeline Integration

The `scripts/deploy-swarm.sh` script executes the following workflow:

1. Builds image using the registry-qualified repository tag (`$REG/sumaenima-server:cpu`);
2. Executes **`docker push`** to the local registry (eliminating manual `docker save | ssh | docker load` piping);
3. Triggers `docker stack deploy --with-registry-auth` — authentication digests propagate to worker nodes, enabling each daemon to pull image layers autonomously.

**Benefits:** Services reference container images **by immutable SHA256 digest** (preventing version drift across nodes), and node failover/rescheduling pulls layers on demand without requiring local cache pre-seeding.

### Exempt Images

- **`sumaenima-server:cuda`** (~4.3 GB): Built and executed exclusively on psicopompo to leverage its dedicated GPU — network transmission is avoided.
- Third-party images (`pgvector`, `valkey`, `tailscale`): Pulled directly from Docker Hub.

## Daemon Restart Resilience & Post-Mortem (2026-09-29)

**Incident:** During a system upgrade (`pacman -Syu`), package hooks triggered `systemctl restart docker.service` twice within 4 minutes. The Docker daemon exceeded systemd's shutdown timeout and received an unhandled `SIGKILL`. As a result, the registry container failed to restart (`Exited (2)`), despite having `restart: unless-stopped`. All other containers recovered; the registry remained offline, blocking subsequent `deploy-swarm.sh` builds.

**Root Cause:** CachyOS enforces a global default stop timeout: **`DefaultTimeoutStopSec=10s`** in `/usr/lib/systemd/system.conf.d/00-timeout.conf`. A Swarm-enabled Docker daemon frequently requires >10s to coordinate cluster state and unmount overlay networks before shutdown.

**Initial Incorrect Fix (Reverted 2026-10-02):** Enabling `live-restore` temporarily mitigated container restart delays but proved **fundamentally incompatible with Docker Swarm mode**:

```json
{ "live-restore": true }
```

> ⚠️ Docker official documentation states: *"The live restore option only pertains to standalone containers, and not to Swarm services"*. In Swarm mode, `dockerd` refuses to initialize: `failed to start cluster component: --live-restore daemon configuration is incompatible with swarm mode` ([moby/swarmkit#2381](https://github.com/moby/swarmkit/issues/2381)).

**Delayed Impact:** `dockerd` parses `daemon.json` only during startup. The configuration change was loaded via `systemctl reload` without restarting the process, leaving an unexploded configuration bomb that triggered during subsequent machine reboots:

| Host | Failure Date | Consequence |
|---|---|---|
| psicopompo (worker) | Reboot 2026-09-30 00:58 | Daemon offline for 2 days · Swarm worker unreachable |
| kavure (manager) | Reboot 2026-10-02 13:08 | Complete `sae-core` outage · `docker ps` socket unreachable |
| ybyra (edge node) | Averted | Config sanitized proactively on 2026-10-02 |

**Masked Failure Mode:** `live-restore` keeps child containers running when the daemon exits. On kavure, 33 orphan containers continued executing while `docker ps` reported `Cannot connect to the Docker daemon`, creating an illusion of partial service availability with zero control plane manageability.

**Correct Remediation (Applied 2026-10-02 across all nodes):**
1. Removed `live-restore` from `daemon.json`.
2. Increased service shutdown timeout via systemd drop-in override:

```ini
# /etc/systemd/system/docker.service.d/timeout.conf
[Service]
TimeoutStopSec=60s
```

Applied via `sudo systemctl daemon-reload`. Matches the drop-in timeout pattern established on kavure in `nfs-ordering.conf`.

**Manual Recovery Commands:**

```console
$ cd ~/homelab/registry && docker compose up -d
$ docker ps --filter name=registry --format '{{.Names}} | {{.Status}}'
$ curl -s -o /dev/null -w '%{http_code}\n' https://psicopompo.chimaera-heptatonic.ts.net:5000/v2/   # 401
```

## See Also

- [`guides/docker-log-rotation.md`](docker-log-rotation.md) — Logging configuration and Promtail compatibility
- [`network/ports.md`](../network/ports.md) — Canonical port allocations and bindings
