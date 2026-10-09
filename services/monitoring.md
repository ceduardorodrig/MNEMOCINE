---
tags: [homelab, service, grafana, prometheus, loki, monitoring]
---

# Observability — Grafana + Prometheus + Loki

Central homelab monitoring and observability stack: host telemetry (node_exporter) + container metrics (cAdvisor) + storage metrics (SMART) + systemd units + backup freshness + log aggregation (promtail/Loki) + alerting (Alertmanager → **alertmanager-ntfy** → ntfy).

**Server:** kavure  
**Grafana:** `http://kavure.chimaera-heptatonic.ts.net:3002` (admin, credential `GRAFANA_ADMIN_PASSWORD` in sops store)  
**Prometheus:** `http://kavure.chimaera-heptatonic.ts.net:9091`  
**Loki:** `http://kavure.chimaera-heptatonic.ts.net:3100`  
**Alertmanager:** `http://kavure.chimaera-heptatonic.ts.net:9093`  

> **Deployment (28/08/2026):** Config-as-code located at `/srv/data/monitoring/`. Superseded legacy glances/homepage polling with enterprise telemetry. **Home dashboard:** `Homelab Health`.

## Stack (kavure)

| Container | Function | Host Port |
|---|---|---|
| monitoring-prometheus | Time-series metrics engine + alert rule evaluation | `9091` |
| monitoring-grafana | Visualization dashboards | `3002` |
| monitoring-loki | Multi-tenant log aggregation | `3100` |
| monitoring-promtail | Node log collector (kavure) | — |
| monitoring-cadvisor | Container resource metrics (kavure) | internal |
| monitoring-alertmanager | Routes firing alerts → **ntfy** (`/alerts`) | `9093` |

## Host Collectors (node_exporter Textfile Collector)

Custom metrics exported via the **textfile collector** (homelab standard — zero extraneous daemon containers; scripts execute via host systemd timers):

| Script (All Hosts) | Timer | Metrics Exported |
|---|---|---|
| `health-files-metrics.sh` | `hl-health-metrics.timer` (5 min) | `homelab_backup_last_ok_seconds`/`_age_seconds` (age of `/srv/health/*-last-ok` stamps) + `homelab_systemd_unit_active`/`_failed` (critical units: mnt-storage, tailscaled, docker, hl-* timers) |
| `container-metrics.sh` | `hl-container-metrics.timer` (2 min) | `homelab_container_state{name,state}` (running/restarting/exited/...) |
| `smart-metrics.sh` (psicopompo/kuaray/kavure — **physical disks only**) | `hl-smart-metrics.timer` (15 min) | `smartmon_smart_available`, `smartmon_health`, `smartmon_temperature_celsius`, `smartmon_{reallocated_sector_ct,current_pending_sector,offline_uncorrectable}_raw_value`, `smartmon_power_on_hours`, `smartmon_power_cycle_count`, `smartmon_load_cycle_count`, `smartmon_unsafe_shutdown_count`, `smartmon_udma_crc_error_count`, NVMe: `smartmon_nvme_{percentage_used,available_spare,media_errors,data_units_written,power_on_hours,unsafe_shutdowns}`, Non-SMART USB/SD cards: `smartmon_usb_ioerr_total`/`smartmon_usb_iorequest_total` |

> `smart-metrics.sh` invokes `smartctl -j` (JSON) + `smart-metrics.py` (parser). Cloud VPS nodes (ybytu/ybyra) do **not** support SMART (virtual disks).  
> Collector scripts output to `/var/lib/node-exporter/textfile/`; node_exporter on each host exposes them via `--collector.textfile.directory`.  
>  
> **Expanded (12/09):** Modern parser introduces `smartmon_smart_available` (suppressing false `health=0` alerts on devices lacking SMART controller hardware — such as SD cards on psicopompo connected via NORELSYS `0x2537:1081` USB card readers which **lack SMART support**), power-on hours/cycles, load cycles, unsafe shutdowns, UDMA CRC, and native NVMe telemetry. `smart-metrics.sh` detects USB storage lacking SMART and exports kernel I/O error counters (`/sys/block/*/device/ioerr_cnt`). **Seagate Firmware Bug:** `Power_On_Hours` raw value uses a multi-byte packed format — parser uses `power_on_time.hours` (top-level decoded field). Reference smartctl_exporter #108.

