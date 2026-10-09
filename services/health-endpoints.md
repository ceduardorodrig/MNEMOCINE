---
tags: [homelab, service, steniobot, monitoring, docker, server, psicopompo, ybyra]
---

# Topology & Monitoring Audit Report (Sumænimá INFRA)

> Status: **COMPLETED** — 2026-06-28
>
> ⚠️ **Post-Migration (07/08/2026):** The core stack (`sae-core`) migrated from psicopompo to **kavure** (100.124.146.77). Monitor #50 in Uptime-Kuma was updated to point to `http://100.124.146.77:9090/api/health` (Kavure - Sumænimá API). Monitor #49 (backup health) targets `http://100.124.146.77:9092/health`. See `services/steniobot.md` and `network/topology.md`.
>
> 🛑 **Monitor #50 BROKEN (verified 02/10/2026) — Port 9090 does not exist on host.**
> `docker service inspect sae-core_api` → `Endpoint.Ports: null`; `ss -ltn` on kavure reveals no 9090 binding; `curl http://100.124.146.77:9090/api/health` → **Connection refused**. Only edge proxy responds: `http://ybyra.chimaera-heptatonic.ts.net/api/health` → **200** (monitor #4 ✓).
>
> **Root Cause (git history of `sumaenima-hub`):** **No commit in `provisioning/stacks/core.yml` ever contained `9090:9090`** — only internal container healthchecks (`curl 127.0.0.1:9090`). The 07/08 binding (§`Port 9090 Published` below) was applied **out-of-band** via `docker service update --publish-add` and was subsequently **reverted** by a regular `docker stack deploy`, which reconciles running services to the compose file. Currently, `core.yml` publishes **only `9092` (backup) and `8766` (asciline)**.
>
> **Remediation Options (Pending Decision):**
> | Option | Method | Trade-off |
> |---|---|---|
> | **A** — Update monitor target | Point #50 to edge `…/api/health` (or rely on `:9092/health`) | Zero operational risk, but loses physical host-level probing on kavure |
> | **B** — Restore published port | Add `ports: ["9090:9090"]` to `core.yml` + execute `docker stack deploy` | Restores monitor #50 **and** direct Tailscale reachability, but exposes API outside overlay (violates minimal exposure policy: currently only edge reaches it) |
>
> ✅ **29/08/2026 — "Sumænimá Backup" Widget Fixed:** The backup health server (`backup_health_server.py`, BaseHTTPRequestHandler) did not implement `do_HEAD` — causing **HEAD** probes from Homepage/Uptime Kuma to receive **501**, flagged as an error on dashboards. Added `do_HEAD` support (GET and HEAD return 200). Monitored endpoint: `http://100.124.146.77:9092/health` (kavure).

---

## 1. Problem Resolved: Ambiguous Target Naming (Ybyra vs Psicopompo)

The monitor originally labeled `Ybyra - Sumænimá API` was renamed to `Ybyra - Proxy API (External)` because the API container (`sae-core_api`) and database (`sae-core_db`) run physically on the internal node, not on Ybyra.

### Actions Executed:

1. **Renamed Monitor #4**: `Ybyra - Sumænimá API` → `Ybyra - Proxy API (External)` — monitors API delivery through Nginx reverse proxy on Ybyra (`http://100.66.224.34/api/health`).
2. **Created Monitor #50**: `Kavure - Sumænimá API (Internal)` — monitors physical API health on kavure via Tailscale (`http://100.124.146.77:9090/api/health`).
3. **Published Port 9090** on `sae-core_api` via `provisioning/stacks/core.yml` + `docker stack deploy` (previously restricted strictly to overlay network).
4. **ntfy Notification Binding** attached to new monitor #50.

---

## 2. Four-Node Topology Audit Findings

### A. Psicopompo (Manager / Core)
| Item | Documented | Actual State |
|------|-------------|--------------|
| API Container | `steniobot_app` (standalone) | `sae-core_api` (Swarm service) |
| Port 9090 | Published | **Overlay-only, published manually** ✅ |
| Portainer | Running | **Exited** (decommissioned) |
| RustDesk (hbbs/hbbr) | Running | **Purged from node** |
| backup-sentinel | **Undocumented** | New Swarm service (port 9092) |
| steniobot_vision/audio | **Undocumented** | 2 standalone containers on overlay |

### B. Ybyra (Edge / VPS)
- **Swarm role:** `primary` — Swarm worker node
- Nginx routes `/api/ → 100.124.146.77:9090` (kavure over Tailscale)
- API health via reverse proxy: `HTTP 200` ✅
- Datavis, Umami, and Tailscale execute as Swarm services

### C. Ybytu (Home Utility)
- Uptime Kuma: 41 monitors configured
- ntfy notifications attached to ALL monitors ✅
- Zero critical deviations detected

### D. Kuaray (Standby / DR)
- 21 containers active as documented
- Swarm node with `standby` label (role dormant)

---

## 3. Updated Documentation

| File | Changes Made |
|---|---|
| `servers/psicopompo.md` | Added Swarm services, backup-sentinel, vision/audio; removed Portainer/RustDesk |
| `servers/ybyra.md` | Added Swarm `primary` role |
| `services/steniobot.md` | Documented Swarm stack, vision/audio workers, recovery via stack deploy |
| `services/uptime-kuma.md` | Documented 41 monitors, monitors #4 and #50, edge/physical segmentation |
| `services/health-endpoints.md` | This audit report |

## 4. Commands Executed

```bash
# 1. Publish port 9090
docker stack deploy -c provisioning/stacks/core.yml sae-core

# 2. Rename monitor #4 in Uptime Kuma
sqlite3 kuma.db "UPDATE monitor SET name='Ybyra - Proxy API (External)' WHERE id=4;"

# 3. Create monitor #50
sqlite3 kuma.db "INSERT INTO monitor (...) VALUES ('Psicopompo - Sumænimá API (Internal)', ...);"

# 4. Bind notification channel
sqlite3 kuma.db "INSERT INTO monitor_notification (monitor_id, notification_id) VALUES (50, 1);"
```

## 5. Validation

- Local API health check: `HTTP 200` ✅
- Direct API health via Tailscale (`100.124.146.77:9090`): `HTTP 200` ✅
- External API health via Ybyra proxy: `HTTP 200` ✅
