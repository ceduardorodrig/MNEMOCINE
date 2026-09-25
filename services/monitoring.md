---
tags: [homelab, service, grafana, prometheus, loki, monitoring]
---

# Observability — Grafana + Prometheus + Loki

Central homelab monitoring stack: host metrics (node_exporter) + containers + disks (SMART) + systemd + backups + logs (promtail/Loki) + alerts (Alertmanager → ntfy).

**Server:** kavure
**Grafana:** `http://kavure.chimaera-heptatonic.ts.net:3002` (admin, password `GRAFANA_ADMIN_PASSWORD` in the sops store)
**Prometheus:** `http://kavure.chimaera-heptatonic.ts.net:9091`
**Loki:** `http://kavure.chimaera-heptatonic.ts.net:3100`
**Alertmanager:** `http://kavure.chimaera-heptatonic.ts.net:9093`

> **Deploy (28/08/2026):** config-as-code in `/srv/data/monitoring/`. Replaces the "rudimentary" use of glances + homepage as the data source. **Home dashboard:** `Homelab Health`.

## Stack (kavure)

| Container | Role | Host port |
|---|---|---|
| monitoring-prometheus | Time-series + alerts | `9091` |
| monitoring-grafana | Dashboards | `3002` |
| monitoring-loki | Log aggregation | `3100` |
| monitoring-promtail | Collects kavure logs | — |
| monitoring-cadvisor | Container metrics (kavure) | internal |
| monitoring-alertmanager | Routes alerts → **ntfy** (`/alerts`) | `9093` |

## Collectors on the hosts (node_exporter textfile collector)

Custom metrics via the **textfile collector** (homelab standard — no extra containers; the scripts run on the host via timers):

| Script (all hosts) | Timer | Metrics |
|---|---|---|
| `health-files-metrics.sh` | `hl-health-metrics.timer` (5 min) | `homelab_backup_last_ok_seconds`/`_age_seconds` (age of the `/srv/health/*-last-ok` files) + `homelab_systemd_unit_active`/`_failed` (critical units: mnt-storage, tailscaled, docker, hl-* timers) |
| `container-metrics.sh` | `hl-container-metrics.timer` (2 min) | `homelab_container_state{name,state}` (running/restarting/exited/...) |
| `smart-metrics.sh` (psicopompo/kuaray/kavure — **physical disks only**) | `hl-smart-metrics.timer` (15 min) | `smartmon_smart_available`, `smartmon_health`, `smartmon_temperature_celsius`, `smartmon_{reallocated_sector_ct,current_pending_sector,offline_uncorrectable}_raw_value`, `smartmon_power_on_hours`, `smartmon_power_cycle_count`, `smartmon_load_cycle_count`, `smartmon_unsafe_shutdown_count`, `smartmon_udma_crc_error_count`, NVMe: `smartmon_nvme_{percentage_used,available_spare,media_errors,data_units_written,power_on_hours,unsafe_shutdowns}`, SD cards/USB without SMART: `smartmon_usb_ioerr_total`/`smartmon_usb_iorequest_total` |

