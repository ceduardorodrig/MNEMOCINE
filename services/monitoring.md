---
tags: [homelab, service, grafana, prometheus, loki, monitoring]
---

# Observabilidade — Grafana + Prometheus + Loki

Stack de monitoramento central do homelab: métricas de host (node_exporter) + containers + discos (SMART) + systemd + backups + logs (promtail/Loki) + alertas (Alertmanager → ntfy).

**Servidor:** kavure
**Grafana:** `http://kavure.chimaera-heptatonic.ts.net:3002` (admin, senha `GRAFANA_ADMIN_PASSWORD` no store sops)
**Prometheus:** `http://kavure.chimaera-heptatonic.ts.net:9091`
**Loki:** `http://kavure.chimaera-heptatonic.ts.net:3100`
**Alertmanager:** `http://kavure.chimaera-heptatonic.ts.net:9093`

> **Deploy (28/08/2026):** config-as-code em `/srv/data/monitoring/`. Substitui o uso "rudimentar" de glances + homepage como fonte de dados. **Home dashboard:** `Homelab Health`.

## Stack (kavure)

| Container | Função | Porta host |
|---|---|---|
| monitoring-prometheus | Time-series + alertas | `9091` |
| monitoring-grafana | Dashboards | `3002` |
| monitoring-loki | Log aggregation | `3100` |
| monitoring-promtail | Coleta logs do kavure | — |
| monitoring-cadvisor | Métricas de container (kavure) | interno |
| monitoring-alertmanager | Roteia alertas → **ntfy** (`/alerts`) | `9093` |

## Coletores nos hosts (textfile collector do node_exporter)

Métricas custom via **textfile collector** (padrão homelab — sem containers extras; os scripts rodam no host via timers):

| Script (todos os hosts) | Timer | Métricas |
|---|---|---|
| `health-files-metrics.sh` | `hl-health-metrics.timer` (5 min) | `homelab_backup_last_ok_seconds`/`_age_seconds` (idade dos `/srv/health/*-last-ok`) + `homelab_systemd_unit_active`/`_failed` (units críticas: mnt-storage, tailscaled, docker, hl-* timers) |
| `container-metrics.sh` | `hl-container-metrics.timer` (2 min) | `homelab_container_state{name,state}` (running/restarting/exited/...) |
| `smart-metrics.sh` (psicopompo/kuaray/kavure — **só discos físicos**) | `hl-smart-metrics.timer` (15 min) | `smartmon_smart_available`, `smartmon_health`, `smartmon_temperature_celsius`, `smartmon_{reallocated_sector_ct,current_pending_sector,offline_uncorrectable}_raw_value`, `smartmon_power_on_hours`, `smartmon_power_cycle_count`, `smartmon_load_cycle_count`, `smartmon_unsafe_shutdown_count`, `smartmon_udma_crc_error_count`, NVMe: `smartmon_nvme_{percentage_used,available_spare,media_errors,data_units_written,power_on_hours,unsafe_shutdowns}`, SD cards/USB sem SMART: `smartmon_usb_ioerr_total`/`smartmon_usb_iorequest_total` |

> `smart-metrics.sh` usa `smartctl -j` (JSON) + `smart-metrics.py` (parse). VPS (ybytu/ybyra) **não** têm SMART (discos virtuais).
> Os scripts escrevem em `/var/lib/node-exporter/textfile/`; o node_exporter de cada host expõe via `--collector.textfile.directory`.
>
> **Expandido (12/09):** novo parser adiciona `smartmon_smart_available` (corrige falso `health=0` de dispositivos sem SMART — SD cards do psicopompo via leitor USB NORELSYS `0x2537:1081`, que **não suportam SMART**), power-on hours/cycles, load cycles, unsafe shutdowns, UDMA CRC e métricas NVMe. `smart-metrics.sh` detecta dispositivos USB sem SMART e exporta os contadores de I/O error do kernel (`/sys/block/*/device/ioerr_cnt`). **Bug Seagate:** `Power_On_Hours` usa encoding multi-byte no `raw.value` do JSON — usar `power_on_time.hours` (top-level, já decodificado). Ver smartctl_exporter #108.

> **Labels amigáveis (28/08):** o `instance` de todos os jobs é **sobrescrito por relabeling** (`prometheus/prometheus.yml`) com o hostname — `psicopompo`, `kuaray`, `ybytu`, `ybyra`, `kavure` (jobs do kavure → `kavure`). Dashboards e alertas mostram os nomes em vez de `IP:porta`. Adicionar host: incluir o IP no alvo + regra de relabel correspondente.

## Métricas (scrape jobs)

- **`node`** — node_exporter **nos 5 hosts** (`:9100`) + textfile (health/systemd/container/smart)
- **`cadvisor`** — containers do kavure
- **`n8n`** — `/metrics` do n8n
- **`prometheus`/`loki`/`grafana`/`alertmanager`** — self

## Logs (Loki)

- **promtail nos 5 hosts** → Loki central do kavure (`100.124.146.77:3100`). Cada host rotula `host=<nome>`.
- **psicopompo:** promtail roda com `network_mode: host` (o bridge do container não roteia pro tailnet no exit node).
- Limite de ingestão: 32 MB/s (ajustado 28/08 p/ o backlog inicial).

## Alertas (Prometheus → Alertmanager → ntfy)