> **Human-Readable Labels (28/08):** Target `instance` labels across all jobs are **rewritten via relabeling** (`prometheus/prometheus.yml`) with the machine hostname — `psicopompo`, `kuaray`, `ybytu`, `ybyra`, `kavure`. Dashboards and alert notifications surface clean hostnames instead of `IP:port`. Adding new nodes requires appending the IP target with a corresponding relabel rule.

## Scrape Jobs

- **`node`** — node_exporter **across all 5 hosts** (`:9100`) + textfile metrics (health/systemd/container/smart)
- **`cadvisor`** — Container engine metrics on kavure
- **`n8n`** — `/metrics` endpoint on n8n
- **`prometheus`/`loki`/`grafana`/`alertmanager`** — Self-monitoring endpoints

## Logs (Loki)

- **promtail deployed on all 5 nodes** → Central Loki instance on kavure (`100.124.146.77:3100`). Each node appends `host=<hostname>` labels.
- **psicopompo:** promtail runs with `network_mode: host` (container bridge routing cannot traverse the tailnet through exit nodes).
- Ingestion rate limit: 32 MB/s (calibrated on 28/08 to ingest initial backlogs).

## Alerting (Prometheus → Alertmanager → alertmanager-ntfy → ntfy)

> **Webhook Bridge (09/10/2026):** Alertmanager originally posted directly to the ntfy `alerts` topic. Because Alertmanager's `webhook_configs` **does not support Go templating**, raw JSON payloads were posted directly without readable titles — creating noisy code dumps on mobile screens. The flow now routes: **Alertmanager → `alertmanager-ntfy`** (container `monitoring-alertmanager-ntfy`, image `ghcr.io/alexbakker/alertmanager-ntfy:1.2.1`, `http://alertmanager-ntfy:8000/hook`, internal compose network) → ntfy `/alerts`.  
> - **Config:** `/srv/data/monitoring/alertmanager-ntfy/config.yml` (Go templates: Title `🚨 Fired` / `✅ Resolved` + summary, body containing alert description, host, start time, `X-Click` pointing to generatorURL, priority `urgent`/`default`, tags `rotating_light`/`+1`).  
> - **Healthcheck:** Invokes native `--health-check` binary flag (runs in `scratch` image without shell).  
> - **End-to-End Validation (09/10):** Synthetic alert payload confirmed clean formatting in mobile `/alerts`.  
> - **Bridge Failure Failure-Domain:** If the bridge crashes, Alertmanager cannot dispatch (webhook returns 5xx) — inspect `docker logs monitoring-alertmanager-ntfy`.

| Alert | Condition | Severity |
|---|---|---|
| `NodeDown` | `up{job="node"}==0` for 5m | critical |
| `HighCPU` | CPU > 90% for 10m | warning |
| `DiskNearlyFull` | mount > 90% for 10m | warning |
| `InodeNearlyFull` | inodes > 90% for 10m | warning |
| `BackupNotRun` | backup health stamp age > 26h | critical |
| `SystemdUnitFailed` | critical systemd unit in failed state | critical |
| `SmartDiskError` | reallocated/pending/uncorrectable sectors > 0 | warning |
| `SmartDiskTemp` | disk temperature > 55°C | warning |
| `ContainerRestarting` | container in restarting state for 10m | warning |
| `n8nDown` / `PrometheusDown` | scrape target unreachable | critical |

> **Real Production Catches (28/08):** Upon initial deployment, the stack **immediately identified** (a) kuaray's HDD suffering 37 pending sectors (`SmartDiskError` firing) and (b) ybytu/ybyra config backups stalled for 7 days due to an NFS `Stale file handle` (`BackupNotRun`). Both remediated same-day.  
>  
> **Disk Failure Warning (12/09):** EXPANSION-2TB on psicopompo (`/dev/sdg`) actively degraded — reallocated sector count surged from 280 → 25,400 with 8 pending + 8 uncorrectable sectors emerging during ext4 formatting (forcing latent bad blocks to surface). smartd tracked normalized health dropping from 99 → 61 in real time. Drive marked dying; quarantined from holding primary data.  
>  
> **False Positives Remediated (09/10/2026):** (a) `n8nDown`/`PrometheusDown` fired every 4 hours because the Prometheus `n8n` job scraped the deprecated kavure target — Miracena stack (including n8n) moved to **kuaray** on 04/10; scrape target updated to `100.94.209.99:5678` (instance relabeled `kuaray`). (b) `BackupNotRun` on scryfall-mirror was false: The rewritten `scryfall-sync` Rust binary (29/09) omitted touching the health stamp — fixed via `ExecStartPost` in the systemd unit (see [`scryfall-mirror`](scryfall-mirror.md)).

