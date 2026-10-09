---
tags: [homelab, service, mosquitto, automation]
---

# Mosquitto

MQTT Broker.

**Server:** ~~kuaray~~ — **REMOVED 16/08/2026**

> **Status (16/08/2026):** Removed from kuaray (container + `/home/kuaray/homelab/mosquitto` + `/home/kuaray/docker/mosquitto`). No active MQTT devices in use (Tuya bulbs/sensors operated via cloud).  
> If required in the future, recreate on **kavure** with credentials (`allow_anonymous false` + password file).  
> The legacy configuration used `allow_anonymous true` (insecure) — **do not reuse**.

## History

| Container | Image | Function |
|---|---|---|
| mosquitto | eclipse-mosquitto:latest | MQTT Broker (removed 16/08) |

## Integration

Was previously used by **Home Assistant** for IoT device communication — idle and decommissioned since removal.
