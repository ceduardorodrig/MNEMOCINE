---
tags: [homelab, service, zomboid, tutorial]
---

# Zomboid — Runbook SSH

Operação manual do servidor de **Project Zomboid** no kavure via SSH. Fonte de verdade: [`project-zomboid.md`](project-zomboid.md).

## Acesso

```bash
tailscale ssh kavure@kavure
```

## Scripts de operação (`/usr/local/bin/zomboid-*`)

| Script | O que faz |
|---|---|
| `zomboid-start` | Liga o servidor (`docker compose up -d`) |
| `zomboid-stop` | Desliga **gracioso** (save RCON + `docker compose down`) |
| `zomboid-restart` | Reinicia **gracioso** (save RCON + `docker restart`; re-baixa/atualiza mods no boot) |
| `zomboid-status` | Status do container + portas UDP |
| `zomboid-save <cmd>` | Envia comando RCON (save, broadcast, players…) |
| `zomboid-update` | Atualiza a **build** (backup do save + FORCEUPDATE/steamcmd) |
| `zomboid-backup` | Backup off-box do painel → psicopompo |

## Comandos rápidos

```bash
tailscale ssh kavure@kavure
zomboid-status
zomboid-restart          # gracioso: salva o mundo + atualiza mods do Workshop
zomboid-stop             # gracioso: save antes de desligar
zomboid-start
zomboid-save save        # save manual via RCON
```

## Equivalente Docker manual

```bash
cd /srv/data/zomboid
docker compose up -d              # start
docker compose down               # stop (abrupto — prefira zomboid-stop)
docker compose restart pz-server  # restart (abrupto — prefira zomboid-restart)
docker compose ps                 # status
docker compose logs -f            # console
docker compose logs -f --tail 100
```

> ⚠️ `docker compose restart` direto é **hard-kill** (entry.sh não trap SIGTERM) — por isso os scripts `zomboid-restart`/`zomboid-stop` fazem save via RCON antes.

## Status / portas

```bash
zomboid-status
docker ps --filter name=pz-server
ss -lunpt | grep -E '16261|16262|27015'
```

| Porta | Protocolo | Uso |
|---|---|---|
| 16261 | UDP | Jogo |
| 16262 | UDP | Conexão direta |
| 27015 | TCP | RCON |

## RCON

```bash
zomboid-save save                                # salva o mundo
zomboid-save 'servermsg "[SERVER] Aviso global"' # banner no topo da tela (avisos)
zomboid-save "broadcast Mensagem no chat"        # mensagem no chat
zomboid-save players                             # lista players (RCON não retorna saída neste build)
zomboid-save quit                                # sai do jogo → Docker reinicia o container (unless-stopped)
```

> **⚠️ `servermsg` SEMPRE com aspas** (`servermsg "mensagem"`): sem aspas o PZ mostra só o primeiro token (fix 10/08/2026). Use aspas simples no shell e duplas dentro da mensagem.
> **Contagem de players:** RCON `players` não retorna dados neste build — para verificar players online use `sudo -n /usr/local/libexec/zomboid-playercount` (lê o `performance_history` do painel, ~1 min de atraso).

> **Avisos padronizados (07/08/2026):** os scripts `zomboid-restart` (20s), `zomboid-stop` (10s) e `zomboid-update` emitem um `servermsg` **antes** da ação, avisando que o servidor vai sair (~1 min para salvar/atualizar mods). O banner é **não-fatal** (se o RCON falhar, a ação segue mesmo assim).

> O script lê a senha RCON de `/srv/data/zomboid/.env` e conecta em `127.0.0.1`/`pz-server:27015`. O comando é o `argv[1]` — use aspas para comandos com espaços.

> **Restart remoto:** um RCON `quit` faz o jogo sair e o container reinicia sozinho (`restart: unless-stopped`), re-baixando os mods no boot — dá pra fazer pelo **Console do painel** no celular (ver [`onboarding`](onboarding.md)). Prefira `zomboid-restart` quando possível (faz save antes de forma explícita).

## Update de mods

1. `zomboid-restart` — no boot o jogo consulta o Steam Workshop e baixa as atualizações (não é o entry.sh; é o próprio jogo).
2. Confirmar no log do jogo:

```bash
grep -iE "workshop|NeedsUpdate|DownloadPending|installed to" \
  /srv/data/zomboid/data/Logs/*DebugLog-server.txt | tail
```

