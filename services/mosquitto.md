---
tags: [homelab, service, mosquitto, automation]
---

# Mosquitto

MQTT broker.

**Server:** ~~kuaray~~ — **REMOVED 16/08/2026**

> **State (16/08/2026):** removed from kuaray (container + `/home/kuaray/homelab/mosquitto` +
> `/home/kuaray/docker/mosquitto`). No MQTT devices in use (Tuya bulbs/sensors via the cloud).
> If needed in the future, recreate it on **kavure** with credentials (`allow_anonymous false` + password file).
> The old config used `allow_anonymous true` (insecure) — **do not reuse**.

## History

| Container | Image | Role |
|---|---|---|
| mosquitto | eclipse-mosquitto:latest | MQTT broker (removed 16/08) |

## Integration

It was used by **Home Assistant** to talk to IoT devices — unused since the removal.
