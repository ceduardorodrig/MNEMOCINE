---
tags: [homelab, service, valheim, tutorial]
---

# Valheim — Onboarding (Jogadores)

Guia para entrar no servidor de Valheim **Mnemocine Vikings** (kavure).

> Acesso só pela tailnet — quem não estiver na Tailscale precisa de acesso manual via IP.

## Dados de conexão

| Item | Valor |
|---|---|
| Nome do servidor | `Mnemocine Vikings` |
| IP (Tailscale) | `100.124.146.77` |
| Porta | `2456` (UDP) |
| **Senha** | `HalVeim1235` |
| Mundo | `Fimbulvetr` |
| Versão | 1.0.12 (Deep North) |

## Como entrar

1. Aceitar o host `kavure` na sua tailnet (se ainda não tiver).
2. Abrir Valheim → **Join Game**.
3. Adicionar servidor manualmente:
   - IP: `100.124.146.77`
   - Porta: `2456`
4. Conectar → digitar a senha `HalVeim1235`.

> O servidor é **privado** (`public=false`) — não aparece na lista de servidores. Só acessível via IP direto na tailnet.

## Mods

O cliente baixa os mods automaticamente ao conectar (BepInEx + 4 mods QoL). Se o jogo pedir para instalar, aceite — o servidor envia a lista.

### Mods instalados (4)

| Mod | Função |
|---|---|
| Gizmo | Rotação de construção (Ctrl+scroll) |
| FuelEternal | Fogo nunca apaga |
| CameraTweaks | Zoom e FOV customizável |
| SmoothServer | Performance de rede (Compression desabilitado, mapa não compartilhado) |

### Comandos admin (F5)

O Valheim 1.0 tem comandos nativos via console:

1. Pressionar **F5** para abrir o console.
2. Digitar `devcommands` → Enter (ativa modo desenvolvedor).
3. Comandos úteis:
   - `god` — modo invencível
   - `fly` — voo livre
   - `pos` — mostra coordenadas
   - `freefly` — câmera livre
   - `event` — eventos aleatórios
   - `stopevent` — para evento em andamento

> ⚠️ Comandos são **locais** — só afetam quem digitou. Não há admin remoto via RCON como no Zomboid.

## Restart remoto pelo celular

Se precisar reiniciar fora de casa:

1. Celular conectado na **Tailscale** (MagicDNS).
2. SSH: `tailscale ssh kavure@kavure`
3. Rodar: `valheim-restart`

> O servidor salva automaticamente antes do restart via `AUTO_BACKUP_ON_SHUTDOWN=1`.

## Manutenção automática

| Horário | O que acontece |
|---|---|
| 03:00 | Watchtower atualiza a imagem (steamcmd) |
| 05:00 | Restart diário (timer `hl-valheim-restart`) |
| 05:30 | Backup off-box (timer `hl-valheim-backup`) |
| A cada 30 min | Backup automático do container |

## Admin (dono)

- **SSH:** [`ssh-runbook`](ssh-runbook.md) — start/stop/restart/backup
- **Console:** `devcommands` no jogo (F5)

## See also

- [[valheim-server]] — Servidor Valheim (Docker)
- [[ssh-runbook]] — Operação via SSH
- [[kavure]] — Servidor de destino
