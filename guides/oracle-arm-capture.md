---
tags: [homelab, oracle, oci, cloud, tutorial, todo]
---

# Always Free ARM VM (A1.Flex) Capture — Loop Design

> Objective: Automatically capture the **most powerful Always Free tier instance** provided by Oracle Cloud — the **`VM.Standard.A1.Flex`** configured with **2 OCPU / 12 GB RAM** (the maximum entitlement for this tenancy). Because regional host capacity fluctuates constantly, an **automated polling loop** is required. Designed on **2026-10-08**.

## Target Specifications

| Parameter | Value |
|---|---|
| Shape | **`VM.Standard.A1.Flex`** (Ampere Altra ARM) |
| OCPU / Memory | **2 OCPU / 12 GB RAM** |
| OS Image | Canonical Ubuntu 24.04 **aarch64** platform image |
| Availability Domain | `WdCV:SA-SAOPAULO-1-AD-1` (Single regional AD) |
| Boot Volume | 50 GB |
| Public IP | None (Account limit of 2 ephemeral IPs reached; node accesses the mesh via **Tailscale**) |
| Subnet | Shared private cloud subnet |

## Execution Strategy

- **Fixed Target:** `2 OCPU / 12 GB RAM`. Smaller allocations are rejected to claim the full entitlement.
- **Interval:** **2-minute polling interval**. Testing at 1-minute intervals triggered `TooManyRequests: Too many requests for the user` API rate limiting. When host capacity opens, it remains available for minutes, not seconds.
- **Tailscale Mesh Networking:** The node launches without a public IP and joins the Tailnet automatically on initial boot.
- **Automatic Sentinel Stop:** Successful instance launch touches `/var/lib/arm-hunt/done`, terminating subsequent polling.
- **ntfy Push Alerts:** Dispatches high-priority notifications on successful launch or unhandled errors.

## Polling Driver (`provisioning/scripts/arm-hunt`)

```bash
#!/bin/bash
# arm-hunt — Automated claim script for Always Free ARM VM. Executed via hl-arm-hunt.timer.
set -euo pipefail

TENANCY="${ARM_TENANCY:-ocid1.tenancy.oc1..aaaaaaaad7bkoaf4ze5dqpncywag5fsktwnnqzjgrd5ktgbcmf6r7x5clokq}"
AD="${ARM_AD:-WdCV:SA-SAOPAULO-1-AD-1}"
SUBNET="${ARM_SUBNET:-ocid1.subnet.oc1.sa-saopaulo-1.aaaaaaaaf32oeak5kdzfyqic5b4y77uxnffxdlyh5dlw2e4pyiipv53dibma}"
IMAGE="${ARM_IMAGE:-ocid1.image.oc1.sa-saopaulo-1.aaaaaaaaqqxqqfkhlzjcneto533jgu7ey6nzlzlpt5kuh6cqtbldhy2bu2hq}"
KEYS_FILE="${ARM_KEYS_FILE:-/etc/arm-hunt/ssh_authorized_keys}"
OCPUS="${ARM_OCPUS:-2}"; MEMGB="${ARM_MEMGB:-12}"
NTFY="${ARM_NTFY:-http://ybytu:8083/alerts}"
STATE=/var/lib/arm-hunt; LOG=/var/log/arm-hunt.log

mkdir -p "$STATE"
[ -f "$STATE/done" ] && exit 0
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
notify(){ curl -s -H "Title: $1" -H "Priority: $2" -H "Tags: $3" -d "$4" "$NTFY" >/dev/null 2>&1 || true; }

KEYS=$(cat "$KEYS_FILE" 2>/dev/null || true)
META=$(printf '{"ssh_authorized_keys":"%s"}' "$KEYS")

out=$(oci compute instance launch \
  --compartment-id "$TENANCY" --availability-domain "$AD" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMGB}" \
  --image-id "$IMAGE" --subnet-id "$SUBNET" \
  --assign-public-ip false --boot-volume-size-in-gbs 50 \
  --display-name ybytyra --metadata "$META" 2>&1) && rc=0 || rc=$?

if printf '%s' "$out" | grep -qi 'Out of host capacity'; then
  log "capacity constrained (A1 $OCPUS/$MEMGB)"; exit 0
fi
if [ "$rc" -eq 0 ] || printf '%s' "$out" | grep -q '"id"'; then
  id=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["id"])' 2>/dev/null || echo '?')
  touch "$STATE/done"
  log "INSTANCE CAPTURED id=$id ($OCPUS/$MEMGB)"
  notify "🎉 ARM Instance Captured" "high" "tada" "A1.Flex $OCPUS OCPU/$MEMGB GB — $id"
else
  log "error: $out"
  notify "⚠️ arm-hunt: unexpected error" "default" "warning" "$(printf '%s' "$out" | head -c 300)"
fi
```

### Systemd Units (`provisioning/systemd/`)

`hl-arm-hunt.service`:
```ini
[Unit]
Description=Homelab: arm-hunt (capture Always Free ARM VM)
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/arm-hunt
```

`hl-arm-hunt.timer`:
```ini
[Unit]
Description=Every 2 min: arm-hunt
[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=1s
Persistent=true
[Install]
WantedBy=timers.target
```

## Zero-Touch Automated Provisioning

Upon launch, the instance is provisioned automatically via cloud-init (`provisioning/cloud-init/ybytyra.yaml`):
1. Docker runtime installation with standardized log rotation defaults;
2. Automatic Tailscale registration using the pre-authenticated vault key;
3. Deployment of core monitoring containers (node-exporter, promtail, glances, dockerproxy, autoheal, watchtower);
4. `etckeeper` backup initialization;
5. Completion push notification to ntfy `/alerts`.

> The captured node is designated **`ybytyra`** (Tupi: *mountain range*), continuing the naming convention of homelab Oracle cloud nodes (`ybytu` = wind, `ybyra` = tree).

## Current Status (2026-10-08)

Active and monitoring on **psicopompo** via `hl-arm-hunt.timer`.

## See Also

- [`guides/oracle-oci-cli.md`](oracle-oci-cli.md) — OCI CLI operations and quota limits
- [`guides/oci-shrink-boot-volume.md`](oci-shrink-boot-volume.md) — Storage reallocation runbook
