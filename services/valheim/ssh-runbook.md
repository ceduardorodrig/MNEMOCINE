---
tags: [homelab, service, valheim, tutorial]
---

# Valheim — Runbook SSH

Operação manual do servidor de **Valheim** no kavure via SSH. Fonte de verdade: [`valheim-server.md`](valheim-server.md).

## Acesso

```bash
tailscale ssh kavure@kavure
```

## Scripts de operação (`/usr/local/bin/valheim-*`)

| Script | O que faz |
|---|---|
| `valheim-start` | Liga o servidor (`docker compose up -d`) |
| `valheim-stop` | Para o servidor (`docker compose down`) |
| `valheim-restart` | Reinicia o servidor (`docker compose restart`) |
| `valheim-status` | Status do container + portas UDP + recursos |
| `valheim-backup` | Backup off-box via rsync → NFS psicopompo |
| `valheim-playercount` | Mostra players conectados (via log) |

## Dar admin a um jogador

> Mecanismo completo em [[valheim-server#Admin — permissions.yaml]]. Resumo: Valheim 1.0 usa `config/bepinex/permissions.yaml` como fonte de verdade, espelhado no `saves/adminlist.txt` legado.
>
> **Restart é o caminho garantido** (fluxo abaixo, passo 2). Mas dá pra editar **sem derrubar o servidor** — o `permissions.yaml` recarrega a cada entrada de jogador: ver **3.5 Atalho**. O `adminlist.txt` legado é boot-only.

### 1. Descobrir o SteamID do jogador

Não existe "quem tá conectado" além do log:

```bash
# histórico completo de conexões (id + nome do personagem)
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aE "Got connection SteamID|joined" | tail -40

# só os IDs distintos, com contagem
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aoE "Got connection SteamID [0-9]+" | awk '{print $4}' | sort | uniq -c | sort -rn
```

Quem **nunca** conectou não aparece no log → pedir o SteamID64 (ou o `V_` do overlay F2) direto pra ele.

### 2. Parar, backup, editar, subir

```bash
valheim-status                 # confirmar que ninguém está jogando
valheim-stop                   # graceful: AUTO_BACKUP_ON_SHUTDOWN=1 salva o mundo
cd /srv/data/valheim

TS=$(date +%Y%m%d-%H%M%S)
cp -a config/bepinex/permissions.yaml "config/bepinex/permissions.yaml.bak-$TS"
cp -a saves/adminlist.txt         "saves/adminlist.txt.bak-$TS"
```

Editar `config/bepinex/permissions.yaml` — o jogo usa **2 entradas por conta**: a base (`id` + `name` + `admin`) e a do personagem (`+ character`). Manter as duas:

```yaml
- id: 76561198009545651
  name: Lira
  admin: yes
- id: 76561198009545651
  name: Lira
  character: -1186721141
  admin: yes
```

> ⚠️ **Com o servidor no ar o jogo reescreve esse arquivo** a cada entrada de jogador. Por isso o `valheim-stop` vem antes da edição — não é exagero.

Espelhar no legado (mesmo formato, um ID por linha, sem comentário):

```bash
printf '76561198075365006\n76561198009545651\n' | sudo tee saves/adminlist.txt >/dev/null
sudo chown kavure:kavure saves/adminlist.txt && sudo chmod 774 saves/adminlist.txt
```

### 3. Subir e verificar

```bash
valheim-start
sleep 60
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aiE 'permission data|ZNet.LoadWorld' | tail
```

Esperado: `[Info :Server Devcommands] Reloading <N> permission data` (N = nº de entradas do YAML) e `ZNet.LoadWorld: Fimbulvetr`.

> O `admin: yes` no YAML é o que o mod lê (`N permission data` = entradas do arquivo). O mod **não** tem allowlist própria.

### 4. Falhou?

| Sintoma | Causa provável |
|---|---|
| `Reloading` ≠ nº de entradas | arquivo não foi pro lugar certo → conferir `stat` em `config/bepinex/permissions.yaml` |
| Admin não funciona in-game | cliente não ligou **Enable Console** (F5) → ver [[onboarding]] |
| Devcommands não aparecem | mod **Server Devcommands** não instalado no PC do jogador |
| Permissão some sozinha | editou com o servidor no ar; o jogo sobrescreveu → repetir com o servidor parado |

### 3.5 Atalho: dar admin **sem** reiniciar (servidor no ar)

> **Validado em produção 26/09/2026** com 3 jogadores conectados. Use quando não quiser derrubar ninguém.

O `permissions.yaml` é **recarregado a cada entrada de jogador** — o mod loga `Reloading <N> permission data` de novo. Grant novo vale a partir do **próximo join**, sem restart.

```bash
cd /srv/data/valheim
TS=$(date +%Y%m%d-%H%M%S)
cp -a config/bepinex/permissions.yaml "config/bepinex/permissions.yaml.bak-$TS"

# escrever o YAML completo no /tmp e instalar com rename (atômico)
cat > /tmp/permissions.yaml <<'EOF'
- id: 76561197988953037
  name: BiM
  admin: yes
- id: 76561197988953037
  name: BiM
  character: 685474752
  admin: yes
EOF
sudo install -o kavure -g kavure -m 774 /tmp/permissions.yaml config/bepinex/permissions.yaml
rm -f /tmp/permissions.yaml
```

> ⚠️ **Escrita atômica é obrigatória** (`install` = tmp + `rename`). O jogo reescreve esse arquivo a cada join; o rename garante que ele leia o arquivo antigo inteiro ou o novo inteiro, nunca um pela metade. `sed -i` in-place **não** serve aqui.

Depois:

```bash
# o jogador precisa RECONECTAR (sair e entrar) — a recarga acontece no join
sudo docker logs -f valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -a 'permission data'
```

| Limitação | Detalhe |
|---|---|
| Não é tempo real | o grant só ativa no **próximo join** de quem recebeu |
| `adminlist.txt` legado | lido **só no boot** — grava agora, vale no próximo restart (timer 05:00) |
| Grant em massa | edite o YAML com o jogador **conectado**; o merge do jogo preserva suas entradas |

Se o jogador não puder reconectar, aí sim restart: `valheim-stop` + `valheim-start`.

## Diagnóstico de conexão

> Contexto e conclusões em [[valheim-server#SmoothServer — ajustes de 27/09/2026 (diagnóstico de conexão)]] e [[valheim-server#SmoothServer — ajustes de 29/09/2026 (lag em Plains / "borracha")]]. Receita para repetir a análise.

### Telemetria do mod (fonte primária)

```bash
cd /srv/data/valheim/config/bepinex/smoothserver/stats

# eventos: joins/leaves, stalls de save, backoff do AdaptiveBudget
sudo tail -50 events-$(date -u +%F).jsonl

# estado por sample (3s desde 29/09/2026; era 10s): fps, frame time, ZDOs e por-peer rtt/pending/queued/budget
sudo tail -5 stats-$(date -u +%F).jsonl | python3 -m json.tool --json-lines

# ocupação da fila x orçamento, por peer (o achado da Plains: quem trava no piso?)
sudo python3 - <<'PY'
import json, glob, statistics as st
agg = {}
for fn in sorted(glob.glob("stats-*.jsonl")):
    for line in open(fn):
        try: d = json.loads(line)
        except: continue
        if d.get("players", {}).get("count", 0) == 0: continue
        for p in d.get("peers", []):
            t = p.get("budgetTargetBytes") or 1
            a = agg.setdefault(p["name"], {"pct": [], "pend": [], "rtt": []})
            a["pct"].append(100 * (p.get("queuedBytes") or 0) / t)
            a["pend"].append(p.get("pendingBytes") or 0)
            a["rtt"].append(p.get("rttMs") or 0)
for k, a in agg.items():
    pct = sorted(a["pct"]); n = len(pct)
    print(f"{k:<12} n={n:<5} mediana={st.median(a['pct']):.0f}% do orcamento  "
          f"p95={pct[int(n*.95)]:.0f}%  >=95%: "
          f"{sum(1 for x in pct if x >= 95)}/{n} ({100*sum(1 for x in pct if x>=95)/n:.1f}%)  "
          f"pending_max={max(a['pend'])}B  rtt_med={st.median(a['rtt']):.0f}ms")
PY

# análise oficial do mod (relatório markdown) — script do repo
# https://github.com/MJensen01/SmoothServer  → tools/README.md
```

> O nome do arquivo usa **data UTC** (o host é `America/Sao_Paulo`) — depois das 21:00 BTR já é o arquivo do dia seguinte.

### Correlacionar queda com causa

```bash
# 1. o peer caiu por ZRpc timeout (30s de silencio RPC) ou ele saiu?
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aE "ZRpc timeout|ClosedByPeer|RPC_Disconnect|joined|SteamID"

# 2. o save/GC congelou o servidor nesse instante? (se sim, é stall nosso)
sudo grep -aE '"(save|gc)"' /srv/data/valheim/config/bepinex/smoothserver/stats/events-$(date -u +%F).jsonl | tail

# 3. o caminho de rede do peer caiu?
tailscale status --json | python3 -c "
import sys,json
d=json.load(sys.stdin)
for p in (d.get('Peer') or {}).values():
    if not p.get('Online'): continue
    print(p.get('HostName'), p.get('TailscaleIPs'), 'DIRETO '+(p.get('CurAddr') or '') if p.get('CurAddr') else 'RELAY '+(p.get('Relay') or '?'))
"
```

**Leitura:**
- `ZRpc timeout detected` logo antes do `leave` → **caminho do cliente caiu** (não é mod nem servidor)
- `ClosedByPeer` + `RPC_Disconnect` → saída voluntária
- `PendingBackoffBytes`/`budgetCongested` baixo + `pendingBytes=0` → budget no piso é **normal em repouso** (BDP baixo por tráfego), não estrangulamento
- ⚠️ **mas em combate é diferente** (achado 29/09): `queuedBytes / budgetTargetBytes >= 95%` repetido = o **piso** está segurando o envio para **aquele** peer → ele vê estado velho (borracha). Medido: Lira em **9,2%** das amostras vs 0,6% do AhNo CaM. Se a correlação `frameWorst` × fila **não** bater (mediana 7% nos picos), são **dois problemas separados** — a fila explica o desync do peer, não o travamento do servidor.
- `frameWorst > 140 ms` caindo em `HH:01:3x`/`HH:31:3x` → é **save** (30 min), não combate. Só chame de lag de combate os picos fora desse padrão.
- `LagProbe` com `0 answered` → cliente **sem o mod**: RTT/jitter/perda reais não são medidos (só o `rttMs` do Steam)

### Identificar qual nó Tailscale é de quem

Os amigos entram por **nós compartilhados** (o kavure é compartilhado na tailnet deles) e aparecem como `device-of-shared-to-user`, sem nome. Para descobrir quem é quem, medir o **delta de tráfego** com o jogador online (nunca reuse nomes de arquivo temporário entre execuções — o `rm` de uma corrida apaga o sample da outra):

```bash
ssh kavure 'tailscale status --json > /tmp/ts-a.json; sleep 60; tailscale status --json > /tmp/ts-b.json'
# comparar RxBytes/TxBytes entre os dois snapshots; o nó que mexe é o do jogador
ssh kavure 'rm -f /tmp/ts-a.json /tmp/ts-b.json'
```

## Comandos rápidos

```bash
tailscale ssh kavure@kavure
valheim-status
valheim-restart
valheim-stop
valheim-start
valheim-backup
```

## Equivalente Docker manual

```bash
cd /srv/data/valheim
docker compose up -d              # start
docker compose down               # stop (gracioso — salva antes via AUTO_BACKUP_ON_SHUTDOWN)
docker compose restart valheim    # restart (rápido — sem save explícito)
docker compose ps                 # status
docker compose logs -f            # console
docker compose logs -f --tail 100
```

> **Diferente do Zomboid:** o Valheim não tem RCON — não é possível forçar save remoto via comando. O container salva automaticamente a cada 30 min (`AUTO_BACKUP`) e antes de shutdown/update.

## Status / portas

```bash
valheim-status
docker ps --filter name=valheim-server
ss -lunpt | grep -E '2456|2457|2458'
```

| Porta | Protocolo | Uso |
|---|---|---|
| 2456 | UDP | Jogo (principal) |
| 2457 | UDP | Jogo (backup) |
| 2458 | UDP | Jogo (backup) |

## Backup

- **Off-box (principal):** `valheim-backup` (rsync `--delete` de `/srv/data/valheim/saves/worlds_local/` → NFS psicopompo `/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`). Corrigido em 13/09/2026 (caminho antigo `config/backups/` não existia neste setup).
- **Container (local):** `AUTO_BACKUP` a cada 30 min em `/home/steam/backups` (`./backups`, persistido desde 13/09). Retenção 7 dias.
- **Pré-update:** `AUTO_BACKUP_ON_UPDATE=1` salva antes de atualizar
- **Pré-shutdown:** `AUTO_BACKUP_ON_SHUTDOWN=1` salva antes de desligar
- World data: `/srv/data/valheim/saves/worlds_local/` (Fimbulvetr.db + Fimbulvetr.fwl + auto-backups)

## Logs

```bash
# Log do jogo
# ⚠️ Não existe arquivo em /config/valheim_server.log (a doc antiga afirmava que
# existia — o Odin não persiste o log do jogo em disco). Leia por docker logs:
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -100
sudo docker logs -f valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g'

# Log do BepInEx (dentro do container)
sudo docker exec valheim-server tail -50 /home/steam/valheim/BepInEx/LogOutput.log

# Logs de restart/backup
tail -f /var/log/valheim-restart.log
tail -f /var/log/valheim-backup.log

# Filtros úteis (removem as cores ANSI do Odin)
sudo docker logs valheim-server 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -aiE 'BepInEx|Plugin|Error|Exception|SteamID|permission data'
```

## Agendamentos (systemd timers)

```ini
# hl-valheim-restart.timer — 05:00 diário (Persistent=true)
# hl-valheim-backup.timer  — 05:30 diário (Persistent=true)
```

- **Fuso do host:** `America/Sao_Paulo`
- **watchtower** (container da stack `ops`, **03:00 BRT**): atualiza `valheim-server` — recria container com stop-timeout 30s; `AUTO_BACKUP_ON_UPDATE=1` salva antes.

## Update de mods

1. Editar `MODS:` no `/srv/data/valheim/docker-compose.yml`
2. `valheim-restart` — no boot o BepInEx baixa/instala os mods automaticamente
3. Confirmar no log:

```bash
docker logs valheim-server --tail 100 2>&1 | grep -iE 'BepInEx|Plugin|Loading'
```

## Update de versão (steamcmd)

O `AUTO_UPDATE` rodando `0 3 * * *` (03:00) já faz update automático. Para manual:

```bash
cd /srv/data/valheim
docker compose down
docker compose up -d
# steamcmd roda no boot e atualiza se necessário
```

## Troubleshooting

- **Container não sobe?** `docker logs valheim-server --tail 100` + `valheim-status`
- **Mundo corrompido?** Restaurar de `/srv/data/valheim/saves/worlds_local/` (backup mais recente) ou do off-box NFS
- **Mods quebrados?** Verificar `BepInEx/LogOutput.log` — erros de compile indicam incompatibilidade
- **Mundo vazio (só terreno)?** `frame tag 0x48` no log → Compression do SmoothServer quebrou; ver [[valheim-server#SmoothServer Compression incompatível com Valheim 1.0.12 (mundo vazio)]]
- **RAM alta?** O Valheim consome ~1-2 GB em idle; `valheim-restart` limpa o heap
- **Conexão lenta?** SmoothServer monitora peers — verificar logs `[PeerTelemetry]`

## See also

- [[valheim-server]] — Servidor Valheim (Docker no kavure)
- [[onboarding]] — Guia para jogadores
- [[kavure]] — Servidor de destino
- [[project-zomboid]] — Servidor Zomboid (padrão de referência)
