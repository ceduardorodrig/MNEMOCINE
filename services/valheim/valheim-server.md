---
tags: [homelab, service, valheim, gaming]
---

# Valheim — Servidor Dedicated

Servidor dedicado Valheim 1.0 (Deep North) com BepInEx e mods QoL.

**Servidor:** kavure
**Portas:** UDP 2456-2458
**Senha:** `HalVeim1235`
**Mundo:** `Fimbulvetr`
**IP (Tailscale):** `100.124.146.77`

> **Ativo desde 09/09/2026:** Valheim 1.0.12 (network version 40) via `mbround18/valheim:3` com BepInEx + 3 mods server-side. Servidor público=false (acesso pela tailnet). Backup automático a cada 30min via container + offbox NFS. Portais em modo casual (ores passam).

## Stack

| Container | Imagem | Função |
|---|---|---|
| valheim-server | mbround18/valheim:3 | Servidor dedicated + BepInEx + mods |

## Portas

| Porta | Protocolo | Uso |
|---|---|---|
| 2456 | UDP | Jogo (principal) |
| 2457 | UDP | Jogo (backup) |
| 2458 | UDP | Jogo (backup) |

## Dados

| Item | Valor |
|---|---|
| Mundo | `Fimbulvetr` |
| Servidor | `Mnemocine Vikings` |
| Senha | `HalVeim1235` |
| Public | `false` (acesso só via tailnet) |
| BepInEx | Sim (`TYPE: BepInEx`) |
| Modifiers | `portals=casual` |
| Auto-update | 03:00 diário (steamcmd) |
| Auto-backup | A cada 30 min → offbox NFS |
| TZ | America/Sao_Paulo |

## World Modifiers

| Modifier | Valor | Efeito |
|---|---|---|
| portals | `casual` | Ores/minérios passam por portais |

## Módulos SmoothServer desabilitados

| Módulo | Config | Motivo |
|---|---|---|
| `[Compression] Enabled` | `false` | Incompatível com Valheim 1.0.12 (frame tag `0x48`, mundo vazio). Fix em 12/09/2026. |
| `[Map] Enabled` | `false` | Compartilhamento de mapa desabilitado a pedido (20/09/2026). Cada jogador vê só o que explorou + pins locais. |

> Ambos persistem entre restarts porque `Profile = Custom` está ativo (sem sobrescrita automática de defaults).

## Mods (3 ativos — server-side)

| Mod | Versão | Função |
|---|---|---|
| Server_devcommands | 1.113 | Devcommands + admin tools |
| SmoothServer | 0.6.0 | Performance de rede |
| FuelEternal | 1.2.1 | Fogo nunca apaga |

**Todos os mods são server-side** — clientes vanilla conectam sem problema.

### Mods client-side (instalar no cliente, não no servidor)

| Mod | Versão | Função |
|---|---|---|
| Gizmo (ComfyMods) | 1.16.0 | Rotação de construção (Ctrl+scroll) |
| CameraTweaks (Searica) | 1.3.1 | Zoom e FOV customizável |

### Mods removidos do servidor

| Mod | Motivo |
|---|---|
| Gizmo (ComfyMods) | Client-side only — removido do servidor em 16/09/2026; cada jogador instala no cliente |
| CameraTweaks (Searica) | Client-side only — removido do servidor em 16/09/2026; cada jogador instala no cliente |
| BuildCamera (Azumatt) | Kickava clientes vanilla (`EnforceClientMod: true`); sem demanda |
| AAA_Crafting | `Inventory.AddItem` mudou assinatura (incompatível com 1.0) |
| aruberuto/AreaRepair | Harmony patch crash em `Awake` (incompatível com 1.0) |
| Azumatt/AzuAreaRepair | Harmony patch crash em `Awake` (incompatível com 1.0) |

## Dados no disco

```
/srv/data/valheim/
├── docker-compose.yml    ← compose (MODS, MODIFIERS: portals=casual)
├── .env                  ← VALHEIM_SERVER_PASS
├── config/               ← BepInEx + configurações
│   └── bepinex/          ← configs dos mods (persistidas entre restarts)
├── data/                 ← binário do servidor (volume → /home/steam/valheim)
├── saves/                ← MUNDO + auto-backups do jogo (volume → /home/steam/.config/unity3d/IronGate/Valheim)
│   └── worlds_local/     ← Fimbulvetr (mundo ativo) + Fimbulvetr_backup_auto-* (auto-backups nativos do jogo)
├── backups/              ← AUTO_BACKUP do container (Odin) → /home/steam/backups (persistido desde 13/09)
└── offbox/               ← mount NFS → psicopompo (backup off-box)
```

