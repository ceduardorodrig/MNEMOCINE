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
| **Senha** | no store sops (`VALHEIM_SERVER_PASS`) |
| Mundo | `Fimbulvetr` |
| Versão | **1.0.16** (Deep North) — atualiza sozinho às 03:00 |

## Como entrar

1. Aceitar o host `kavure` na sua tailnet (se ainda não tiver).
2. Abrir Valheim → **Join Game**.
3. Adicionar servidor manualmente:
   - IP: `100.124.146.77`
   - Porta: `2456`
4. Conectar → digitar a senha (ver `VALHEIM_SERVER_PASS` no store sops).

> O servidor é **privado** (`public=false`) — não aparece na lista de servidores. Só acessível via IP direto na tailnet.

## Mods

O servidor roda BepInEx com mods **server-side** — quem conecta com o jogo vanilla entra normal, sem instalar nada.

### Client-side (cada jogador instala no PC)

| Mod | Função | Para quem |
|---|---|---|
| Gizmo (ComfyMods) | Rotação de construção (Ctrl+scroll) | todos |
| CameraTweaks (Searica) | Zoom e FOV customizável | todos |
| Server Devcommands (JereKuusela) | devcommands de **admin** (god/fly/spawn) | **só admins** |

Instalação: BepInExPack + o mod, via r2modman/Thunderstore Mod Manager no PC.

> **Corrigido em 26/09/2026:** esta seção antes afirmava que "o cliente baixa os mods automaticamente ao conectar (BepInEx + 4 mods QoL)". **Não acontece** — mods client-side não são baixados pelo servidor; cada um instala no PC.

### Console (F5) — como abrir

O console **não abre por padrão**. Faça isso **no seu PC**, uma vez:

- **Settings → Gameplay → Enable Console** (o caminho normal), **ou**
- parâmetro de launch `-console` no Steam.

Depois de conectar no servidor, **F5** abre o console. Sem esse passo o F5 não faz nada.

### O que cada perfil pode fazer

| | Comandos | Precisa de quê |
|---|---|---|
| **Admin** (na lista) | `kick`, `ban`, `unban`, `banned`, `save` + `devcommands` (`god`, `fly`, `pos`, `freefly`, `event`, `stopevent`, …) | estar na lista de admin do servidor |
| **Jogador normal** | `devcommands` só pra si mesmo (efeito local) | nada |

> **Mod client-side:** os *devcommands* de admin (spawn, god, fly) exigem o mod **Server Devcommands** instalado **no seu PC** (Thunderstore → `JereKuusela/Server_devcommands`, junto do BepInExPack). O servidor já tem do lado dele — sem o mod no cliente, os comandos de admin não aparecem pra você. Os nativos (kick/ban/save) funcionam sem mod nenhum.

> **Corrigido em 26/09/2026:** esta seção antes dizia *"os comandos são locais, não há admin remoto"*. **Estava errado** — o admin existe e é configurado no servidor (ver [[valheim-server#Admin — permissions.yaml]]). O que acontece é que quase ninguém estava na lista de admin.

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

## Admin

**Admins do servidor:**

| Jogador | Nome in-game | SteamID64 |
|---|---|---|
| Carlos (dono) | AhNo CaM | `76561198075365006` |
| Titi / Twister / Lira | Lira | `76561198009545651` |
| Henrique | BiM | `76561197988953037` |

> Admin é por **conta Steam**, não por personagem — quem tem o ID na lista é admin em todos os personagens dela (Titi, Twister e Lira são a mesma conta).

- **SSH:** [`ssh-runbook`](ssh-runbook.md) — start/stop/restart/backup
- **In-game:** F5 (com Enable Console ligado) → `god`, `fly`, `pos`, `kick <player>`, `save`
- **Pedir admin:** mandar o SteamID64 (ou o `V_` que aparece no overlay F2 dentro do jogo) pro dono — ele adiciona na lista

## See also

- [[valheim-server]] — Servidor Valheim (Docker)
- [[ssh-runbook]] — Operação via SSH
- [[kavure]] — Servidor de destino
