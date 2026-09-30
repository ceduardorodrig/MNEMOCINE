---
tags: [homelab, service, wake-on-lan, wol, power, psicopompo, kavure]
---

# Wake-on-LAN Relay

Serviço leve que acorda servidores remotamente via Magic Packet (WoL), acessível via Tailscale.

**Servidores:** kururu (emissor dedicado 24/7 com no-break) / kavure / psicopompo

## Stack

| Componente | Tecnologia |
|---|---|
| Emissor Canônico 24/7 | `kururu-wake` (Rust nativo, porta `9096` no nó `kururu`) |
| Emissor Redundante (Psicopompo) | `wol-relay` (Rust nativo compilado de `kururu-wake`, porta `9096`) |
| Emissor Redundante (Kavure) | `wol-relay` (Rust nativo compilado de `kururu-wake`, porta `9096`) |
| Systemd / Init | `wol-relay.service` (hosts x86) / `/system/etc/install-recovery.sh` (kururu) |
| Segurança | Tailscale ACL (só hosts da tailnet alcançam) |
| Porta | `9096` |

## Arquitetura

```
Qualquer nó da Tailnet (Celular, Notebook, Ybytu, etc.)
  │
  ├─► kururu:9096/wake/psicopompo ──► Magic Packet LAN (192.168.3.255:9) ──► Acorda Psicopompo
  └─► kururu:9096/wake/kavure     ──► Magic Packet LAN (192.168.3.255:9) ──► Acorda Kavure
```

> **Por que Kururu é o nó canônico para WoL?**
> 1. **Consumo ínfimo (~1W) e 24/7 na tomada**: Diferente do psicopompo e kavure, kururu nunca é desligado.
> 2. **Bateria integrada (No-break de hardware)**: Permite enviar WoL mesmo em transições de energia.
> 3. **Conexão Direta ao AP Principal (`Cratos`)**: O Kavure fica atrás de repetidor Wi-Fi (que bloqueia pacotes broadcast L2). Kururu transmite em broadcast direto para o segmento `192.168.3.255:9`.

## Hosts e MACs

| Host | Interface | MAC | IP Tailscale | Função WoL |
|---|---|---|---|---|
| **kururu** | `mlan0` | `24:f5:aa:7c:e3:1e` | `100.127.188.45` | **Emissor Primário 24/7** (`kururu-wake`) |
| **psicopompo** | `eno1` | `d0:94:66:de:8b:58` | `100.82.51.112` | Alvo (acordado via kururu ou kavure) |
| **kavure** | `enp1s0` | `d0:94:66:ad:f3:c4` | `100.124.146.77` | Alvo (acordado via kururu ou psicopompo) |

## Arquivos

| Arquivo | Caminho | Hosts |
|---|---|---|
| Rust Daemon & CLI | `/usr/local/bin/kururu-wake` / `/usr/local/bin/wol-relay` | kururu, psicopompo, kavure (Rust binário nativo) |
| Boot Persistence | `/system/etc/install-recovery.sh` | kururu |
| Configuração de Alvos | `/etc/kururu-wake.conf` | kururu, psicopompo, kavure |
| Service Nativo | `/etc/systemd/system/wol-relay.service` | psicopompo, kavure |
| Script Legado (Arquivado) | `scripts/archive/wol-relay.py` | vault `agentic-ai` (referência técnica histórica) |

### Configuração de Alvos (`/etc/kururu-wake.conf`)

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

### Kururu (Rust Nativo — Canônico 24/7)

| Endpoint | Método | Descrição | Resposta Exemplo |
|---|---|---|---|
| `GET /wake/psicopompo` | GET | Acorda Psicopompo via broadcast direto LAN | `{"status":"ok","target":"psicopompo","mac":"d0:94:66:de:8b:58","emitted":true}` |
| `GET /wake/kavure` | GET | Acorda Kavure via broadcast direto LAN | `{"status":"ok","target":"kavure","mac":"d0:94:66:ad:f3:c4","emitted":true}` |
| `GET /health` | GET | Verificação de integridade do relay | `{"status":"online","service":"kururu-wol-relay","node":"kururu"}` |

### Hosts x86 Legados (psicopompo / kavure)

| Endpoint | Método | Resposta |
|---|---|---|
| `GET /wake` | Envia Magic Packet cruzado | `200 {"status":"sent","target":"<host>","mac":"<mac>"}` |
| `GET /health` | Health check | `200 {"status":"ok"}` |

## Homepage

Entradas recomendadas no `services.yaml` do Homepage (ybytu):

- **Grupo Psicopompo** → "Ligar Psicopompo": `href: http://100.127.188.45:9096/wake/psicopompo`
- **Grupo Kavure** → "Ligar Kavure": `href: http://100.127.188.45:9096/wake/kavure`

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
