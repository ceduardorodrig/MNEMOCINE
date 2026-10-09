---
tags: [homelab, oracle, oci, cloud, tutorial, recovery]
---

# Shrinking an OCI Boot Volume (Methodology & ybyra Runbook)

> **Context:** Oracle Cloud Infrastructure **does not support shrinking** boot or block volumes — volumes can only be expanded. When an Always Free account reaches its 200 GB block storage ceiling, the only viable path to reclaim storage is **re-provisioning** the volume with a smaller quota. This document outlines the reduction of ybyra's boot disk (150 GB → 50 GB), releasing the 100 GB required for the ARM A1 instance. Established on **2026-10-08**.

## Tenancy Storage Constraints

| Parameter | Value | Details |
|---|---|---|
| Total Block Storage Quota | **200 GB** | Shared across all boot and block volumes in the tenancy |
| Current Allocations | **200 GB** | ybytu (50 GB) + ybyra (150 GB) |
| Target Allocations | **100 GB** | ybytu (50 GB) + ybyra (50 GB) → **100 GB free** |
| Custom Image Quota | **0** | Tenancy enforces `custom-image-count = 0`; live disk imaging is unavailable. |

Because custom image snapshots are disallowed in this account, shrinking requires rebuilding the instance using the standard platform Ubuntu 24.04 image while preserving network identities.

## Rebuilding Runbook (Zero-Drift Strategy)

The target is to replace the running instance with an identical 50 GB instance: identical hostname, identical internal private IP (`10.0.0.40`), and identical Tailnet identity.

### Phase 1 — State & Identity Preservation
1. **Tailscale Node State:** Mirror `/var/lib/tailscale/tailscaled.state` to NAS backup to retain Tailscale IPv4/IPv6 addresses and node keys.
2. **Configurations:** Execute `config-backup` to ensure all compose trees and `/etc` states (via `etckeeper`) are updated on the NAS.
3. **Capture Instance Metadata:** Record subnet OCID, security groups, and SSH authorized keys.

### Phase 2 — Migration Window & Cutover
4. **Edge Failover:** Scale up backup standby services on kavure (`sae-edge_proxy-standby`, `sae-edge_tunnel-standby`, `sae-edge_umami-standby`) to maintain zero public downtime.
5. **Terminate Legacy Instance:**
   ```bash
   oci compute instance terminate --instance-id <YBYRA_OCID> --preserve-boot-volume false --force
   ```
6. **Launch Replacement Instance (50 GB):**
   ```bash
   oci compute instance launch -c "$T" \
     --availability-domain "WdCV:SA-SAOPAULO-1-AD-1" \
     --shape "VM.Standard.E2.1.Micro" --image-id <UBUNTU_24_04_OCID> \
     --subnet-id "$SUBNET_ID" --private-ip 10.0.0.40 \
     --assign-public-ip true --boot-volume-size-in-gbs 50 \
     --display-name ybyra --metadata "{\"ssh_authorized_keys\":\"$KEYS\"}"
   ```

### Phase 3 — State Restoration
7. **Restore Tailscale State:** Stop `tailscaled`, restore `/var/lib/tailscale/`, and start the daemon. Node rejoins at `100.66.224.34`.
8. **Docker & Swarm Join:** Rejoin the Swarm cluster as a worker:
   ```bash
   docker swarm join --token <WORKER_TOKEN> <kavure>:2377
   ```
9. **Restore Local Compose Stacks:** Restore `/home/ubuntu/homelab/` from NAS mirror and hydrate environment secrets via SOPS.
10. **Re-apply Node Labels:**
    ```bash
    docker node update --label-add role=primary ybyra
    ```

### Phase 4 — Validation & Fail-back
11. Verify health endpoints and scale down standby replicas on kavure:
    ```bash
    docker service scale sae-edge_proxy=1 sae-edge_tunnel=1 sae-edge_umami=1
    docker service scale sae-edge_proxy-standby=0 sae-edge_tunnel-standby=0 sae-edge_umami-standby=0
    ```

## See Also

- [`guides/oracle-oci-cli.md`](oracle-oci-cli.md) — OCI CLI terminal operations
- [`guides/oracle-arm-capture.md`](oracle-arm-capture.md) — ARM instance capture loop
- [`servers/ybyra.md`](../servers/ybyra.md) — Primary edge node documentation
