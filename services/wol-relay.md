---
tags: [homelab, service, wake-on-lan, wol, power, psicopompo, kavure]
---

# Wake-on-LAN Relay

Serviço leve que acorda servidores remotamente via Magic Packet (WoL), acessível via Tailscale.

**Servidor:** kavure / psicopompo

## Stack

| Componente | Tecnologia |
|---|---|
| Servidor HTTP | Python `http.server` (padrão homelab) |
| WoL CLI | `wakeonlan` (perl, Arch extra / Ubuntu apt) |
| Systemd | `wol-relay.service` |
| Segurança | Tailscale ACL (só hosts da tailnet alcançam) |
| Porta | `9096` |

## Arquitetura

```
ybytu (Homepage:3001)
  ├─ "Ligar Kavure"     → Tailscale → psicopompo:9096/wake → wakeonlan <MAC-kavure>
  └─ "Ligar Psicopompo" → Tailscale → kavure:9096/wake     → wakeonlan <MAC-psicopompo>
```

Cada host roda um relay que acorda o **outro** host da LAN local.

## Hosts e MACs

| Host | Interface | MAC | IP Tailscale | Relay acorda |
|---|---|---|---|---|
| psicopompo | `eno1` | `d0:94:66:de:8b:58` | `100.82.51.112` | kavure |
| kavure | `enp1s0` | `d0:94:66:ad:f3:c4` | `100.124.146.77` | psicopompo |

## Arquivos

| Arquivo | Caminho | Hosts |
|---|---|---|
| Script | `/usr/local/bin/wol-relay.py` | psicopompo + kavure |
| Service | `/etc/systemd/system/wol-relay.service` | psicopompo + kavure |
| Env | `/etc/wol-relay.env` | psicopompo + kavure |
| Deploy script | `/tmp/opencode/deploy-wol-relay.sh` | temporário (remover após uso) |

### Env files

**psicopompo** (`/etc/wol-relay.env`):
```
WOL_TARGET_MAC=d0:94:66:ad:f3:c4
WOL_TARGET_HOST=kavure
WOL_PORT=9096
```

**kavure** (`/etc/wol-relay.env`):
```
WOL_TARGET_MAC=d0:94:66:de:8b:58
WOL_TARGET_HOST=psicopompo
WOL_PORT=9096
```

## API

| Endpoint | Método | Resposta |
|---|---|---|
| `GET /wake` | Envia Magic Packet | `200 {"status":"sent","target":"<host>","mac":"<mac>"}` |
| `GET /health` | Health check | `200 {"status":"ok"}` |

## Homepage

Entradas no `services.yaml` do Homepage (ybytu):

- **Grupo Psicopompo** → "Ligar Kavure": `href: http://100.82.51.112:9096/wake`
- **Grupo Kavure** → "Ligar Psicopompo": `href: http://100.124.146.77:9096/wake`

Ambos usam `siteMonitor` pro chip de saúde.

## Manutenção

```bash
# Status
systemctl status wol-relay

# Reiniciar
sudo systemctl restart wol-relay

# Logs
journalctl -u wol-relay -f

# Testar wake manualmente
curl http://100.82.51.112:9096/wake   # acorda kavure (de psicopompo)
curl http://100.124.146.77:9096/wake  # acorda psicopompo (de kavure)

# Testar health
curl http://100.82.51.112:9096/health
curl http://100.124.146.77:9096/health
```

## Pré-requisitos WoL

Para o WoL funcionar, a máquina alvo precisa ter:

1. **WoL habilitado na BIOS** (já feito em psicopompo e kavure)
2. **WoL habilitado na interface de rede:**
   ```bash
   # Verificar
   ethtool eno1 | grep "Wake-on"
   # Deve mostrar: Wake-on: g (magic packet)

   # Habilitar (persistente via systemd-networkd ou /etc/conf.d/network)
   sudo ethtool -s eno1 wol g
   ```
3. **Interface cabeada conectada** (WoL não funciona via Wi-Fi)

## Deploy inicial (01/09/2026)

1. `wakeonlan` instalado via pacman (psicopompo) e apt (kavure)
2. Script + service + env deployados via SCP/SSH
3. Kavure: porta 9096 (9093 ocupada por docker-proxy)
4. Homepage atualizado com entradas de WoL

## Boot-race fix (22/09/2026)

**Problema:** `wol-relay` falhava no boot com `bind: Cannot assign requested address` — `WOL_LISTEN_ADDR=100.82.51.112` (IP TS) subia antes do tailscaled atribuir o IP. Além disso, o unit tinha `Restart=unless-stopped` (**sintaxe docker, inválida no systemd** → ignorada, sem auto-restart).

**Fix (padrão canônico do homelab — mesmo do syncthing 10/08):**
1. `/etc/wol-relay.env` → `WOL_LISTEN_ADDR=127.0.0.1` (bind local, nunca 0.0.0.0 nem IP TS volátil)
2. `tailscale serve --bg --tcp 9096 tcp://127.0.0.1:9096` — tailscaled expõe `100.82.51.112:9096` na tailnet (estado persiste no tailscaled)
3. `Restart=on-failure` (systemd-correct) + drop-in `After/Wants=tailscaled-wait.service`
4. Validação: `curl http://100.82.51.112:9096/health` → `{"status":"ok"}` ✅
