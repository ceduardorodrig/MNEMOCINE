---
tags: [homelab, service, crafty, gaming]
---

# minecraft-status

**Native HTTP endpoint** reporting whether the Minecraft server process responds to Server List Ping (SLP). Provides the **Homepage** dashboard status chip (and HTTP monitors) with the *true state of the game server* — rather than container engine lifecycle state.

**Server:** kavure  
**Port:** `9095` (HTTP, `0.0.0.0`)  
**Service:** `minecraft-status.service` (systemd, native) · binary `/usr/local/bin/minecraft-status`  
**Source:** `SUMAENIMA-HUB/provisioning/minecraft-status/` (Rust, zero dependencies)  

## API Contract

| Method | Server Running | Server Stopped |
|---|---|---|
| `GET /` | **200** `up` | **503** `down` |
| `HEAD /` | **200**, identical headers to GET, **no body** | **503**, identical headers, no body |

- SLP handshake (protocol `-1` + status request) validates `version`/`players`/`description` in JSON responses — **an arbitrary open port will not pass** as "up".
- Plaintext payload with `Content-Length`; `Connection: close` (no persistent keep-alive).

## Operational Motivation

The `crafty-controller` container remains **always up** (acting as the management daemon) — displaying its container state on a dashboard badge would provide false uptime signals. The Homepage `minecraft` widget renders an oversized 3-field card outside standard UI styling.  
Solution: A minimal HTTP status endpoint + `siteMonitor` → compact status chip reflecting actual in-game state.

## Bug & Fix (08/10/2026 — HEAD Response Body Violation)

**Symptom:** Homepage logged `<httpProxy> Error calling http://kavure:9095/` every ~30s, regardless of server running state.

**Root Cause (Reproduced):** Homepage probes `siteMonitor` using **HEAD** requests. The Python→Rust rewrite (29/09) treated `HEAD` identically to `GET` and returned **a response body** — violating RFC 7231 §4.3.2. Node.js HTTP parsers aborted with `Parse Error: Data after \`Connection: close\`` → 500 proxy error. `GET` requests functioned properly (returning 200/503), explaining why symptom logs diverged from reported server state.

**Resolution:** `main.rs` differentiates `GET` from `HEAD`; HEAD responses return **headers only** (`headers_only`), maintaining accurate `Content-Length`. **9 unit tests** pass. Previous binary preserved at `/usr/local/bin/minecraft-status.bak-20261008-head`.

**Verification:**
- Raw socket: HEAD terminates in `\r\n\r\n` without trailing payload.
- Node.js (inside Homepage container): `HEAD ×3` → `200`, empty body, **0 errors**.
- Homepage logs: **0 `<httpProxy>` errors** across 100s observation window.

## Operation

```bash
systemctl status minecraft-status
curl -s -w " [%{http_code}]" http://127.0.0.1:9095/    # up|down + 200|503
journalctl -u minecraft-status -n 30 --no-pager
```

Rebuild & deploy: `cargo build --release` in `SUMAENIMA-HUB/provisioning/minecraft-status/` → `install -m 755 target/release/minecraft-status /usr/local/bin/` (kavure) → restart systemd unit.

## References

- Server & Management: [`crafty.md`](crafty.md) · Dashboard: [`homepage.md`](homepage.md)
- Systemd unit definition in HUB: `provisioning/systemd/minecraft-status.service`