## Backup

> **Corrigido (13/09/2026):** o backup off-box estava **quebrado** — o script `valheim-backup` apontava para `/srv/data/valheim/config/backups/` (padrão de outra imagem), pasta que **não existe** neste setup. O mundo real vive em `saves/worlds_local/`. Corrigido o script (fonte → `saves/worlds_local/`) + adicionado mount `./backups:/home/steam/backups` no compose para o AUTO_BACKUP do Odin não perder backup no recreate.

- **Off-box (principal):** o **auto-backup nativo do jogo** grava em `saves/worlds_local/Fimbulvetr_backup_auto-*` → espelhado por `valheim-backup` (rsync) para NFS psicopompo (`/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`). Cobre o mundo ativo + backups.
- **AUTO_BACKUP do container (Odin):** a cada 30 min → `/home/steam/backups` (`./backups`, persistido desde 13/09). Retenção `AUTO_BACKUP_DAYS_TO_LIVE=7`.
- **Schedule:** systemd timer `hl-valheim-backup.timer` (05:30, `Persistent=true`) → health file `/srv/health/valheim-backup-last-ok` (alerta `BackupNotRun` cobre).

## Agendamentos (systemd timers)

```ini
# hl-valheim-restart.timer — 05:00 diário (Persistent=true)
# hl-valheim-backup.timer  — 05:30 diário (Persistent=true)
```

- **watchtower** (container da stack `ops`, **03:00 BRT**): atualiza `valheim-server` — recria container com stop-timeout 30s; `AUTO_BACKUP_ON_UPDATE=1` salva antes.

## Acesso

```bash
tailscale ssh kavure@kavure
valheim-status    # status completo
```

## Troubleshooting

### SmoothServer Compression incompatível com Valheim 1.0.12 (mundo vazio)

**Sintomas:** mundo carrega vazio (terreno OK, sem árvores/construções), erro `unknown frame tag 0x48` nos logs, `zdosSent/s=0` (servidor não envia ZDOs pro client).

**Causa raiz (diagnóstico final 12/09/2026):** o módulo `[Compression]` do SmoothServer 0.6.0 é **incompatível com o Valheim 1.0.12** (protocolo de rede mudou, frame tag `0x48`). **Não** é DLL corrompido — mesmo reinstalado limpo, o problema voltava.

**O detalhe que impediu o fix antes:** com `Profile = Default`, o SmoothServer 0.6.0 **força os valores default de volta** no config a cada boot — qualquer edição em `Compression.Enabled` era sobrescrita silenciosamente.

**Fix (confirmado):**
1. Editar `[Profiles] Profile = Default` → `Profile = Custom` (para o plugin não sobrescrever nada)
2. Editar `[Compression] Enabled = true` → `Enabled = false`
3. Restart container

**Como editar o config (importante):** editar via **`docker exec`** dentro do container, com aspas aninhadas corretas. Editar via `echo senha | sudo -S sed` no host não persiste.

```bash
ssh kavure@kavure
echo 'SENHA' | sudo -S docker exec valheim-server bash -c \
  'sed -i "281s/Profile = Default/Profile = Custom/; 90s/Enabled = true/Enabled = false/" \
  /home/steam/valheim/BepInEx/config/Nosferatu.SmoothServer.cfg'
```

> **Nunca** delete arquivos de `saves/` ou `worlds_local/` — eles contêm o mundo.

### Erros de edição no config via host não persistem

O arquivo do config do SmoothServer é montado de `./config/bepinex` no host para `/home/steam/valheim/BepInEx/config` no container. Edições feitas no host com `echo senha | sudo -S sed ...` **não aplicam** (problema de stdin/aspas no SSH). Use sempre `docker exec` no container.

## See also

- [[onboarding]] — Guia para jogadores
- [[ssh-runbook]] — Operação via SSH
- [[kavure]] — Servidor de destino
- [[project-zomboid]] — Servidor Zomboid (padrão de referência)
