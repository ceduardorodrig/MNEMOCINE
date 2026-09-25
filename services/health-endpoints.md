---
tags: [homelab, service, steniobot, monitoring, docker, server, psicopompo, ybyra]
---

# Report: Topology and Monitoring Audit (Sumænimá INFRA)

> Status: **COMPLETED** — 2026-06-28
>
> ⚠️ **Post-migration (07/08/2026):** the core (`sae-core`) migrated from psicopompo to **kavure** (100.124.146.77). Uptime-Kuma monitor #50 now points to `http://100.124.146.77:9090/api/health` (Kavure - Sumænimá API). Monitor #49 (backup health) points to `http://100.124.146.77:9092/health`. See `services/steniobot.md` and `network/topology.md`.
>
> ✅ **29/08/2026 — "Sumænimá Backup" widget fixed:** the backup health server (`backup_health_server.py`, BaseHTTPRequestHandler) did not implement `do_HEAD` — **HEAD** probes from Homepage/Uptime Kuma got **501**, shown as an error on the dashboard. `do_HEAD` added (GET and HEAD → 200). Monitored endpoint: `http://100.124.146.77:9092/health` (kavure).

---

## 1. Resolved Problem: Fragile Naming (Ybyra vs Psicopompo)

The `Ybyra - Sumænimá API` monitor was renamed to `Ybyra - Proxy API (Externo)` because the API container (`sae-core_api`) and the database (`sae-core_db`) physically run on Psicopompo, not on Ybyra.

### What was done:

1. **Monitor #4 renamed**: `Ybyra - Sumænimá API` → `Ybyra - Proxy API (Externo)` — monitors API delivery via the Nginx proxy on Ybyra (`http://100.66.224.34/api/health`)
2. **Monitor #50 created**: `Kavure - Sumænimá API (Interno)` — monitors the physical health of the API on kavure over Tailscale (`http://100.124.146.77:9090/api/health`)
3. **Port 9090 published** on `sae-core_api` via `provisioning/stacks/core.yml` + `docker stack deploy` (it was only on the overlay network)
4. **ntfy notification** attached to the new monitor #50

---

## 2. Audit Findings on the 4 Nodes

### A. Psicopompo (Manager / Core)
| Item | Documented | Actual |
|------|-------------|------|
| API container | `steniobot_app` (standalone) | `sae-core_api` (Swarm service) |
| Port 9090 | Published | **Was overlay-only, has been published** ✅ |
| Portainer | Running | **Exited** (removed) |
| RustDesk (hbbs/hbbr) | Running | **No longer exists** |
| backup-sentinel | **Not documented** | New Swarm service (port 9092) |
| steniobot_vision/audio | **Not documented** | 2 standalone containers on the overlay |

### B. Ybyra (Edge / VPS)
- **Swarm role:** `primary` — Swarm worker node
- Nginx routes `/api/ → 100.124.146.77:9090` (kavure over Tailscale)
- API health via the proxy: `HTTP 200` ✅
- Datavis, Umami and Tailscale run as Swarm services

### C. Ybytu (Home Utility)
- Uptime Kuma: 41 monitors (not 37 as documented)
- Ntfy notification attached to ALL monitors ✅
- No critical discrepancies

### D. Kuaray (Standby / DR)
- 21 containers running as documented
- Swarm node with label `standby` (role not actively used)

---

## 3. Updated Documentation

| File | What was changed |
|---------|-------------------|
| `servers/psicopompo.md` | Swarm services, backup-sentinel, vision/audio added; Portainer/RustDesk removed |
| `servers/ybyra.md` | Swarm role `primary` added |
| `services/steniobot.md` | Swarm stack, vision/audio, recovery via stack deploy |
| `services/uptime-kuma.md` | 41 monitors, monitors #4 and #50 documented, edge/physical split |
| `services/health-endpoints.md` | This report |

## 4. Commands Executed

```bash
# 1. Publicar porta 9090
docker stack deploy -c provisioning/stacks/core.yml sae-core

# 2. Renomear monitor #4 no Uptime Kuma
sqlite3 kuma.db "UPDATE monitor SET name='Ybyra - Proxy API (Externo)' WHERE id=4;"

# 3. Criar monitor #50
sqlite3 kuma.db "INSERT INTO monitor (...) VALUES ('Psicopompo - Sumænimá API (Interno)', ...);"

# 4. Associar notificação
sqlite3 kuma.db "INSERT INTO monitor_notification (monitor_id, notification_id) VALUES (50, 1);"
```

## 5. Validation

- Local API health: `HTTP 200` ✅
- API health via Tailscale (100.124.146.77:9090): `HTTP 200` ✅
- API health via the Ybyra proxy: `HTTP 200` ✅
