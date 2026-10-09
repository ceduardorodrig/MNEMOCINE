---
tags: [homelab, cold-storage, docker, tutorial]
---

# Service Cold Storage (Homelab)

**Methodology** for **freezing** a homelab service: the service stops running, but remains preserved as a fully recoverable artifact — **prevented from accidental startup**, **included in automated backups**, and with a **verified rollback procedure**. Distinct from vault project cold storage (which archives directories into `.tar.gz`), service cold storage targets **native Docker services** requiring revival in minutes.

> Established on **2026-10-08** with `dnscrypt-proxy` on kavure, superseded by native recursive [`unbound`](../services/unbound.md).

## Definition of "Frozen" State

A service qualifies for cold storage only when **all six conditions** are satisfied:

1. **`cold` profile in Compose** — routine invocations (`docker compose up -d`, Watchtower, human operators) **ignore** services without active profiles;
2. **`restart: "no"`** in Compose **and** `docker update --restart=no <container>` applied to the running/stopped container (restart policies are written to container state, not just YAML);
3. **Container stopped** (`exited`);
4. **Proven Fail-Closed Design** — if started accidentally, the container **fails to bind or execute** (see below);
5. **Verified Backup** — service directory is included in NAS config synchronization;
6. **Documentation Tagged ⛔** — the service documentation page specifies cold-storage status and explicit reactivation commands.

## Freezing Checklist

```bash
# 1. Back up Compose manifest before modifications
cp compose.yml compose.yml.bak-YYYYMMDD-cold

# 2. Edit Compose: append to service definition:
#      profiles: ["cold"]
#      restart: "no"
#    Verify default operations exclude the service:
docker compose config --services                # MUST NOT list the service
docker compose --profile cold config --services # MUST list the service

# 3. Update existing container state
docker update --restart=no <container>
docker stop <container>
docker inspect -f '{{.HostConfig.RestartPolicy.Name}} {{.State.Status}}' <container>
# Expected output: no exited

# 4. PROVE fail-closed behavior (do not assume!):
docker start <container>                         # Intentionally attempt restart
#  → Verify primary service remains healthy (e.g. ss -ulnp | grep 5053 = unbound)
#  → Verify container logs report bind failure / port conflict
#  → Verify container enters exited state with NO restart crash-loop (restart=no)
docker stop <container>                          # Return to cold state

# 5. VERIFY backup coverage:
systemctl start hl-config-backup.service         # Trigger immediate sync
ls /mnt/BACKUP/configs-homelab/<host>/data/<service>/

# 6. Document service status in the service catalog
```

**Fail-Closed Architecture** serves as the second line of defense: even if steps 1–3 are bypassed, the frozen service cannot operate. In the case of `dnscrypt-proxy`, native `unbound` binds to `0.0.0.0:5053` and `127.0.0.1:5053`. If dnscrypt-proxy starts, it logs `[FATAL] ... bind: address already in use`, exits with code 255, and remains stopped without looping.

## Rollback (Reactivation)

```bash
# 1. Stop replacement service if conflicting (e.g. unbound):
systemctl stop unbound

# 2. Revert watchdog probes pointing to successor service:
#    e.g. hl-dns-watchdog.service → --container <container> instead of --service unbound

# 3. Reactivate with explicit cold profile
cd /srv/data/<service> && docker compose --profile cold up -d

# 4. Re-enable persistent restart policy if desired
docker update --restart=unless-stopped <container>
```

After testing, re-freeze following the checklist to restore `profiles: ["cold"]`.

## Backup & Maintenance Routines

| Routine | Coverage Details |
|---|---|
| `hl-config-backup.timer` (05:00) | `SRC_DIRS` synchronizes the **entire service directory** (compose files, `.bak` copies, configurations) to `/mnt/BACKUP/configs-homelab/` — see [`../backups/config-backup.md`](../backups/config-backup.md) |
| Restic + Snapper | NAS mirror is snapshotted and versioned (protection against deletion/corruption) |
| Watchtower | **Bypasses container**: default filters exclude stopped containers, and profiles hide the service |
| Autoheal | **Bypasses container**: monitors running containers only |

## Cold Storage Service Catalog

| Service | Host | Date Frozen | Successor | Reactivation | Documentation |
|---|---|---|---|---|---|
| `dnscrypt-proxy` | kavure | 2026-10-08 | Native `unbound` (`:5053`) | `docker compose --profile cold up -d` | [`../services/dnscrypt-proxy.md`](../services/dnscrypt-proxy.md) |

## See Also

- [`../services/dnscrypt-proxy.md`](../services/dnscrypt-proxy.md) — Reference implementation
- [`../services/unbound.md`](../services/unbound.md) — Recursive DNS resolver
- [`docker-healthchecks.md`](docker-healthchecks.md) — Rust watchdog and healthcheck standards
- [`../backups/config-backup.md`](../backups/config-backup.md) — Configuration backup strategy
