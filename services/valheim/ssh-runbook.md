---
tags: [homelab, service, valheim, tutorial]
---

# Valheim — SSH Operations Runbook

Operational procedures and diagnostic runbook for managing the **Valheim** dedicated server on kavure via SSH. Canonical architecture: [`valheim-server.md`](valheim-server.md).

## Remote Access

```bash
tailscale ssh kavure@kavure
```

## Management Scripts (`/usr/local/bin/valheim-*`)

| Script | Function |
|---|---|
| `valheim-start` | Starts the server container (`docker compose up -d`) |
| `valheim-stop` | Stops the server cleanly (`docker compose down`) |
| `valheim-restart` | Restarts the container (`docker compose restart`) |
| `valheim-status` | Displays container state, bound UDP sockets, and resource utilization |
| `valheim-backup` | Synchronizes off-box backup via rsync to psicopompo NAS target |
| `valheim-playercount` | Reports active player count parsed from daemon logs |

## Granting In-Game Administrative Privileges

Valheim 1.0 utilizes `config/bepinex/permissions.yaml` as the canonical permissions database, mirrored to legacy `saves/adminlist.txt`.

### Step 1: Identify Target Player SteamID64

Parse historical connection handshakes directly from container output:

```bash
# Display recent connection handshakes (SteamID and character names):
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aE "Got connection SteamID|joined" | tail -40

# Count unique connecting SteamIDs:
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aoE "Got connection SteamID [0-9]+" | awk '{print $4}' | sort | uniq -c | sort -rn
```

### Step 2: Atomic Online Grant (No Server Downtime)

The server daemon dynamically **reloads permissions on every player join event** (`Reloading <N> permission data` logged by Server Devcommands). New privileges activate upon the player's next reconnect without restarting the container:

```bash
cd /srv/data/valheim
TS=$(date +%Y%m%d-%H%M%S)
cp -a config/bepinex/permissions.yaml "config/bepinex/permissions.yaml.bak-$TS"

# Write full updated configuration to temporary file and install atomically:
cat > /tmp/permissions.yaml <<'EOF'
- id: 76561198009545651
  name: Lira
  admin: yes
- id: 76561198009545651
  name: Lira
  character: -1186721141
  admin: yes
EOF
sudo install -o kavure -g kavure -m 774 /tmp/permissions.yaml config/bepinex/permissions.yaml
rm -f /tmp/permissions.yaml
```

> ⚠️ **Atomic file installation (`install`) is mandatory**: The game engine rewrites this file when players connect. An atomic rename prevents race conditions where the process reads a partially written file.

Instruct the player to disconnect and rejoin. Verify in logs:
```bash
sudo docker logs -f valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -a 'permission data'
```

## Connection & Latency Diagnostics

Correlate connection drops and latency spikes using structured log analysis:

```bash
# 1. Determine whether disconnection was triggered by RPC timeout or voluntary leave:
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aE "ZRpc timeout|ClosedByPeer|RPC_Disconnect|joined|SteamID"

# 2. Inspect active Tailscale routing states (Direct vs Relay):
tailscale status --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
for p in (d.get('Peer') or {}).values():
    if not p.get('Online'): continue
    print(p.get('HostName'), p.get('TailscaleIPs'), 'DIRECT ' + (p.get('CurAddr') or '') if p.get('CurAddr') else 'RELAY ' + (p.get('Relay') or '?'))
"
```

Diagnostic Interpretation:
- `ZRpc timeout detected` immediately prior to departure points to an interruption along the client's network path (packet drop or local ISP stall).
- `ClosedByPeer` / `RPC_Disconnect` indicates an intentional client-initiated exit.

## Direct Docker Commands

```bash
cd /srv/data/valheim
docker compose up -d              # Launch container
docker compose down               # Graceful stop with automated world save
docker compose restart valheim    # Quick container restart
docker compose logs -f --tail 100 # Live log tail
```

## UDP Port Validation

```bash
valheim-status
docker ps --filter name=valheim-server
ss -lunpt | grep -E '2456|2457|2458'
```

| Port | Protocol | Purpose |
|---|---|---|
| 2456 | UDP | Primary game listener |
| 2457 | UDP | Steam query port / secondary |
| 2458 | UDP | Auxiliary query port |

## Backup Verification

- **Off-Box NAS Target:** `valheim-backup` executes `rsync --delete` from `/srv/data/valheim/saves/worlds_local/` → `/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/` over NFS.
- **Container Backups:** Dedicated Odin container snapshots written every 30 minutes into `/srv/data/valheim/backups/` with a 7-day retention policy.

## Troubleshooting

- **Container fails to boot:** Inspect `docker logs valheim-server --tail 100` for missing Steam dependencies or filesystem lock conflicts.
- **Corrupted world save:** Restore the latest snapshot from `/srv/data/valheim/saves/worlds_local/` or off-box NFS target.
- **Elevated memory footprint:** Normal idle usage sits between 1.5–2.5 GB. If memory leaks occur across long sessions, trigger `valheim-restart`.

## See Also
- [`valheim-server.md`](valheim-server.md) — Dedicated server specification
- [`onboarding.md`](onboarding.md) — Player connection setup guide
- [`../../servers/kavure.md`](../../servers/kavure.md) — Kavure hardware profile