| Alerta | Condição | Severidade |
|---|---|---|
| `NodeDown` | `up{job="node"}==0` 5m | critical |
| `HighCPU` | CPU > 90% 10m | warning |
| `DiskNearlyFull` | mount > 90% 10m | warning |
| `InodeNearlyFull` | inodes > 90% 10m | warning |
| `BackupNotRun` | health file do backup > 26h | critical |
| `SystemdUnitFailed` | unit crítica em estado failed | critical |
| `SmartDiskError` | reallocated/pending/uncorrectable > 0 | warning |
| `SmartDiskTemp` | disco > 55°C | warning |
| `ContainerRestarting` | container em restarting 10m | warning |
| `n8nDown` / `PrometheusDown` | target down | critical |

> **Validação real (28/08):** ao subir, o sistema **já pegou** (a) o HDD do kuaray com 37 pending sectors (`SmartDiskError` firing) e (b) config-backup de ybytu/ybyra parado há ~7 dias por `Stale file handle` NFS (`BackupNotRun`). Ambos corrigidos no mesmo dia.
>
> **Alerta real (12/09):** EXPANSION-2TB (psicopompo, `/dev/sdg`) degradando ativamente — reallocated subiu de 280 → 25400 e surgiram 8 pending + 8 uncorrectable após a formatação ext4 (forçou remapeamento de setores ruins latentes). smartd reportou a queda do normalized 99→61 em tempo real. Disco em colapso; não usar para dados importantes.

## Longo prazo (12/09)

- **Retenção Prometheus:** `--storage.tsdb.retention.time=30d` → **365d** (`compose.yml`). TSDB era ~1.9GB/30d → ~23GB/ano (aceitável, volume no NAS do kavure).
- **Recording rules** (`prometheus/rules.yml`): grupo `smart-trends`, 1 ponto/dia/disco via `max_over_time[...24h]`, avaliado a cada 1h. Métricas: `smart:reallocated_sectors:max_1d`, `smart:pending_sectors:max_1d`, `smart:uncorrectable_sectors:max_1d`, `smart:temperature:max_1d`, `smart:power_on_hours:max_1d`, `smart:load_cycle_count:max_1d`, `smart:udma_crc_errors:max_1d`, `smart:nvme_percentage_used:max_1d`, `smart:nvme_media_errors:max_1d`, `smart:usb_ioerr:max_1d`.
  - ⚠️ Recording rules vivem no MESMO TSDB da retenção — o bump p/ 365d é obrigatório p/ histórico de longo prazo.
  - ⚠️ `max_over_time[24h]` só gera série após 24h de dados; as primeiras séries aparecem automaticamente.

## Grafana

- Datasources provisionados: **Prometheus** (uid `prometheus`) + **Loki** (uid `loki`).
- Dashboards provisionados: **Homelab Health** (home), **Node Exporter Full**, **Docker and system monitoring**, **Tendência SMART (1 ano)** (12/09).
- **Homelab Health** (uid `homelab-health`): Hosts (CPU/RAM/load/uptime), Discos (espaço+inodes), Saúde SMART, Backups (idade), Systemd failed, Containers (restarting/running por host), CPU/RAM/Rede/I/O (time series).
- **Tendência SMART (1 ano)** (uid `smart-trends`): séries diárias (`smart:*:max_1d`) de reallocated, pending, temperatura, power-on hours, NVMe % used e I/O errors USB/SD.
- Login: `admin` + `GRAFANA_ADMIN_PASSWORD`. `GF_USERS_ALLOW_SIGN_UP=false`.

## Backup off-box (13/09/2026)

- **Destino:** NAS psicopompo `/mnt/BACKUP/monitoring-server-kavure/` (export NFS `100.124.146.77`, mount `/srv/data/monitoring/offbox` — fstab padrão `soft,timeo=30,retrans=2`).
- **Timer:** `hl-monitoring-backup.timer` (diário **05:15**) → `/usr/local/bin/monitoring-backup` (padrão failsafe homelab: reachability NFS → retry 3× → ntfy `/backup` → health file `/srv/health/monitoring-backup-last-ok`, coberto pelo alerta `BackupNotRun`).
- **Conteúdo:** snapshot do TSDB do Prometheus (`POST /api/v1/admin/tsdb/snapshot` — requer `--web.enable-admin-api`, adicionado 13/09) + rsync `--delete` de Loki e Grafana → `daily/{prometheus,loki,grafana}/`.
- **⚠️ Storage ativo fica LOCAL no kavure** (volumes Docker) — doc oficial do Prometheus **NÃO suporta TSDB em NFS** (corrupção irreversível). NFS é só backup.

## Manutenção

- **Update:** watchtower do kavure gerencia as imagens.
- **Config:** editar em `/srv/data/monitoring/` e `docker compose restart <serviço>` (Prometheus: `POST /-/reload`).
- **Adicionar alerta/dashboard:** editar `prometheus/alerts.yml` (+ reload) / `grafana/dashboards/` (JSON) e `docker compose restart grafana`.
- **Mudar retenção/regras:** `compose.yml` (`--storage.tsdb.retention.time`) exige recrear o container; `rules.yml` só precisa de reload.
- **Espelho:** configs e dashboards espelhados pelo `config-backup` (kavure `/srv/data` → NAS). `.env` excluído (segredo no store).

## See also
- [[n8n]] — métricas consumidas pelo Prometheus
- [[homepage]] — atalhos Grafana/Prometheus no grupo Kavure
- [[backup-rituals]] — health files de backup monitorados (28/08)