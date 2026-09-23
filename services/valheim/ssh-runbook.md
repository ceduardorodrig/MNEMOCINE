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
tail -f /srv/data/valheim/config/valheim_server.log

# Console do container
docker logs -f valheim-server

# Logs de restart/backup
tail -f /var/log/valheim-restart.log
tail -f /var/log/valheim-backup.log

# Últimas linhas com mods
docker logs valheim-server --tail 200 2>&1 | grep -iE 'BepInEx|Plugin|Error|Exception'
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
