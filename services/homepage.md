---
tags: [homelab, service, homepage, monitoring]
---

# Homepage

Dashboard central do homelab — agrega links e status de todos os serviços.

**Servidor:** ybytu
**Porta:** `3001`
**URL:** `http://ybytu.chimaera-heptatonic.ts.net:3001`

## Stack

| Container | Imagem | Status |
|---|---|---|
| homepage | ghcr.io/gethomepage/homepage:latest | Up |

## Configuração

O Homepage usa arquivos YAML em `/app/config/` (host: `/home/ubuntu/homelab/homepage/config/`).

Arquivos de configuração:
- `docker.yaml` — instâncias Docker conectadas (status up/down automático)
- `services.yaml` — serviços por grupo
- `bookmarks.yaml` — favoritos
- `settings.yaml` — tema e layout
- `widgets.yaml` — widgets (Disk, Weather, etc.)

### Docker instances (`docker.yaml`)

| Instância | Endpoint | Servidor |
|---|---|---|
| `ybytu` | `/var/run/docker.sock` | local |
| `psicopompo` | `100.82.51.112:2375` | dockerproxy |
| `kuaray` | `100.94.209.99:2375` | dockerproxy |
| `kavure` | `100.124.146.77:2375` | dockerproxy |

Cada serviço no `services.yaml` com `server:` + `container:` mostra status up/down automaticamente. Containers Exited (ex: kuaray) aparecem como down sem config manual.

### Grupos do `services.yaml` (10/09/2026)

Ordem atual (cloud no final):
1. **Psicopompo (Workstation)** — **Ligar Kavure (WoL)**, Syncthing, Punktfunk, Glances
2. **Kavure (Serviços)** — **Ligar Psicopompo (WoL)**, Project Zomboid, Zomboid Control Panel, Crafty Controller, Minecraft Server, Valheim Server, Sumænimá API, Sumænimá Backup, **AioStreams, Comet**, **WordPress (10/09)**, **Directus (10/09)**, **NPM Admin (10/09)**, **n8n (10/09 — badge Docker)**, **Grafana (28/08)**, **Prometheus (28/08)**, **SearXNG (28/08)**, Pi-hole, Home Assistant, Navidrome, Calibre Web, Glances
3. **Kuaray (Midia e Automacao)** — Syncthing, Transmission, Prowlarr, Lidarr, slskd, FlareSolverr, Soularr, Vert, Glances
4. **Ybytu (Cloud)** — AdGuard Home, Glances, Uptime Kuma, Changedetection, Ntfy
5. **Ybyra (Cloud)** — Sumænimá (Borda Primária), Glances

> **08/08/2026:** **CasaOS removido** (desinstalado do kuaray); **Crafty/Minecraft migrado** p/ o kavure (grupo Kavure); grupos reordenados (cloud no final).
>
> **28/08/2026:** **Infra em todos os grupos** — cada host ganhou badges `Watchtower`, `Autoheal`, `Node Exporter`, `Promtail` (`server:` + `container:`, padrão badge docker) para mostrar o status dos containers de infra/monitoramento. Container names por host: `autoheal-autoheal-1` (kuaray), `monitoring-promtail` (kavure), `promtail` (demais).
>
> **09/08/2026:** **aiostreams e comet migrados do kuaray → kavure** (grupo Kavure, `100.124.146.77:3000` e `:8000`); removidos do grupo Kuaray. URLs internas (tailnet) mantidas no padrão do grupo.
> **Crafty Controller** web movido p/ porta **`8444`** (a `8443` virou funnel do aiostreams — depois migrado p/ `:10000` em 18/09/2026, ver nota abaixo) + badge docker; **Minecraft Server** usa `siteMonitor` do endpoint `minecraft-status` (kavure `:9095`, probe SLP → chip pequeno com status real do jogo).
>
> **Pi-hole e Home Assistant migrados do kuaray → kavure** (grupo Kavure); **Home Assistant** passou para acesso **tailnet-only** (`http://100.124.146.77:8123`, sem Funnel público — 18/09/2026); **AioStreams** movido para Funnel porta **`:10000`** (`kavure.chimaera-heptatonic.ts.net:10000` → `localhost:3000`) — porta `:8443` era inválida para Funnel público Tailscale (suportadas: 443, 8080, 10000); removidos do grupo Kuaray.
>
> **Navidrome e Calibre Web** no grupo Kavure; **Kavita removido (10/08)** — entrada retirada do grupo Kavure e container desinstalado do kavure.
> **Minecraft Server** `description` corrigida p/ **`Docker`** — o server Dominium roda como **subprocesso Java dentro do container `crafty-controller`** (bind-mount `MINECRAFT SERVER` → `/crafty/servers/dominium`); não é container separado nem nativo. Só o probe `minecraft-status.service` (systemd, `:9095`) é nativo.
> **Pi-hole** `icon` trocado p/ **`pi-hole`** (Dashboard Icons colorido; o `pihole.svg` local era monocromático).
>
> **26/08/2026:** **Mosquitto removido do dashboard** (container já removido do kuaray em 16/08 — entrada órfã) e **Rclone GUI removido** (webgui desativado/deletado no psicopompo — porta `46295` liberada; o siteMonitor do homepage era a única conexão à porta). Backup da config: `services.yaml.bak-20260826`.
>
> **01/09/2026:** **Wake-on-LAN adicionado** — entradas "Ligar Kavure" (grupo Psicopompo) e "Ligar Psicopompo" (grupo Kavure) com `href` para o relay WoL (`wol-relay.py`, porta `9096`) + `siteMonitor` pro chip de saúde. Ver [`wol-relay`](wol-relay.md).
>
> **29/08/2026:** **`Sumænimá (Borda Secundária)` removido do grupo Kuaray** — kuaray deprecado no Sumænimá (borda secundária deixa de usar `kuaray:8085`); o standby agora vive no **kavure** (ver `network/service-topology.md`). Grupo Kuaray mantém apenas serviços de mídia/automação do Homelab. **`Sumænimá Backup`** (grupo Kavure) volta a ficar ✅ — o health server `:9092` passou a responder **HEAD** (bug do widget: `BaseHTTPRequestHandler` sem `do_HEAD` → 501 em probe HEAD do Homepage; corrigido 29/08). Monitor aponta para `http://100.124.146.77:9092/health`.
>
> **09/09/2026:** **Valheim Server adicionado** ao grupo Kavure — `valheim-server` (Docker, `mbround18/valheim:3`, porta `2456`/udp). Badge Docker (container `valheim-server`). Ícone `valheim.png` (walkxcode/dashboard-icons). Ver [`valheim-server`](valheim/valheim-server.md).
>
> **10/09/2026:** **Miracena Stack adicionado** ao grupo Kavure — **WordPress** (`miracena-wordpress`, `:8085`), **Directus** (`miracena-directus`, `:8055`), **NPM Admin** (`miracena-nginx-proxy-manager`, `:81`). **n8n atualizado** para badge Docker (`miracena-n8n`). Todos os serviços da stack Miracena agora aparecem no dashboard com status up/down e label `Docker · Miracena` para diferenciação. Ver [`miracena-stack`](miracena-stack.md).