> `smart-metrics.sh` uses `smartctl -j` (JSON) + `smart-metrics.py` (parse). VPSes (ybytu/ybyra) have **no** SMART (virtual disks).
> The scripts write to `/var/lib/node-exporter/textfile/`; each host's node_exporter exposes them via `--collector.textfile.directory`.
>
> **Extended (12/09):** the new parser adds `smartmon_smart_available` (fixes the false `health=0` for devices without SMART — psicopompo's SD cards via a NORELSYS `0x2537:1081` USB reader, which **do not support SMART**), power-on hours/cycles, load cycles, unsafe shutdowns, UDMA CRC and NVMe metrics. `smart-metrics.sh` detects USB devices without SMART and exports the kernel's I/O error counters (`/sys/block/*/device/ioerr_cnt`). **Seagate bug:** `Power_On_Hours` uses multi-byte encoding in the JSON's `raw.value` — use `power_on_time.hours` (top-level, already decoded). See smartctl_exporter #108.

> **Friendly labels (28/08):** the `instance` of all jobs is **overridden by relabeling** (`prometheus/prometheus.yml`) with the hostname — `psicopompo`, `kuaray`, `ybytu`, `ybyra`, `kavure` (kavure's jobs → `kavure`). Dashboards and alerts show names instead of `IP:porta`. Adding a host: include the IP in the target + the matching relabel rule.

## Metrics (scrape jobs)

- **`node`** — node_exporter **on the 5 hosts** (`:9100`) + textfile (health/systemd/container/smart)
- **`cadvisor`** — kavure's containers
- **`n8n`** — n8n's `/metrics`
- **`prometheus`/`loki`/`grafana`/`alertmanager`** — self

## Logs (Loki)

- **promtail on the 5 hosts** → kavure's central Loki (`100.124.146.77:3100`). Each host labels `host=<nome>`.
- **psicopompo:** promtail runs with `network_mode: host` (the container bridge does not route to the tailnet on the exit node).
- Ingestion limit: 32 MB/s (tuned on 28/08 for the initial backlog).

## Alerts (Prometheus → Alertmanager → ntfy)

| Alert | Condition | Severity |
|---|---|---|
| `NodeDown` | `up{job="node"}==0` 5m | critical |
| `HighCPU` | CPU > 90% 10m | warning |
| `DiskNearlyFull` | mount > 90% 10m | warning |
| `InodeNearlyFull` | inodes > 90% 10m | warning |
| `BackupNotRun` | backup health file > 26h | critical |
| `SystemdUnitFailed` | critical unit in failed state | critical |
| `SmartDiskError` | reallocated/pending/uncorrectable > 0 | warning |
| `SmartDiskTemp` | disk > 55°C | warning |
| `ContainerRestarting` | container restarting for 10m | warning |
| `n8nDown` / `PrometheusDown` | target down | critical |

> **Real validation (28/08):** on startup the system **already caught** (a) kuaray's HDD with 37 pending sectors (`SmartDiskError` firing) and (b) ybytu/ybyra's config-backup stopped for ~7 days due to an NFS `Stale file handle` (`BackupNotRun`). Both fixed the same day.
>
> **Real alert (12/09):** EXPANSION-2TB (psicopompo, `/dev/sdg`) actively degrading — reallocated went from 280 → 25400 and 8 pending + 8 uncorrectable appeared after the ext4 formatting (it forced a remap of latent bad sectors). smartd reported the normalized drop 99→61 in real time. The disk is failing; do not use it for important data.

## Long term (12/09)

- **Prometheus retention:** `--storage.tsdb.retention.time=30d` → **365d** (`compose.yml`). The TSDB was ~1.9GB/30d → ~23GB/year (acceptable, volume on kavure's NAS).
- **Recording rules** (`prometheus/rules.yml`): group `smart-trends`, 1 point/day/disk via `max_over_time[...24h]`, evaluated every 1h. Metrics: `smart:reallocated_sectors:max_1d`, `smart:pending_sectors:max_1d`, `smart:uncorrectable_sectors:max_1d`, `smart:temperature:max_1d`, `smart:power_on_hours:max_1d`, `smart:load_cycle_count:max_1d`, `smart:udma_crc_errors:max_1d`, `smart:nvme_percentage_used:max_1d`, `smart:nvme_media_errors:max_1d`, `smart:usb_ioerr:max_1d`.
  - ⚠️ Recording rules live in the SAME TSDB as the retention — the bump to 365d is mandatory for long-term history.
  - ⚠️ `max_over_time[24h]` only produces a series after 24h of data; the first series appear automatically.

## Grafana

- Provisioned datasources: **Prometheus** (uid `prometheus`) + **Loki** (uid `loki`).
- Provisioned dashboards: **Homelab Health** (home), **Node Exporter Full**, **Docker and system monitoring**, **SMART Trend (1 year)** (12/09).
- **Homelab Health** (uid `homelab-health`): Hosts (CPU/RAM/load/uptime), Disks (space+inodes), SMART Health, Backups (age), Systemd failed, Containers (restarting/running per host), CPU/RAM/Network/I/O (time series).
- **SMART Trend (1 year)** (uid `smart-trends`): daily series (`smart:*:max_1d`) of reallocated, pending, temperature, power-on hours, NVMe % used and USB/SD I/O errors.
- Login: `admin` + `GRAFANA_ADMIN_PASSWORD`. `GF_USERS_ALLOW_SIGN_UP=false`.

## Off-box backup (13/09/2026)

- **Destination:** psicopompo NAS `/mnt/BACKUP/monitoring-server-kavure/` (NFS export `100.124.146.77`, mount `/srv/data/monitoring/offbox` — standard fstab `soft,timeo=30,retrans=2`).
- **Timer:** `hl-monitoring-backup.timer` (daily **05:15**) → `/usr/local/bin/monitoring-backup` (homelab failsafe standard: NFS reachability → retry 3× → ntfy `/backup` → health file `/srv/health/monitoring-backup-last-ok`, covered by the `BackupNotRun` alert).
- **Content:** snapshot of the Prometheus TSDB (`POST /api/v1/admin/tsdb/snapshot` — requires `--web.enable-admin-api`, added 13/09) + rsync `--delete` of Loki and Grafana → `daily/{prometheus,loki,grafana}/`.
- **⚠️ Active storage stays LOCAL on kavure** (Docker volumes) — the official Prometheus docs **DO NOT support a TSDB on NFS** (irreversible corruption). NFS is for backup only.

## Maintenance

- **Update:** kavure's watchtower manages the images.
- **Config:** edit in `/srv/data/monitoring/` and `docker compose restart <serviço>` (Prometheus: `POST /-/reload`).
- **Add alert/dashboard:** edit `prometheus/alerts.yml` (+ reload) / `grafana/dashboards/` (JSON) and `docker compose restart grafana`.
- **Change retention/rules:** `compose.yml` (`--storage.tsdb.retention.time`) requires recreating the container; `rules.yml` only needs a reload.
- **Mirror:** configs and dashboards mirrored by `config-backup` (kavure `/srv/data` → NAS). `.env` excluded (secret in the store).

## See also
- [[n8n]] — metrics consumed by Prometheus
- [[homepage]] — Grafana/Prometheus shortcuts in the Kavure group
- [[backup-rituals]] — monitored backup health files (28/08)
