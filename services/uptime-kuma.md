---
tags: [homelab, service, uptime-kuma, monitoring, server, ybytu]
---

# Uptime Kuma

**Role:** Uptime monitoring with HTTP(S), TCP and Ping probes over Tailscale.

## Deployment

- **Server:** ybytu
- **Container:** `uptime-kuma`
- **Image:** `louislam/uptime-kuma:latest`
- **Port:** `3002` (bound to `0.0.0.0`)
- **Volume:** `uptime-kuma` → `/app/data`
- **Network:** `bridge`
- **Restart:** `unless-stopped`
- **Start command:**

```bash
docker run -d \
  --restart unless-stopped \
  -p 3002:3001 \
  -v uptime-kuma:/app/data \
  --cap-add=NET_RAW \
  louislam/uptime-kuma:latest
```

## Access

- **URL:** `http://ybytu.chimaera-heptatonic.ts.net:3002`
- **Login:** admin — the password is a **hash (bcrypt)** in SQLite (`kuma.db`), it **does not go into the sops store** (not reusable).
- **Password reset (28/08/2026):**
  ```bash
  docker exec -it uptime-kuma npm run reset-password
  ```
  (interactive; or `npm run reset-password -- --new_password='<nova>'`). Remove 2FA: `npm run remove-2fa`. See [Reset-Password-via-CLI](https://github.com/louislam/uptime-kuma/wiki/Reset-Password-via-CLI).

## Motivation

Oracle Cloud claims free VMs (AMD Free Tier) as long as average CPU usage stays below 20% and network below 20% for 7 consecutive days. Uptime Kuma was installed to generate real monitoring traffic (HTTP, TCP, Ping) via Tailscale for all homelab services, keeping the VMs active.

## Monitors

41 monitors configured directly in SQLite (`/app/data/kuma.db`), organized into 4 groups:

| Group | Count | Targets |
|---|---|---|
| Kavure | ~12 | Swarm sae-core (API, backup, Valkey), Games (Minecraft/Crafty, Zomboid, Valheim), Home Assistant, Pi-hole, Glances |
| Psicopompo | 4 | StênioREC, Glances, Ping, Syncthing |
| Ybytu | 7 | AdGuard, Homepage, Uptime Kuma, Filebrowser, Syncthing, Glances, Changedetection, Ntfy |
| Ybyra | 6 | Proxy API (external), SPA, Funnel, Umami, Datavis, Glances, Ping |
| Kuaray | ~5 | Standby mirror, Glances, Ping |

> **Migration history:** previously, Crafty/Minecraft and the API were on Psicopompo, and *arr/HA on Kuaray. After the consolidation on Kavure (08-09/2026), the service probes were remapped to their real hosts.

### Edge vs Physical Split

Every service monitor that goes through Ybyra's Nginx was renamed with a `Proxy` prefix to make clear it is the edge entry point, not the physical service:

| ID | Name | URL | What it monitors |
|---|---|---|---|
| 4 | Ybyra - Proxy API Sumænimá (Externo) | `http://100.66.224.34/api/health` | Nginx reverse proxy → API on kavure |
| 5 | Ybyra - Proxy Umami | `http://100.66.224.34/` | Nginx proxy → Umami on Ybyra |
| 15 | Ybyra - Proxy SPA Sumænimá | `http://100.66.224.34/` | Nginx proxy → SPA frontend |
| 48 | ~~Ybyra - Proxy Datavis Sumænimá~~ | ~~`http://100.66.224.34/api/datavis/health`~~ | ~~Nginx proxy → Datavis on Ybyra~~ **removed 22/09/2026 (legacy)** |
| 46 | Ybyra - Funnel Sumænimá | `https://sumaenima.chimaera-heptatonic.ts.net` | public Tailscale Funnel (HTTPS) |
| 50 | Psicopompo - Sumænimá API (Interno) | `http://100.124.146.77:9090/api/health` | API on kavure over Tailscale |

> ⚠️ **Finding (22/09/2026):** the `uptime-kuma` container was **recreated on 16/09** and the current DB (`~/homelab/uptime-kuma/data/kuma.db`) has **NO monitors at all** (empty `monitor` table, `sqlite_sequence` = 0, empty `/api/status-page/heartbeat/1` API). All monitors documented above (and the #48 datavis monitor) **were lost in the recreation**. The `uptime-kuma-data` docker volume (named) exists but is empty. **Pending:** rebuild the monitors in the panel (port 3002) or restore from an old backup — see [`services/monitoring.md`](monitoring.md) for the full list.

### Kernel Guard

The `pm_tailscale_funnel` driver (kernel) periodically checks:
- `edge.yml` has the correct `configs:` and `ports: 80`
- `serve.json` mounted via Docker Configs
- Funnel answers HTTPS 200
- Fails if any config is removed — prevents accidental loss of the funnel

## Notes

- Configured without Docker Compose (plain `docker run` command).
- Monitors were inserted via SQLite because Uptime Kuma does not expose a REST API for creation; it uses Socket.IO.
- The password's bcrypt hash got corrupted once by bash (`$` expansion); fixed by generating the hash inside the container via `node -e "bcrypt.hashSync(...)"`.
