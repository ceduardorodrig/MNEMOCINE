---
tags: [homelab, service, zomboid, tutorial]
---

# Zomboid — Onboarding (Jogadores)

Guia para entrar no servidor de Project Zomboid **VaiMorreSim** (kavure).

> Acesso só pela tailnet (**whitelist only**) — quem não estiver na Tailscale usa o navegador do jogo (o servidor é público na lista).

## Dados de conexão

| Item | Valor |
|---|---|
| Nome do servidor | `VaiMorreSim` |
| IP (Tailscale) | `100.124.146.77` |
| Porta | `16261` (UDP) |
| **Senha** | `TuVaiMorre` |
| Máx. jogadores | 15 |
| Build | B42 (**stable**) |
| Mods | ~65 Workshop |

## Como entrar

**Opção A — navegador do jogo (não precisa de Tailscale):**
1. Jogo → **Join** → procurar por `VaiMorreSim` na lista de servidores (é público).
2. Conectar → digitar a senha `TuVaiMorre`.

**Opção B — direto (Tailscale):**
1. Aceitar o host `kavure` na sua tailnet (se ainda não tiver).
2. Jogo → **Join** → **Enter IP** → `100.124.146.77` (porta 16261) → conectar.
3. Senha `TuVaiMorre`.

> Se o jogo pedir para baixar mods do Workshop ao conectar, aceite — o servidor envia a lista automaticamente na primeira entrada.

> **Avisos de manutenção:** antes de reinícios/desligamentos, um **banner amarelo no topo da tela** (`[SERVER] ...`) avisa com ~20s de antecedência — o servidor fica fora ~1 min para salvar e atualizar os mods. Restarts automáticos: 05:00, 11:00, 17:00 e 23:00 (são pulados se houver players online).

## Restart remoto pelo celular (update de mods)

Se precisar reiniciar fora de casa (ex.: atualizou um mod no Workshop e quer puxar agora), use o **painel** pelo navegador do celular:

1. Celular conectado na **Tailscale** (MagicDNS) — `http://kavure.chimaera-heptatonic.ts.net:3001`.
2. Logar no **Zomboid Control Panel** (conta admin do painel).
3. Aba **Console** → digitar `save` → Enter (salva o mundo).
4. ~5s depois → digitar `quit` → Enter.
5. O jogo salva e sai → o **Docker reinicia o container sozinho** (`restart: unless-stopped`) → no boot o servidor re-baixa/atualiza os mods do Workshop (~1-2 min fora).

> Validado em 07/08/2026. Alternativa via SSH (Termius/Termux + Tailscale): `tailscale ssh kavure@kavure` → `zomboid-restart` (1 comando, faz save + restart).

## Mods

- Lista completa (WorkshopItems/Mods) gerida pelo **Zomboid Control Panel** (aba Mods) — ver [`zomboid-control-panel`](zomboid-control-panel.md).
- Referência técnica em [`project-zomboid`](project-zomboid.md) (`Mods=`/`WorkshopItems=` no `pzserver.ini`).
- Atualização de mods: automática no restart **4x/dia** (05:00, 11:00, 17:00, 23:00 — o servidor baixa updates do Workshop no boot).

## Admin (dono)

- **Painel web:** `http://kavure.chimaera-heptatonic.ts.net:3001` — RCON, players, mapa, mods, backup, eventos.
- **SSH/scripts:** [`ssh-runbook`](ssh-runbook.md) — start/stop/restart/update/backup.
- **Players admins:** contas e permissões vêm do `players.db` migrado (inalterado).

## See also
- [[project-zomboid]] — Servidor Project Zomboid (Docker)
- [[ssh-runbook]] — Operação via SSH
- [[zomboid-control-panel]] — Painel web