### Padrão de status (CONVENÇÃO — seguir SEMPRE em novas adições)

| Tipo de serviço | Fonte de status | Config no `services.yaml` |
|---|---|---|
| **Serviço HTTP** | Chip `siteMonitor` — ping em **ms** | `siteMonitor: <url>` |
| **Serviço docker sem HTTP** (jogos, MQTT) | Badge Docker (dot running/stopped) | `server:` + `container:` |
| **Serviço nativo** (systemd/processo, sem container) | Chip `siteMonitor` | `siteMonitor: <url>` |

**Regras:**
1. **HTTP → `siteMonitor`** (chip com ms). É o padrão preferido.
2. **Sem HTTP → badge docker** (`server` + `container`). Ex.: Project Zomboid (`pz-server`).
   - **Jogos com protocolo próprio (ex: Minecraft)** → para **chip pequeno (padrão) + status real do jogo**, usar um **mini endpoint HTTP de status** no host e `siteMonitor: <url>`. No kavure: serviço `minecraft-status` (porta `9095`, probe Minecraft SLP em `25565` → 200 up / 503 down). Não usar badge do `crafty-controller` (container fica sempre up e engana) nem widget `minecraft` (renderiza painel de 3 campos, fora do padrão).
3. **⚠️ Evitar widget `customapi`** — renderiza um **painel** (não o chip padrão) e quebra fácil (ex: API error). Só usar se não houver alternativa e validar o visual.
4. **Env vars**: para segredos/configs no gethomepage, definir no `.env` do config dir com o **prefixo `HOMEPAGE_VAR_`** (ex: `HOMEPAGE_VAR_CRAFTY_API_KEY=...`) e referenciar `{{HOMEPAGE_VAR_CRAFTY_API_KEY}}`. Sem o prefixo a var fica indefinida.
5. **Serviços do swarm** (sae-core/sae-edge): badge via nome do serviço + `swarm: true` na instância do `docker.yaml` (dockerproxy com `SERVICES=1`).

### Ícones custom (config/icons/)

| Ícone | Origem |
|---|---|
| `sumaenima.svg` | logo da Sumænimá (`logo-8.svg`) |
| `zomboid.png` | mascote Spiffo do Project Zomboid (`spiffo.png` do repo `fpsacha/zomboid-control-panel`) |
| `zombie.svg` | asset do painel (`zombie.svg` do mesmo repo) |

> **Monitors uptime-kuma (07/08/2026):** corrigido o IP velho do psicopompo (`100.76.19.118` → `100.82.51.112`)
> em Crafty, Syncthing e Sumænimá API; **Sumænimá Backup desativado** (migração); **AdGuard** volta a usar IP de
> bridge (`172.17.0.5:3000`) — containers no ybytu não alcançam o próprio IP tailnet (`EHOSTUNREACH`).
> Ícone da Sumænimá: `config/icons/sumaenima.svg` (origem `logo-8.svg`).

## Manutenção

```bash
docker restart homepage
```

> **Aplicar mudanças de config:** o homepage é **estático** — após editar `services.yaml`/`settings.yaml` etc., regenerar o HTML com o **botão de refresh** (canto inferior direito) ou:
> ```bash
> curl http://127.0.0.1:3001/api/revalidate   # demora ~1 min; retorna quando terminar
> ```
> Não precisa rebuild nem recriar o container. `docker restart homepage` também funciona (recarrega na 1ª requisição).

> **⚠️ Healthcheck:** a imagem usa `wget 127.0.0.1:3000` (IPv4) mas o Next.js 16 escuta em IPv6 — o healthcheck default falha e o autoheal reinicia em loop. Corrigido no `docker-compose.yml` com healthcheck custom usando `[::1]` (06/08/2026). Backup do original em `docker-compose.yml.bak`.

Logs do container são gerenciados pelo Docker e watchtower faz auto-update.
