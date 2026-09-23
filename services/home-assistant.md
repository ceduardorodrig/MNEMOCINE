---
tags: [homelab, service, home-assistant, automation]
---

# Home Assistant

Plataforma de automação residencial.

**Servidor:** kavure (migrado 09/08/2026, antes kuaray)
**Porta:** `8123` (host network)
**Funnel:** `kavure.chimaera-heptatonic.ts.net:10000`
**URL interna:** `http://kavure.chimaera-heptatonic.ts.net:8123`
**URL pública:** `https://kavure.chimaera-heptatonic.ts.net:10000`
**Versão:** 2026.8.2

> **Estado (16/08/2026):** config **nova** (dados perdidos 08/08 com o CasaOS; onboarding concluído 16/08).
> Container com `cap_add: [NET_ADMIN, NET_RAW]` (recomendado pela doc oficial; **kavure não tem hardware
> Bluetooth** — integração removida). **HACS 2.0.5 instalado e configurado** (OAuth GitHub OK). **Tuya (nuvem)**
> e **backup automático** pendentes de configuração na UI. Acesso HTTP interno + HTTPS via funnel Tailscale.

## Stack

| Container | Imagem | Função |
|---|---|---|
| homeassistant | homeassistant/home-assistant:latest | Automação (host network, `cap_add: [NET_ADMIN, NET_RAW]`) |

- **MQTT:** removido (16/08) — sem dispositivos MQTT em uso; mosquitto retirado do kuaray. Se precisar no futuro, recriar no **kavure** com credenciais (`allow_anonymous false`).

## Portas

| Porta | Serviço | Bind |
|---|---|---|
| `8123` | Home Assistant web UI | host (0.0.0.0) |
| `18554` | go2rtc WebRTC (embutido) | 127.0.0.1 |

## Acesso

- **Tailscale:** `http://kavure.chimaera-heptatonic.ts.net:8123`
- **Público:** `https://kavure.chimaera-heptatonic.ts.net:10000` (via Funnel — HTTPS só aqui; interno é HTTP, decisão 16/08)
- `trusted_proxies` (`127.0.0.1`, `::1`) aplicados em `.storage/http` (HA 2026.8 ignora `http:` do yaml).

## Integrações

- **Bluetooth** — **sem hardware no kavure** (sem adaptador USB/PCI, bluez não instalado). Os dados de scanner
  (`54:35:30:FE:E7:66`, sensor `TY`) eram do kuaray, herdados na migração. Integração **removida 16/08**
  (entrada deletada do `.storage/core.config_entries`). As caps `NET_ADMIN`/`NET_RAW` ficam no compose
  (inofensivas) — se um dia plugar dongle BT USB ou proxy ESP32, basta re-adicionar a integração.
- **go2rtc** (embutido, `source: system`) — servidor interno `:18554`; câmeras ainda não configuradas
- **Tuya** (nuvem, **adicionada 16/08**) — lâmpadas Wi-Fi + sensores de porta (via hub Zigbee Tuya, mesma conta Smart Life)
- **HACS** (instalado e **configurado 16/08** — OAuth GitHub OK, `hacs.repositories` baixado)
- **Material You Utilities** (HACS frontend module, ativado 16/08) — `frontend.extra_module_url` + `panel_custom` no `configuration.yaml` (painel "Material You Utilities" na sidebar)
- **Adaptive Lighting** (HACS, ativado 16/08) — entry **Mnemocine** (`switch.adaptive_lighting_mnemoncine` + sleep/adapt switches), controla as 4 lâmpadas (`light.sink_lamp`, `light.fridge_lamp`, `light.door_lamp`, `light.desk_lamp`). Defaults: `take_over_control: true` (cede a mudanças manuais feitas via HA/app), `detect_non_ha_changes: false` (mudanças pelo app Smart Life NÃO são detectadas), `only_once: false`, color_temp 2000–5500K. Config via UI: *Settings > Devices & Services > Adaptive Lighting: Mnemocine > Options*
  - **Sleep mode** (`switch.adaptive_lighting_mnemoncine_..._sleep_mode_mnemoncine`) = modo "luz bem baixinha" sob demanda (brilho 1% + 1000K); ajustável em Options (`sleep_brightness`/`sleep_color_temp`). Ativado acidentalmente em 16/08 (causou luz a 1% de dia).
  - Stub `adaptive_lighting:` NÃO é necessário no YAML p/ uso via UI (cria uma entry "default" duplicada) — removido 16/08.
  - Entry "default" deletada 16/08; switches órfãos removidos automaticamente pelo HA.
- **Backup** (nativo, **ativado 16/08** com criptografia — chave `HA_BACKUP_ENCRYPTION_KEY` no store sops/age; automático diário, retenção 3 cópias; 1º backup 20 MB 14:09)

## Dados

- `/srv/data/homeassistant/` no kavure (`compose.yml` + `config/`).
- Espelhado diariamente pelo `config-backup` → `/mnt/BACKUP/configs-homelab/kavure/data/homeassistant`.
- Backup nativo do HA (snapshots `.tar` em `config/backups`) — ativar na UI (Settings > System > Backups).
- `secrets.yaml` (`some_password`) **capturado no store sops 28/08** (`HA_SOME_PASSWORD`; restore via `inject-secrets.sh`) — ver `guides/secrets-centralizados.md`. `secrets.yaml` é excluído do espelho `config-backup`.