3. No painel (Zomboid Control Panel), mods devem ficar sem "Mod update available". Se aparecer persistente, confira que o painel lê `/pz-server/steamapps/workshop` (= `workshop-mods/`, bind adicionado em 07/08/2026).

## Update de build (steamcmd)

```bash
zomboid-update
```

Fluxo: backup comprimido do save → psicopompo (`archive/pre-update-<data>.tar.zst` via `zstd -3 -T0`), recria com `FORCEUPDATE=true` (steamcmd validate), sobe normal.

> **Após o update, reaplicar as flags ZGC** — o steamcmd sobrescreve o `ProjectZomboid64.json`:

```bash
python3 -c "import json;p='/srv/data/zomboid/pz-dedicated/ProjectZomboid64.json';d=json.load(open(p));flags=['-XX:+ZUncommit','-XX:ZUncommitDelay=60','-XX:SoftMaxHeapSize=4g'];a=d.setdefault('vmArgs',[]);[a.append(f) for f in flags if f not in a];json.dump(d,open(p,'w'),indent=2)"
zomboid-restart
```

## Backup

- **Off-box (principal):** `zomboid-backup` (systemd `hl-zomboid-backup.timer`, **05:15**, `Persistent=true`) espelha os zips do painel via **NFS** (`/srv/data/zomboid/offbox/daily/` = NAS psicopompo). Failsafe: reachability + retry (3×/2min) + timeouts + **ntfy** em falha — ver `project-zomboid.md`.
- **Painel (local):** autobackup diário **00:00**, retenção 7, em `/srv/data/zomboid/data/backups/`.
- **Pré-update:** `zomboid-update` salva em `offbox/archive/pre-update-<data>.tar.zst` (NFS).
- Saves: `/srv/data/zomboid/data/Saves/Multiplayer/pzserver`

## Logs

```bash
# Log do jogo (boot atual)
ls -lt /srv/data/zomboid/data/Logs/*DebugLog-server.txt
tail -f /srv/data/zomboid/data/Logs/*DebugLog-server.txt

# Console do container
docker logs -f pz-server

# Logs de restart/backup
tail -f /var/log/zomboid-restart.log
tail -f /var/log/zomboid-backup.log
```

## Agendamentos (systemd timers)

```ini
# hl-zomboid-restart.timer — 05:00, 11:00, 17:00, 23:00 (4x OnCalendar, Persistent=true)
# hl-zomboid-backup.timer  — 05:15 (Persistent=true)
```

- **Fuso do host:** `America/Sao_Paulo` (configurado em 07/08/2026 — antes o host estava em UTC e os restarts rodavam 3h mais cedo).
- **watchtower** (container da stack `ops`, **03:00 BRT**): atualiza imagens de todos os containers, **incluindo `pz-server`** — recria o container sem save RCON (stop-timeout 30s); protegido por autosave + backups do painel/off-box.

## Painel web (Zomboid Control Panel)

- **URL:** `http://kavure.chimaera-heptatonic.ts.net:3001`
- **Funções:** RCON console, players, mapa ao vivo, gerenciador de mods, backup, scheduler de saves/broadcast, eventos/clima.
- **Não** faz start/stop do container (falso "stopped" é esperado — o lifecycle é do Docker, via `zomboid-*`).
- **Mods:** o painel lê o workshop em `/pz-server/steamapps/workshop` (bind de `workshop-mods/`). Em 07/08/2026 foi corrigido: a cópia velha em `pz-dedicated/steamapps/workshop` (que causava "Mod update available" eterno) foi removida.

## Troubleshooting

- **"Joining Game" infinito no cliente?** Incompatibilidade de versão (ex: Build 42.20.2 vs 42.20.3).
  - No cliente (`console.txt`), aparece `BufferUnderflowException: ChunkNotReadyPacket.parse`.
  - Solução: rodar `zomboid-update` no `kavure` ou sincronizar `projectzomboid.jar` com hash idêntico ao do cliente.
- **Servidor não sobe?** `docker logs pz-server --tail 100` + `zomboid-status`.
- **Mundo não salvo?** `zomboid-save save`; restauração via painel (backups) ou off-box `daily/`.
- **RAM alta em idle?** `zomboid-stop` libera tudo; o restart 4x/dia (05/11/17/23) limpa o heap.

## See also
- [[project-zomboid]] — Servidor Project Zomboid (Docker no kavure)
- [[zomboid-control-panel]] — Painel web
- [[kavure]] — Servidor de destino
- [[kavure-disaster-recovery]] — Restore completo a partir do off-box