## Long-Term Retention & Recording Rules (12/09)

- **Prometheus Retention:** Extended from `--storage.tsdb.retention.time=30d` → **365d** in `compose.yml`. TSDB footprint was ~1.9GB/30d → ~23GB/year (modest footprint stored on kavure NAS volume).  
- **Recording Rules** (`prometheus/rules.yml`): Group `smart-trends`, 1 data point per day per disk evaluated via `max_over_time[...24h]` hourly. Metrics: `smart:reallocated_sectors:max_1d`, `smart:pending_sectors:max_1d`, `smart:uncorrectable_sectors:max_1d`, `smart:temperature:max_1d`, `smart:power_on_hours:max_1d`, `smart:load_cycle_count:max_1d`, `smart:udma_crc_errors:max_1d`, `smart:nvme_percentage_used:max_1d`, `smart:nvme_media_errors:max_1d`, `smart:usb_ioerr:max_1d`.  
  - ⚠️ Recording rules reside in the SAME TSDB storage as raw metrics — bumping retention to 365d is mandatory to preserve historical trendlines.  
  - ⚠️ `max_over_time[24h]` only yields series after 24 continuous hours of data ingestion.

## Grafana Dashboards

- Provisioned Datasources: **Prometheus** (uid `prometheus`) + **Loki** (uid `loki`).  
- Provisioned Dashboards: **Homelab Health** (default landing page), **Node Exporter Full**, **Docker and system monitoring**, **SMART 1-Year Trend** (12/09).  
- **Homelab Health** (uid `homelab-health`): Hosts overview (CPU/RAM/load/uptime), Disks (storage + inodes), SMART health status, Backups (freshness age), Failed systemd units, Container health (restarting/running per node), CPU/RAM/Network/IO time series.  
- **SMART 1-Year Trend** (uid `smart-trends`): Daily aggregated series (`smart:*:max_1d`) for reallocated/pending sectors, thermals, power-on hours, NVMe % wear, and USB/SD I/O errors.  
- Authentication: `admin` + `GRAFANA_ADMIN_PASSWORD`. `GF_USERS_ALLOW_SIGN_UP=false`.

## Off-Box Backup (13/09/2026)

- **Destination:** NAS psicopompo `/mnt/BACKUP/monitoring-server-kavure/` (NFS export `100.124.146.77`, mounted at `/srv/data/monitoring/offbox` — fstab standard `soft,timeo=30,retrans=2`).  
- **Timer:** `hl-monitoring-backup.timer` (Daily at **05:15**) → `/usr/local/bin/monitoring-backup` (failsafe homelab standard: NFS reachability check → 3× retries → ntfy `/backup` → health stamp `/srv/health/monitoring-backup-last-ok`, tracked by `BackupNotRun`).  
- **Payload:** Prometheus TSDB snapshot (`POST /api/v1/admin/tsdb/snapshot` — requires `--web.enable-admin-api`, added 13/09) + rsync `--delete` of Loki and Grafana directories → `daily/{prometheus,loki,grafana}/`.  
- **⚠️ Active storage remains strictly LOCAL on kavure** (Docker volumes) — Official Prometheus documentation explicitly states **TSDB on NFS is unsupported** (causes irreversible database corruption). NFS is strictly a backup transit medium.

## Maintenance

- **Updates:** Kavure's Watchtower daemon manages image refreshes.  
- **Configuration:** Modify `/srv/data/monitoring/` and run `docker compose restart <service>` (Prometheus hot-reload: `POST /-/reload`).  
- **Add Alerts / Dashboards:** Modify `prometheus/alerts.yml` (+ reload) or `grafana/dashboards/` (JSON) and run `docker compose restart grafana`.  
- **Tune Retention / Rules:** Modifying `compose.yml` (`--storage.tsdb.retention.time`) requires recreating the container; `rules.yml` changes only require a reload.  
- **Mirrors:** Configs and dashboards are mirrored by `config-backup` (kavure `/srv/data` → NAS). `.env` is excluded (managed in sops secret store).

## See also
- [[n8n]] — Metrics scraped by Prometheus
- [[homepage]] — Grafana/Prometheus dashboard shortcuts in Kavure group
- [[backup-rituals]] — Monitored backup health stamps (28/08)