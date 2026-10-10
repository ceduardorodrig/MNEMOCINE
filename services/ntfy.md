---
tags: [homelab, service, ntfy, monitoring, ybytu]
---

# Ntfy

Push notification server. Runs on ybytu (Docker).

**Server:** ybytu

## Deployment

Config-as-code (Docker Compose) on ybytu: `/home/ubuntu/homelab/ntfy/compose.yml`.

```yaml
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    command: ["serve"]
    volumes: [ "./data:/etc/ntfy" ]
    ports: [ "8083:80" ]
    healthcheck: wget -q -O /dev/null http://127.0.0.1:80/v1/health
```

> ⚠️ **No custom `server.yml`** — ntfy operates using **defaults** (without auth/ACL). `./data` is currently empty.

## Access

- URL: `http://ybytu:8083` (MagicDNS) · `http://100.115.253.109:8083` · `http://ybytu.chimaera-heptatonic.ts.net:8083`
- Publish: `curl -d "msg" -H "Title: ..." http://ybytu:8083/<topic>`

## Topics (09/10/2026)

| Topic | Origin | Usage |
|---|---|---|
| **`backup`** | Backup automation scripts (config, restic, agentic-ai, docs-sync, n8n, monitoring, zomboid, valheim, sumaenima, miracena, rclone, scryfall, arandu) | **OK/FAILED** status reports for all scheduled backups |
| **`alerts`** | **Uptime Kuma** (~40 Down/Up monitors) **+ `alertmanager-ntfy`** (Prometheus/Alertmanager) **+ `arm-hunt`** | Service downtime + homelab alerts + ARM instance acquisition |
| `chimaera-heptatonic` | Changedetection.io | Webpage change notifications |
| ~~`uptimekuma`~~ | **Deprecated / unused** — Uptime Kuma publishes directly to **`/alerts`** (Option A, 08/10/2026) | — |

> **Active Mobile Subscriptions:** **`backup`** and **`alerts`** (`/alerts` consolidates uptime monitors and ARM notifications).

> **Topic contract & priority rules:** see [`notification-methodology.md`](../guides/notification-methodology.md) (priority = Android channel, anti-flap, who may publish where).

> **Unauthenticated Topics:** Any node on the tailnet can publish/subscribe. ntfy is **private to the tailnet** (bound to `0.0.0.0` but the host firewall/routing only exposes it across the tailnet). Consider provisioning a `server.yml` with authentication if further isolation is required.

## Integrations

- **ntfy mobile app** — Subscribe to **`backup`** (singular!) and **`alerts`**.
  In app: *Settings → Manage users → Add* → Server URL `http://ybytu.chimaera-heptatonic.ts.net:8083` (or via tailnet IP), then **Subscribe** to each topic.
- Uptime Kuma → ntfy **to `/alerts`** (configured as `ntfy (alerts)`), not `/uptimekuma`.
- **Prometheus/Alertmanager → ntfy via bridge `alertmanager-ntfy`** (09/10/2026):
  Alertmanager **does not support message templating** inside standard `webhook_configs` — pointing it directly to the topic posted **raw JSON payloads** without clean headers, polluting `/alerts`.
  The bridge container (`monitoring-alertmanager-ntfy` on kavure) formats alerts cleanly: title `🚨 Fired` / `✅ Resolved` + summary, priority by severity (`urgent` critical / `low` warning / `min` resolved), click action linking to graphs.
  Details in [`monitoring.md`](monitoring.md). Policy is canonical in [`notification-methodology.md`](../guides/notification-methodology.md).
- Changedetection.io → `ntfy://100.115.253.109:8083/chimaera-heptatonic`

> **Configuration Backup:** ybytu's `config-backup` mirrors `/home/ubuntu/homelab` (which includes `compose.yml`). The empty `./data` directory is **not** mirrored — if a `server.yml` is created, add its directory to `SRC_DIRS`.

## RAM Usage

~15 MB.
