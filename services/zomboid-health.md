---
tags: [homelab, service, zomboid, gaming]
---

# zomboid-health

**Native HTTP endpoint** reporting whether the **Project Zomboid** dedicated server responds on its Source
RCON port. Provides the **Homepage** dashboard status chip with the *true state of the game server* — not the
`zomboid-panel` manager's state.

**Server:** kavure  
**Port:** `100.124.146.77:9098` (HTTP, kavure tailnet IP — re-bound from `0.0.0.0` on 2026-10-13, HB-047)  
**Service:** `hl-zomboid-health.service` (systemd, native) · binary `/usr/local/bin/zomboid-health`  
**Source:** `MNEMOCINE-OPS/provisioning/zomboid-health/` (Rust, zero dependencies)  

## API Contract

| Method | Game Running | Game Stopped |
|---|---|---|
| `GET /` | **200** `up` | **503** `down` |
| `HEAD /` | **200**, identical headers to GET, **no body** | **503**, identical headers, no body |
| other | **405** | **405** |

- Plaintext payload with `Content-Length`; `Connection: close` (no persistent keep-alive).

## Why it exists (13/10/2026)

The `Project Zomboid` Homepage tile had **no honest status source**:

- The game runs in the **`pz-server` container** (`danixu86/project-zomboid-dedicated-server`), which publishes
  `27015/tcp` (RCON) and `16261-16262/udp`. When the game is stopped, `zomboid-stop` runs `docker compose down`,
  which **removes** the container — so a Docker chip on `pz-server` would render "not found" rather than a red
  "down".
- A chip on the **`zomboid-panel`** manager would be **false uptime**: the panel stays up while the game is down,
  and its API is auth-gated (`/api/servers/status` → `401`).

Following the Homepage status convention (a game server with a custom binary protocol gets a lightweight HTTP
status endpoint + `siteMonitor`), this endpoint is the sibling of [`minecraft-status`](minecraft-status.md)
(`:9095`) and [`unbound`](unbound.md) (`:9097`): same shape, same HEAD-without-body care (RFC 7231 §4.3.2).

## Probe

A **TCP connect to `127.0.0.1:27015`** (the game's RCON, published on loopback by the `pz-server` container).
That host port is owned **exclusively** by the game container: it is refused when the game is down and accepted
once RCON is listening, so the chip cannot report false uptime (nor a false down while the game is up). No secret
is required. Historical proof that this is the right address: the `zomboid-save` helper issued RCON commands to
`127.0.0.1` successfully until the game was stopped on **2026-08-26**.

## Operation

```bash
systemctl status hl-zomboid-health
curl -s -w " [%{http_code}]" http://100.124.146.77:9098/    # up|down + 200|503
journalctl -u hl-zomboid-health -n 30 --no-pager
```

Rebuild & deploy: `cargo build --release` in `MNEMOCINE-OPS/provisioning/zomboid-health/` →
`install -m 755 target/release/zomboid-health /usr/local/bin/` (kavure) → restart systemd unit. Or via the
installer: `MNEMOCINE-OPS/provisioning/scripts/install-homelab-tools.sh --host kavure zomboid-health`.

## References

- Game & management: [`zomboid/project-zomboid.md`](zomboid/project-zomboid.md) · Dashboard: [`homepage.md`](homepage.md)
- Systemd unit definition in `MNEMOCINE-OPS`: `provisioning/systemd/hl-zomboid-health.service`
