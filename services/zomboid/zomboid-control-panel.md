---
tags: [homelab, service, zomboid-panel, gaming]
---

# Zomboid Control Panel

Painel web de administração para o servidor de **Project Zomboid** — o "Crafty" do Zomboid.

**Projeto:** [fpsacha/zomboid-control-panel](https://github.com/fpsacha/zomboid-control-panel) (MIT, ativo, testado até B42.18)
**Versão:** v1.1.36 (atualizado 07/08/2026 — imagem `ghcr.io/fpsacha/zomboid-panel:latest`; o watchtower também atualiza às 03:00)
**Servidor:** kavure (ativo desde 06/08/2026)
**Acesso:** via Tailscale

## Recursos

- **Controle do servidor** — start/stop/restart/save, status, uptime
- **Console + RCON** — terminal com histórico (elimina SSH/sudo para administrar)
- **Mod manager** — detecta updates do Workshop, resolve `Mods=`/`WorkshopItems=` automaticamente
- **Backups** com restore pela UI
- **Agendador** — restarts/saves/broadcast (substitui timers systemd)
- Extras: mapa do mundo ao vivo, Discord bot, editor INI, eventos/clima

## Requisitos

- Servidor PZ com **RCON habilitado**: `RCONPort=27015` + `RCONPassword=...` no `pzserver.ini`
- Acesso de rede do painel ao servidor (mesma máquina, LAN ou Tailscale)
- Para PanelBridge (features avançadas): `DoLuaChecksum=false` no server `.ini`

## Instalação (kavure)

Opções: **Docker** (`ghcr.io/fpsacha/zomboid-panel:latest`) ou binário Linux (`./start.sh`).

```bash
mkdir -p ~/zomboid-panel && cd ~/zomboid-panel
curl -O https://raw.githubusercontent.com/fpsacha/zomboid-control-panel/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/fpsacha/zomboid-control-panel/main/.env.example
mv .env.example .env
docker compose up -d
```

- Acessa em `http://localhost:3001` (ou via Tailscale)
- Configurar: caminho do server PZ, dados, RCON (host/port/senha)
- No Docker, usar `PUID`/`PGID` dos donos das pastas do PZ

## Segurança

- JWT em todas as rotas + rate limiting
- Não expor a porta 3001 diretamente à internet — usar Tailscale ou reverse proxy com HTTPS

## Mods e caminho do Workshop

- O painel lê os mods em `/pz-server/steamapps/workshop` — o compose do painel faz bind de `/srv/data/zomboid/workshop-mods` nesse path (mesmo overlay do container do jogo).
- A cópia antiga em `pz-dedicated/steamapps/workshop/` foi **removida** (07/08/2026) — causava "Mod update available" eterno (local desatualizado vs Steam).
- O Mod manager compara o `timeUpdated` local (da pasta) com a Steam API. Se aparecer "update available", reinicie o jogo (`zomboid-restart`) para baixar a atualização; o auto-scan do painel (5 min) então mostra tudo em dia.

## PanelBridge

- Mod Lua server-side que dá ao painel ações fora do RCON (teleport, heal, clima, inventário...). Vive em `pz-dedicated/media/lua/server/PanelBridge.lua`.
- **Fix 07/08/2026:** a pasta `media/lua/server/` era `root:root` → o painel (uid 1000) não conseguia **auto-atualizar** o bridge (EACCES). `sudo chown -R kavure:kavure /srv/data/zomboid/pz-dedicated/media/lua/server` resolveu — auto-update `1.7.21 → 1.7.23 → 1.7.24` confirmado no log do painel (após update do painel para v1.1.36).

## See also
- [[project-zomboid]] — Servidor Project Zomboid
- [[kavure]] — Servidor de destino
- [[kavure-migration-plan]] — Plano de migração
