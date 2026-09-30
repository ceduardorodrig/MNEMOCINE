---
tags: [homelab, service, mosquitto, automation]
---

# Mosquitto

Broker MQTT.

**Servidor:** ~~kuaray~~ — **REMOVIDO 16/08/2026**

> **Estado (16/08/2026):** removido do kuaray (container + `/home/kuaray/homelab/mosquitto` +
> `/home/kuaray/docker/mosquitto`). Sem dispositivos MQTT em uso (lâmpadas/sensores Tuya via nuvem).
> Se precisar no futuro, recriar no **kavure** com credenciais (`allow_anonymous false` + password file).
> A config antiga usava `allow_anonymous true` (insegura) — **não reutilizar**.

## Histórico

| Container | Imagem | Função |
|---|---|---|
| mosquitto | eclipse-mosquitto:latest | Broker MQTT (removido 16/08) |

## Integração

Era usado pelo **Home Assistant** para comunicação com dispositivos IoT — sem uso desde a remoção.
