---
tags: [homelab, service, wake-on-lan, wol, power, psicopompo, kavure]
---

# Wake-on-LAN Relay

Lightweight service that wakes servers remotely via Magic Packet (WoL), reachable over Tailscale.

**Server:** kavure / psicopompo

## Stack

| Component | Technology |
|---|---|
| HTTP server | Python `http.server` (homelab standard) |
| WoL CLI | `wakeonlan` (perl, Arch extra / Ubuntu apt) |
| Systemd | `wol-relay.service` |
| Security | Tailscale ACL (only tailnet hosts can reach it) |
| Port | `9096` |

## Architecture

```
ybytu (Homepage:3001)
  ├─ "Ligar Kavure"     → Tailscale → psicopompo:9096/wake → wakeonlan <MAC-kavure>
  └─ "Ligar Psicopompo" → Tailscale → kavure:9096/wake     → wakeonlan <MAC-psicopompo>
```

Each host runs a relay that wakes the **other** host on the local LAN.

## Hosts and MACs

| Host | Interface | MAC | Tailscale IP | Relay wakes |
|---|---|---|---|---|
| psicopompo | `eno1` | `d0:94:66:de:8b:58` | `100.82.51.112` | kavure |
| kavure | `enp1s0` | `d0:94:66:ad:f3:c4` | `100.124.146.77` | psicopompo |

## Files

| File | Path | Hosts |
|---|---|---|
| Script | `/usr/local/bin/wol-relay.py` | psicopompo + kavure |
| Service | `/etc/systemd/system/wol-relay.service` | psicopompo + kavure |
| Env | `/etc/wol-relay.env` | psicopompo + kavure |
| Deploy script | `/tmp/opencode/deploy-wol-relay.sh` | temporary (remove after use) |

### Env files

**psicopompo** (`/etc/wol-relay.env`):
```
WOL_TARGET_MAC=d0:94:66:ad:f3:c4
WOL_TARGET_HOST=kavure
WOL_PORT=9096
```

**kavure** (`/etc/wol-relay.env`):
```
WOL_TARGET_MAC=d0:94:66:de:8b:58
WOL_TARGET_HOST=psicopompo
WOL_PORT=9096
```

## API

| Endpoint | Method | Response |
|---|---|---|
| `GET /wake` | Sends Magic Packet | `200 {"status":"sent","target":"<host>","mac":"<mac>"}` |
| `GET /health` | Health check | `200 {"status":"ok"}` |

## Homepage

Entries in Homepage's `services.yaml` (ybytu):

- **Psicopompo group** → "Ligar Kavure": `href: http://100.82.51.112:9096/wake`
- **Kavure group** → "Ligar Psicopompo": `href: http://100.124.146.77:9096/wake`

Both use `siteMonitor` for the health chip.

## Maintenance

```bash
# Status
systemctl status wol-relay

# Reiniciar
sudo systemctl restart wol-relay

# Logs
journalctl -u wol-relay -f

# Testar wake manualmente
curl http://100.82.51.112:9096/wake   # acorda kavure (de psicopompo)
curl http://100.124.146.77:9096/wake  # acorda psicopompo (de kavure)

# Testar health
curl http://100.82.51.112:9096/health
curl http://100.124.146.77:9096/health
```

## WoL Prerequisites

For WoL to work, the target machine needs:

1. **WoL enabled in the BIOS** (already done on psicopompo and kavure)
2. **WoL enabled on the network interface:**
   ```bash
   # Verificar
   ethtool eno1 | grep "Wake-on"
   # Deve mostrar: Wake-on: g (magic packet)

   # Habilitar (persistente via systemd-networkd ou /etc/conf.d/network)
   sudo ethtool -s eno1 wol g
   ```
3. **Wired interface connected** (WoL does not work over Wi-Fi)

## Initial deploy (01/09/2026)

1. `wakeonlan` installed via pacman (psicopompo) and apt (kavure)
2. Script + service + env deployed via SCP/SSH
3. Kavure: port 9096 (9093 taken by docker-proxy)
4. Homepage updated with WoL entries

## Boot-race fix (22/09/2026)

**Problem:** `wol-relay` failed on boot with `bind: Cannot assign requested address` — `WOL_LISTEN_ADDR=100.82.51.112` (TS IP) came up before tailscaled assigned the IP. On top of that, the unit had `Restart=unless-stopped` (**docker syntax, invalid in systemd** → ignored, no auto-restart).

**Fix (homelab canonical standard — same as the 10/08 syncthing fix):**
1. `/etc/wol-relay.env` → `WOL_LISTEN_ADDR=127.0.0.1` (local bind, never 0.0.0.0 nor the volatile TS IP)
2. `tailscale serve --bg --tcp 9096 tcp://127.0.0.1:9096` — tailscaled exposes `100.82.51.112:9096` on the tailnet (state persists in tailscaled)
3. `Restart=on-failure` (systemd-correct) + drop-in `After/Wants=tailscaled-wait.service`
4. Validation: `curl http://100.82.51.112:9096/health` → `{"status":"ok"}` ✅
