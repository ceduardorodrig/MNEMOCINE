---
tags: [homelab, recovery, checklist, todo]
---

# Checklist — Pós-migração kuaray (09/08/2026)

> ✅ **RESOLVIDO (10/08/2026)** — pendências executadas (config-as-code, watchtower, syncthing re-pareado, migrations). Detalhes em `recovery/disaster-recovery.md` e `servers/kuaray.md`.

> Contexto: perda do `/DATA/AppData` (CasaOS removido) no kuaray → configs apagadas sem backup.
> Migração: **aiostreams + comet → kavure**; demais apps ficaram no kuaray.
> Checklist de pendências para retomar depois.

## Pendências

- [ ] **Reconfigurar AIOStreams** em `https://kavure.chimaera-heptatonic.ts.net:8443/stremio/configure`
      (debrid keys, marketplace, filtros, custom formatter)
- [ ] **Reconfigurar Comet** em `http://kavure.chimaera-heptatonic.ts.net:8000` (debrid, scrape sources)
- [ ] **Reconfigurar Home Assistant** (kavure, `kavure.chimaera-heptatonic.ts.net:10000`) — config nova/vazia
      - ✅ **Funnel HA corrigido (09/08):** HA 2026.8 ignora `http:` do `configuration.yaml` (migrado p/ UI) → `trusted_proxies`/`use_x_forwarded_for` aplicados direto no `.storage/http`. Funnel `:10000` OK.
      - ⚠️ HA agora serve **HTTP** (cert SSL perdido com a config); HTTPS só via funnel Tailscale (decisão 16/08).
      - ✅ **Container corrigido (16/08):** `cap_add: [NET_ADMIN, NET_RAW]` → Bluetooth funcionando.
      - ✅ **HACS 2.0.5 instalado e configurado (16/08)** — OAuth GitHub OK, repos baixados.
      - ⏳ **Tuya (nuvem)** e **backup automático** — pendentes de config na UI.
- [ ] **Reconfigurar Pi-hole** (kuaray) — adlists/blocklists voltaram ao default; DNS ok
- [x] **Mosquitto (kuaray)** — **REMOVIDO 16/08/2026** (container + pastas). Sem dispositivos MQTT em uso; se precisar, recriar no kavure com credenciais. Ver [`services/mosquitto.md`](../services/mosquitto.md)
- [ ] **arr-stack (kuaray)** — Transmission, Lidarr, Prowlarr, slskd, Soularr, Syncthing: configs resetadas (reconfigurar + re-emparelhar o Syncthing, device ID novo)
- [ ] **Watchtower kuaray** — pausado (`docker update --restart=no` + stop); decidir se volta. Watchtower do **kavure** (03:00 BRT) já gerencia aiostreams/comet
- [ ] **`sae-core_api` crashando no kavure** (swarm) — investigar (não tocado na migração)
- [ ] **Definir backup estruturado de configs** — duplicati removido (06/08); hoje não há backup de configs

## Informações sensíveis

> Valores removidos por política (08/09/2026) — segredos vivem no **store sops/age** (`/mnt/NVME_PCI/secrets/`, ver `guides/secrets-centralizados.md`). SECRET_KEY do aiostreams e senhas sudo foram movidos para lá.

## Layout pós-migração

| Host | Caminho de dados |
|---|---|
| kuaray | `/home/kuaray/docker/<app>/` (prowlarr, lidarr, transmission, soularr, slskd, syncthing, mosquitto, homeassistant, pihole) |
| kavure | `/srv/data/aiostreams`, `/srv/data/comet` |

- CasaOS **removido** do kuaray (era ele quem montava `/DATA/AppData`)
- Funnels: kavure `kavure.chimaera-heptatonic.ts.net:8443` → aiostreams; kuaray `:10000` → Home Assistant

## Referências

- [`services/aiostreams.md`](../services/aiostreams.md)
- [`services/comet.md`](../services/comet.md)
- [`services/homepage.md`](../services/homepage.md)
- [`servers/kuaray.md`](../servers/kuaray.md)
- [`servers/kavure.md`](../servers/kavure.md)
- [`network/tailscale.md`](../network/tailscale.md)
