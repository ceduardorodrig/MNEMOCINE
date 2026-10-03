---
tags: [homelab, service, wake-on-lan, wol, power, psicopompo, kavure, kururu]
---

# Wake-on-LAN Relay

Serviço leve que acorda servidores remotamente via Magic Packet (WoL), acessível via Tailscale.

**Servidores:** kururu (emissor dedicado 24/7 com no-break) / kavure / psicopompo

> **✅ Status (02/10/2026):** validado de **ponta a ponta nos dois hosts** — psicopompo
> acorda em **54s** e kavure em **29s** após soft-off (ninguém tocou o power), com a
> persistência de WoL sobrevivendo ao reboot. A causa da falha das 14:07 foi
> identificada (BIOS Dell, `Deep Sleep Control`) e corrigida — ver
> [§Validação de ponta a ponta](#validação-de-ponta-a-ponta-02102026).

## Arquitetura — 3 camadas de redundância

Um **único código-fonte** (`kururu-wake`, Rust) implantado em **3 nós**:

```
                               Homepage / Cliente Remoto
                                           │
                                           ▼
                            ybytu (Smart Dispatcher 24/7)
                                  100.115.253.109:9096
                                   /             \
                  (primário 24/7) /               \ (fallback automático)
                                 ▼                 ▼
              kururu (24/7 + bateria) ── acorda ──► psicopompo  E  kavure
                          │
        ┌─────────────────┴─────────────────┐
        ▼                                   ▼
  psicopompo ◄─────── acorda ──────────► kavure
        ▲             (par a par)           │
        └───────────── acorda ──────────────┘
```

> **Regra de Acionamento Remoto:** O **Homepage** agora aponta para o **Smart Dispatcher** no `ybytu` (`100.115.253.109:9096`). O despachante tenta sempre o **Kururu** primeiro; se o Kururu estiver offline, aciona automaticamente o par x86 em fallback sem intervenção manual.
> **Quórum de 3:** basta **1 nó vivo na LAN** pra religar os outros dois. Sem kururu, os x86 se acordam mutuamente; sem os dois x86, o kururu acorda ambos.

| Componente | Tecnologia |
|---|---|
| Smart Dispatcher 24/7 (Cloud) | `wol-relay --dispatcher` (Rust nativo, porta `9096` no nó `ybytu`) |
| Emissor Canônico 24/7 (LAN) | `kururu-wake` (Rust nativo, porta `9096` no nó `kururu`) |
| Emissor Redundante (Psicopompo) | `wol-relay` (Rust nativo compilado de `kururu-wake`, porta `9096`) |
| Emissor Redundante (Kavure) | `wol-relay` (Rust nativo compilado de `kururu-wake`, porta `9096`) |
| Systemd / Init | `wol-dispatcher.service` (ybytu) / `wol-relay.service` (x86) / `/system/etc/install-recovery.sh` (kururu) |
| Persistência do WoL na NIC | `wol@.service` + mecanismo nativo (NetworkManager / netplan) — ver [§Persistência](#persistência-do-wol-f1--02102026) |
| Segurança | bind `127.0.0.1` + Tailscale Serve (x86); bind tailnet (ybytu) |
| Porta | `9096` (HTTP) → Magic Packet em `udp/9` na LAN |

> **Por que Kururu é o nó canônico para WoL?**
> 1. **Consumo ínfimo (~1W) e 24/7 na tomada**: diferente do psicopompo e kavure, kururu nunca é desligado.
> 2. **Bateria integrada (No-break de hardware)**: permite enviar WoL mesmo em transições de energia.
> 3. ~~**Conexão direta ao AP principal (`Cratos`)**: o kavure ficava atrás do repetidor Wi-Fi,
>    que bloqueia broadcast L2.~~ **Obsoleto desde 02/10/2026:** o kavure é **cabeado** no
>    switch gigabit `IT-BLUE LE-4203` (ver [`network/topology.md`](../network/topology.md)) —
>    o broadcast L2 chega normalmente. Kururu segue canônico pelos motivos 1 e 2.
>    A validação de ponta a ponta via switch **falhou às 14:07 e foi resolvida no mesmo dia**
>    (causa = BIOS) — ver [§Validação](#validação-de-ponta-a-ponta-02102026).

## Hosts e MACs

| Host | Interface | MAC | IP Tailscale | Função WoL |
|---|---|---|---|---|
| **kururu** | `mlan0` | `24:f5:aa:7c:e3:1e` | `100.127.188.45` | **Emissor Primário 24/7** (`kururu-wake`) — acorda **ambos** |
| **psicopompo** | `eno1` | `d0:94:66:de:8b:58` | `100.82.51.112` | Emissor redundante (acorda **kavure**) + alvo |
| **kavure** | `enp1s0` | `d0:94:66:ad:f3:c4` | `100.124.146.77` | Emissor redundante (acorda **psicopompo**) + alvo |

## Arquivos

| Arquivo | Caminho | Hosts |
|---|---|---|
| Rust Daemon & CLI | `/usr/local/bin/kururu-wake` / `/usr/local/bin/wol-relay` | kururu, psicopompo, kavure (Rust binário nativo) |
| Boot Persistence (kururu) | `/system/etc/install-recovery.sh` | kururu |
| Configuração de Alvos | `/etc/kururu-wake.conf` | kururu, psicopompo, kavure |
| Env do Daemon | `/etc/wol-relay.env` | psicopompo, kavure |
| Service Nativo | `/etc/systemd/system/wol-relay.service` | psicopompo, kavure |
| Persistência WoL | `/etc/systemd/system/wol@.service` | psicopompo, kavure |
| Netplan (wakeonlan) | `/etc/netplan/50-cloud-init.yaml` (backup `50-cloud-init.yaml.bak-20261002`) | kavure |
| Script Legado (Arquivado) | `scripts/archive/wol-relay.py` | vault `agentic-ai` (referência técnica histórica) |

## Configuração

### Alvos — `/etc/kururu-wake.conf` (nome → MAC)

**kururu** (acorda os dois — é o relay do Homepage):
```
psicopompo=d0:94:66:de:8b:58
kavure=d0:94:66:ad:f3:c4
```

**psicopompo** (só o par):
```
kavure=d0:94:66:ad:f3:c4
```

**kavure** (só o par):
```
psicopompo=d0:94:66:de:8b:58
```

> `GET /wake/<host>` apontando para o **próprio** nó retorna
> `404 "Target '<host>' not found ..."` — **por design** (auto-acordar em S5 é impossível).

### Daemon — `/etc/wol-relay.env`

| Var | Função |
|---|---|
| `WOL_TARGET_HOST` | alvo do atalho `GET /wake` (ex.: `kavure` no psicopompo) |
| `WOL_PORT` | porta do daemon HTTP (`9096`) |
| `WOL_LISTEN_ADDR` | bind do daemon — **sempre `127.0.0.1`** (padrão canônico) |

**psicopompo:**
```
WOL_TARGET_MAC=d0:94:66:ad:f3:c4
WOL_TARGET_HOST=kavure
WOL_PORT=9096
WOL_LISTEN_ADDR=127.0.0.1
```

**kavure:**
```
WOL_TARGET_MAC=d0:94:66:de:8b:58
WOL_TARGET_HOST=psicopompo
WOL_PORT=9096
WOL_LISTEN_ADDR=127.0.0.1   # adicionado 02/10/2026 (era 0.0.0.0)
```

> `WOL_TARGET_MAC` é **config legada**: a resolução do alvo usa
> `/etc/kururu-wake.conf`. Inofensiva, mantida por compatibilidade.

## API

### Kururu (Rust Nativo — Canônico 24/7)

| Endpoint | Método | Descrição | Resposta Exemplo |
|---|---|---|---|
| `GET /wake/psicopompo` | GET | Acorda Psicopompo via broadcast direto LAN | `{"status":"ok","target":"psicopompo","mac":"d0:94:66:de:8b:58","emitted":true}` |
| `GET /wake/kavure` | GET | Acorda Kavure via broadcast direto LAN | `{"status":"ok","target":"kavure","mac":"d0:94:66:ad:f3:c4","emitted":true}` |
| `GET /health` | GET | Verificação de integridade do relay | `{"status":"online","service":"kururu-wol-relay","node":"kururu"}` |

### Hosts x86 (psicopompo / kavure)

| Endpoint | Método | Resposta |
|---|---|---|
| `GET /wake` | Envia Magic Packet para o par (`WOL_TARGET_HOST`) | `200 {"status":"ok","target":"<host>","mac":"<mac>","emitted":true}` |
| `GET /wake/<host\|MAC>` | Envia para nome do conf ou MAC escrito na URL | `200 {"status":"ok",...}` |
| `GET /health` | Health check | `200 {"status":"online",...}` |
| `GET /wake/<próprio host>` | — | `404 {"status":"error","message":"Target '<host>' not found ..."}` (**por design**) |

> ⚠️ O `/health` reporta `node:"kururu"` **hardcoded em todos os nós** — para saber
> qual camada respondeu, use a origem da requisição (bind/serve), não o campo `node`.

### Bind e exposição

| Nó | Bind | Acesso remoto |
|---|---|---|
| psicopompo | `127.0.0.1` (desde 22/09/2026) | `tailscale serve` → `100.82.51.112:9096` |
| kavure | `127.0.0.1` (corrigido de `0.0.0.0` em 02/10/2026) | `tailscale serve` → `100.124.146.77:9096` |
| kururu | `0.0.0.0` ⚠️ **desvio conhecido** | LAN `192.168.3.55:9096` + tailnet `100.127.188.45:9096` |

> **Por que `127.0.0.1`:** com `0.0.0.0` o endpoint **sem autenticação** fica acessível
> a qualquer dispositivo da LAN **e às bridges Docker** (`172.x`) — um container
> comprometido acordaria o psicopompo à vontade. Cada nó só precisa de **localhost**
> (o próprio daemon emite o pacote localmente); o acesso remoto legítimo (Homepage,
> celulares, tailnet) passa pelo `tailscale serve`, que é persistente no tailscaled.
>
> **Pendência opcional:** padronizar o kururu (adicionar `WOL_LISTEN_ADDR=127.0.0.1`
> no hook `/system/etc/install-recovery.sh`) — **antes, verificar** se o
> `kururu-display` consulta o daemon via IP da LAN (se sim, manter `0.0.0.0` e
> registrar a exceção).

## Persistência do WoL (F1 — 02/10/2026)

**Problema:** `ethtool -s ... wol g` é **RUNTIME ONLY — não sobrevive a reboot**.
Provado na prática em 02/10/2026: o `wol g` do kavure foi **zerado pelo reboot das 13:08**
(voltou `Wake-on: d`).

**Solução — 2 camadas por host** (mecanismo nativo do gerenciador de rede + serviço
`wol@.service` do [ArchWiki §Make it persistent](https://wiki.archlinux.org/title/Wake-on-LAN#systemd_service)):

| Host | Mecanismo nativo | Garantia no boot | Validado |
|---|---|---|---|
| psicopompo (NetworkManager) | `nmcli c modify "Wired connection 1" 802-3-ethernet.wake-on-lan magic` | `/etc/systemd/system/wol@.service` → **`wol@eno1` = enabled** | ✅ boot 21:07 → `Wake-on: g` sozinho |
| kavure (netplan/networkd) | `wakeonlan: true` em `/etc/netplan/50-cloud-init.yaml` (backup `.bak-20261002`, `netplan generate` OK) | `/etc/systemd/system/wol@.service` → **`wol@enp1s0` = enabled** | ✅ boot 21:12 → `Wake-on: g` sozinho |

`/etc/systemd/system/wol@.service` (idêntico nos 2 hosts; só muda o path do `ethtool`:
`/usr/bin` no Arch, `/usr/sbin` no Ubuntu):

```ini
[Unit]
Description=Habilita Wake-on-LAN (magic packet) na interface %I
Documentation=https://wiki.archlinux.org/title/Wake-on-LAN
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ethtool -s %I wol g

[Install]
WantedBy=multi-user.target
```

```bash
# habilitar / verificar
sudo systemctl enable --now wol@eno1    # psicopompo
sudo systemctl enable --now wol@enp1s0   # kavure
sudo ethtool eno1 | grep "Wake-on"       # deve ser: Wake-on: g
```

## Validação de ponta a ponta (02/10/2026)

### Causa raiz da falha das 14:07 — BIOS Dell

Diagnóstico oficial da Dell (OptiPlex 3060): **`Deep Sleep Control` = "Enabled in S4 and
S5"** (**default de fábrica**) desligava a NIC em S5 — o magic packet chegava, mas a placa
estava **sem energia de standby**. **Corrigido na BIOS pelo usuário** (`Deep Sleep Control
= Disabled`, junto com `Wake on LAN/WWAN` e `AC Recovery` já habilitados).

**Falsas hipóteses descartadas na investigação:** quirk do driver `r8169` (o WoL funciona
com ele), "shutdown travado" (desligamento medido em **13s**) e "pacote não atravessa o
switch" (**tcpdump provou a chegada** no `enp1s0`).

**Diagnóstico físico — fazer ANTES de apertar o power (2 segundos):**

| Luz da porta no switch (cabo do host) | Leitura |
|---|---|
| 🔴 **apagada** | NIC sem energia de standby → causa **BIOS** (`Deep Sleep Control` / `ErP Ready`) |
| 🟢 **acesa** | NIC viva esperando pacote → driver/quirk, ou o pacote não chegou → isolar com `tcpdump`/`nc -u -l -p 9` |

> 💏 Caminho alternativo de emissão: botão **Wake-on-LAN** da interface do roteador
> (`192.168.3.1`, gateway `Cratos`).

### Resultado — os dois hosts ✅

| Etapa | psicopompo | kavure |
|---|---|---|
| Desligamento (`shutdown -P`, S5) | 21:07 (offline em ~13s) | 21:11:42 (offline em 13s) |
| Quem emitiu | **watcher no kavure** (relay local `127.0.0.1:9096`) | **psicopompo** (relay local) |
| Magic packets | 9 disparos (5s entre eles) | 5 disparos |
| **ACORDOU** | **54s** após offline | **29s** após offline |
| `Wake-on` após o boot | `g` — **F1 intacto** | `g` — **F1 intacto** |
| Pós-boot | Swarm worker reentrou `Ready` | Swarm 3/3, **37/37** containers, NFS `active`, `Live Restore: false` |

- **Ninguém apertou o power** (confirmado pelo usuário) → **WoL puro nos dois sentidos.**
- **Prévias (Fase A):** pacotes capturados no `eno1` do psicopompo vindos do kavure
  (10 magic: `ffffffffffff d09466de8b58 ×16`, `192.168.3.41 → 192.168.3.255` e
  `→ 255.255.255.255`) e, mais cedo, no `enp1s0` do kavure vindos do psicopompo.
- **Direção kavure → psicopompo = 54s**: a placa leva mais pra finalizar o S5 — o burst
  repetido (5s) cobre a janela. **Direção psicopompo → kavure = 29s.**
- A janela derrubou o Swarm **manager** por ~1,5min; os workers mantêm as tasks e tudo
  reconvergiu sozinho (validar `docker node ls` ao voltar).

### Runbook de teste reproduzível

```bash
# 1) conferir prontidão (alvo)
sudo ethtool <iface> | grep -E 'Supports|Wake-on'   # Supports: *g* · Wake-on: g
systemctl is-enabled wol@<iface>                     # enabled
grep GLAN /proc/acpi/wakeup                          # *enabled

# 2) armar watcher NO OUTRO host (ele é quem sobrevive)
#    loop: ping até cair → curl 127.0.0.1:9096/wake/<alvo> a cada 5s → logar
#    timestamps → registrar quando o ping voltar

# 3) derrubar com atraso (a sessão local fecha antes da morte)
sudo systemd-run --on-active=30s /usr/sbin/shutdown -P now

# 4) ao voltar: ler o log do host vivo e conferir que Wake-on segue 'g'
```

## Homepage (Smart Dispatcher com Auto-Failover)

Entradas no `services.yaml` do Homepage (ybytu) — **atualizadas em 03/10/2026** apontando para o Smart Dispatcher no Ybytu (`100.115.253.109:9096`):

- **Grupo Psicopompo** → "Ligar Psicopompo":
  - `href: http://100.115.253.109:9096/wake/psicopompo`
  - `siteMonitor: http://100.115.253.109:9096/health`
  - *Fluxo:* Tenta Kururu (`100.127.188.45`) ➔ Fallback automático Kavure (`100.124.146.77`).
- **Grupo Kavure** → "Ligar Kavure":
  - `href: http://100.115.253.109:9096/wake/kavure`
  - `siteMonitor: http://100.115.253.109:9096/health`
  - *Fluxo:* Tenta Kururu (`100.127.188.45`) ➔ Fallback automático Psicopompo (`100.82.51.112`).

> O `siteMonitor` no Homepage fica verde desde que **pelo menos um** emissor na LAN esteja online.

## Manutenção

```bash
# Status / logs (hosts x86)
systemctl status wol-relay
journalctl -u wol-relay -f

# Testar wake LOCAL (bind é 127.0.0.1)
curl http://127.0.0.1:9096/wake          # acorda o par
curl http://127.0.0.1:9096/wake/kavure   # alvo nomeado

# Testar via tailnet (tailscale serve)
curl http://100.82.51.112:9096/health    # psicopompo
curl http://100.124.146.77:9096/health   # kavure
curl http://100.127.188.45:9096/health   # kururu
```

## Pré-requisitos WoL

1. **WoL habilitado na BIOS:** psicopompo ✅ · **kavure ✅** (`Deep Sleep Control = Disabled`
   desde 02/10/2026 — era o default `Enabled in S4 and S5` que causou a falha)
2. **WoL habilitado na interface** (`Wake-on: g`) — **persistente**, ver
   [§Persistência](#persistência-do-wol-f1--02102026) (`ethtool -s` sozinho não basta)
3. **Interface cabeada** (WoL não funciona via Wi-Fi) + **energia de standby na NIC**
   (com `ErP Ready` ligado na BIOS a NIC morre junto com o host)
4. **Driver cooperativo** — no kavure, `r8169`/RTL8168H consta como problemático na
   [ArchWiki §Realtek](https://wiki.archlinux.org/title/Wake-on-LAN#Realtek), **mas na
   prática funcionou** (quirk descartado em 02/10)

## Histórico

- **01/09/2026 — Deploy inicial:** `wakeonlan` instalado (pacman/apt) + script + service
  + env via SCP/SSH; porta 9093 ocupada por docker-proxy no kavure → 9096; Homepage atualizado.
- **22/09/2026 — Boot-race fix:** `WOL_LISTEN_ADDR=100.82.51.112` (IP TS) morria antes do
  tailscaled → bind `127.0.0.1` + `tailscale serve --bg --tcp 9096` + `Restart=on-failure`
  + drop-in `After/Wants=tailscaled-wait.service`.
- **02/10/2026, 13:08 — Migração pro switch gigabit:** boot do kavure derrubado pelo
  `live-restore` (ver [`servers/kavure.md`](../servers/kavure.md)) — e o `wol g` zerado
  pelo reboot, expondo a falta de persistência.
- **02/10/2026, 14:07 — Teste via switch FALHOU** (kavure fora do ar por ~70min até o
  acesso físico) → investigação com tcpdump/nc → **causa raiz: BIOS `Deep Sleep Control`**.
- **02/10/2026, 20:50–21:13 — Validação completa:** BIOS corrigido → kavure acorda (21s)
  · **F1** persistência aplicada nos 2 hosts · bind do kavure → `127.0.0.1` ·
  **psicopompo acorda em 54s** (watcher no kavure) · **kavure acorda em 29s** (relay do
  psicopompo) · conf do kururu conferido completo.

## Fontes

- [ArchWiki — Wake-on-LAN](https://wiki.archlinux.org/title/Wake-on-LAN)
  (§Enable WoL · §Make it persistent · §Realtek)
- [systemd.link(5)](https://man.archlinux.org/man/systemd.link.5)
- [NetworkManager — 802-3-ethernet.wake-on-lan](https://networkmanager.dev/docs/api/latest/settings-802-3-ethernet.html)
- [netplan — `wakeonlan`](https://canonical-netplan.readthedocs-hosted.com/)
