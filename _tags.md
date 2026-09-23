---
tags: [homelab, meta, taxonomy]
---

# Tag Taxonomy

Single source of truth for allowed tags in this repository.
Tags are always in English.
Every `tags:` in YAML frontmatter must only use tags listed here.

## Categories

### `#homelab` — Everything related to this repo
Root tag. Every file inside `mnemocine` must have it.

### `#server` — Tailnet servers
- `#psicopompo` — Main / gaming / desktop
- `#ybytu` — Cloud / DNS primário
- `#ybyra` — Cloud / futuro SPA host
- `#kuaray` — Media / Home Assistant
- `#kavure` — Servidor de serviços dedicado (Project Zomboid, painel; Sumænimá em migração)

### `#service` — Individual services
- `#adguard` — AdGuard Home (DNS)
- `#aiostreams` — Streaming de áudio/vídeo web
- `#calibre-web` — Biblioteca de eBooks
- `#casaos` — Painel de gerenciamento kuaray (~~ativo~~ — **histórico**, removido 08/08)
- `#comet` — Indexador de Usenet
- `#crafty` — Minecraft server (psicopompo)
- `#duplicati` — Backup de arquivos (~~ativo~~ — **histórico**, removido 06/08)
- `#flaresolverr` — Proxy para Cloudflare
- `#grafana` — Dashboards de observabilidade
- `#home-assistant` — Automação residencial
- `#homepage` — Dashboard de serviços
- `#uptime-kuma` — Monitoramento de uptime
- `#kavita` — Leitor de mangás/quadrinhos (~~ativo~~ — **histórico**, removido 10/08)
- `#lidarr` — Gerenciador de música
- `#loki` — Log aggregation (Loki)
- `#mosquitto` — Broker MQTT
- `#navidrome` — Streaming de música
- `#n8n` — Automação visual (workflows)
- `#pihole` — DNS blocker (kuaray)
- `#portainer` — Gerenciamento Docker
- `#prometheus` — Métricas time-series (Prometheus)
- `#punktfunk` — Streaming de jogos/desktop de baixa latência
- `#changedetection` — Monitoramento de mudanças em páginas
- `#ntfy` — Notificações push
- `#prowlarr` — Indexador de torrent/usenet
- `#soularr` — Integração Soulseek + Lidarr
- `#searxng` — Busca privada (meta-search)
- `#slskd` — Cliente Soulseek
- `#steniobot` — Bot de relatoria com IA
- `#sumaenima-local` — Controle local do SUMAENIMA (sumaenima-ctl)
- `#stremio` — Streaming de filmes/séries
- `#syncthing` — Sincronização de arquivos
- `#transmission` — Cliente torrent
- `#vert` — Microblogging descentralizado
- `#watchtower` — Auto-update de containers
- `#zomboid` — Servidor Project Zomboid
- `#zomboid-panel` — Painel web do Project Zomboid
- `#wol` — Wake-on-LAN, relay de acionamento remoto

### `#network` — Network, DNS and firewall
### `#tailscale` — Tailscale específico
### `#backup` — Estratégia e procedimentos de backup
- `#snapshot` — Snapshots btrfs/snapper (anti-deleção)
- `#snapper` — Snapper específico
- `#btrfs` — Filesystem btrfs
- `#config` — Configurações e compose
- `#compose` — Docker Compose
- `#ritual` — Rituais e verificação de backup
- `#checklist` — Checklist / pendências
### `#recovery` — Disaster recovery
### `#docker` — Docker, compose, containers

### Categorias de serviço
- `#media` — Streaming, música, livros
- `#download` — Torrent, Usenet, Soulseek
- `#dns` — AdGuard, Pi-hole
- `#automation` — Home Assistant, MQTT
- `#monitoring` — Portainer, Homepage, Glances
- `#gaming` — Crafty, Steam, Minecraft
- `#storage` — Discos, pools, volumes, montagens
- `#cloud` — Cloud storage, remotes, sincronização off-site
- `#rclone` — Rclone, mounts, Google Drive
- `#tutorial` — Guias passo-a-passo
- `#todo` — Pendências / WIP
- `#env` — Variáveis de ambiente, portas
- `#sops` — Criptografia de segredos (sops/age), store central
- `#ssl` — Certificados, TLS
- `#meta` — Tags que descrevem o próprio sistema de tags
- `#taxonomy` — Usada na própria _tags.md
- `#agents` — Instruções para agentes de IA
- `#steam` — Steam / jogos no Linux
- `#power` — Energia, suspensão, hibernação (S3/S4)

### `#hardware` — Dispositivos físicos, periféricos, mídias
- `#usb` — Dispositivos USB, pendrives, gravadores
- `#fat` — Filesystem FAT32, vfat, dirty bit
- `#gpu` — Placas de vídeo (GPU) e configuração de vídeo
- `#nvidia` — Driver e configuração NVIDIA (proprietário)
- `#rebar` — ReBAR / Resizable BAR (BIOS da Dell não permite; via Linux sim)

### `#desktop` — Desktop / Workstation (ex.: KDE no psicopompo)
- `#kde` — KDE Plasma (sessão, applets, configuração)
- `#plasma` — Plasma shell / widgets / workarounds
