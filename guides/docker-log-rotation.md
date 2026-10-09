---
tags: [homelab, tutorial, docker, storage, kavure, psicopompo]
---

# Docker Log Rotation (Preventing Disk Exhaustion)

Canonical guide on container logging policy across the homelab — **why**, **where**, and **how to diagnose**. Created on 2026-09-29 after discovering **1.9 GB** of unrotated logs on kavure.

## The Problem

Docker defaults to the `json-file` logging driver **with no rotation enabled**. Official Docker documentation states ([Configure logging drivers](https://docs.docker.com/engine/logging/configure/)):

> *"Use the `local` logging driver to prevent disk-exhaustion. By default, **no log-rotation is performed**. As a result, log-files stored by the default `json-file` logging driver can cause a significant amount of disk space to be used for containers that generate much output, which can lead to **disk space exhaustion**."*

**Actual measurement on kavure (2026-09-29):** 1.9 GB unrotated logs, including:

| Container | Log Volume |
|---|---|
| `monitoring-cadvisor` | **870 MB** |
| `node-exporter` | **519 MB** |
| `monitoring-loki` | **380 MB** |

psicopompo had only 6 MB total.

## ⚠️ Infrastructure Invariant: Do NOT Use the `local` Driver

Docker docs recommend the `local` driver for automatic rotation. **However, doing so breaks homelab observability:** **Promtail** directly scrapes `/var/lib/docker/containers/*/*-json.log`. The `local` driver stores logs in an incompatible binary/protobuf format under different filenames, terminating container log ingestion.

**Therefore: We strictly maintain `json-file` + explicit rotation bounds.**

## Enforced Policy

### Layer 1 — Daemon Defaults (New Containers)

`/etc/docker/daemon.json` across **all 3 primary nodes** (psicopompo, kavure, ybyra):

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

> On psicopompo, existing keys (`data-root`, `runtimes`, `builder`) were merged via `jq` — never overwrite this file wholesale. Validate syntax with `dockerd --validate --config-file=/etc/docker/daemon.json`.
>
> ⚠️ Docker docs note: *"Existing containers **don't** use the new logging configuration automatically"* — only newly spawned containers inherit daemon changes. Hence Layer 2 is required.
>
> 🛑 **Golden Rule (2026-10-02):** When editing `daemon.json`, **never add `"live-restore": true`**. All 3 hosts are **Docker Swarm nodes**, and `live-restore` prevents `dockerd` from booting on system restarts (`failed to start cluster component … incompatible with swarm mode`). See [`AGENTS.md`](../AGENTS.md) § `live-restore` FORBIDDEN on Swarm hosts.

### Layer 2 — Per-Service Definitions (Immediate Effect)

Configured via the `logging:` stanza in Compose files:

| Target | File Path | Deployment Method |
|---|---|---|
| Monitoring stack (kavure) | `/srv/data/monitoring/compose.yml` | `docker compose up -d` |
| Node exporter (kavure) | `/srv/data/node-exporter/compose.yml` | `docker compose up -d` |
| Promtail (psicopompo) | `~/homelab/promtail/compose.yml` | `docker compose up -d` |
| Swarm services | `provisioning/stacks/{core,edge,gpu}.yml` | `docker stack deploy` |

Example Compose stanza:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## Diagnostics

```console
# Measure disk space consumed per log file (must run with root privileges)
$ sudo bash -c 'du -b /var/lib/docker/containers/*/*-json.log | sort -nr | head'

# Total directory size
$ sudo du -sh /var/lib/docker/containers

# Check rotation settings on a running container
$ docker inspect <container> --format '{{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}'
# Expected output: json-file map[max-file:3 max-size:10m]
```

**Immediate Non-Disruptive Log Truncation** (safe; Docker maintains the active file descriptor):

```console
$ sudo truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log
```

## 🐛 Promtail Ingestion Fix

Two silent bugs previously prevented Promtail from ingesting container logs:

| Issue | Previous Incorrect Value | Remediation |
|---|---|---|
| **Path Glob** | `*-log.json` | **`*-json.log`** (the actual naming convention of `json-file`) |
| **Mount Path** on psicopompo | `/var/lib/docker/containers` | `/mnt/NVME_PCI/docker-data/containers` (custom `data-root` location) |

Fixed in `~/homelab/promtail/promtail-config.yml` (psicopompo and kavure) and Compose manifests. Promtail logs now show `msg="tail routine: started"` across targets.

> A **persistent positions volume** (`/var/lib/promtail`) was also mounted. Without it, container restarts cause Promtail to re-read all log history from beginning-of-file, triggering Loki rejections with `400 entry too far behind`.

## See Also

- [`guides/docker-disk-cleanup.md`](docker-disk-cleanup.md) — Cache and image pruning
- [`guides/docker-containerd-cleanup-kavure.md`](docker-containerd-cleanup-kavure.md)
