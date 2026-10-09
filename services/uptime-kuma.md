---
tags: [homelab, service, uptime-kuma, monitoring, server, ybytu]
---

# Uptime Kuma

**Função:** Monitoramento de uptime com probes HTTP(S), TCP e Ping sobre Tailscale.

## Deployment

- **Servidor:** ybytu
- **Container:** `uptime-kuma`
- **Imagem:** `louislam/uptime-kuma:latest`
- **Rede:** **`network_mode: host`** (07/10/2026) + `UPTIME_KUMA_PORT: 3002` — necessário porque o `INPUT` do ybytu é **default-deny** (só loopback é aceito): em bridge, o container **não alcançava** os serviços do host (`EHOSTUNREACH` em 3002/8082/8083/61208; só a 3000 passava por DNAT).
- **Volume:** `./data` → `/app/data`
- **Compose:** `/home/ubuntu/homelab/uptime-kuma/compose.yml` (backup do anterior: `.bak-20261007-hostnet`)
- **Restart:** `unless-stopped`

> ⚠️ **`kuma.db` NÃO é espelhado no NAS:** o `config-backup` exclui `*.db` — foi por isso que os
> ~38 monitores perdidos na recriação de 16/09 ficaram **irrecuperáveis**. Reconstruídos em
> 07/10/2026 a partir do Homepage (ver abaixo). **Pendência:** incluir um export do Uptime Kuma
> (ou o `kuma.db`) no backup.

## Acesso

- **URL:** `http://ybytu.chimaera-heptatonic.ts.net:3002`
- **Login:** `admin` — credencial agora no **cofre sops** (`UPTIME_KUMA_ADMIN_USER` / `UPTIME_KUMA_ADMIN_PASSWORD`, adicionadas 06/10/2026). No SQLite a senha é **hash (bcrypt)**, não reutilizável.
- **Reset de senha (28/08/2026):**
  ```bash
  docker exec -it uptime-kuma npm run reset-password
  ```
  (interativo; ou `npm run reset-password -- --new_password='<nova>'`). Remove 2FA: `npm run remove-2fa`. Ver [Reset-Password-via-CLI](https://github.com/louislam/uptime-kuma/wiki/Reset-Password-via-CLI).

## Motivação

Oracle Cloud reivindica VMs gratuitas (AMD Free Tier) se o uso médio de CPU ficar abaixo de 20% e rede abaixo de 20% por 7 dias consecutivos. Uptime Kuma foi instalado para gerar tráfego de monitoramento real (HTTP, TCP, Ping) via Tailscale para todos os serviços do homelab, mantendo as VMs ativas.

## Monitores

> **Reconstruído em 07/10/2026 — 51 monitores, todos UP.** A lista abaixo (41, de antes) é
> histórica. O estado atual foi recriado a partir do **Homepage** (`services.yaml`) como fonte
> das URLs + **3 monitores de DNS** (Pi-hole, AdGuard e caminho da casa):
> - **48 HTTP** (serviços com URL) + **6 ping** (psicopompo, kavure, kuaray, ybytu, ybyra, kururu)… total 54 nomes,
>   dos quais **51 ficaram ativos** após ajuste de códigos aceitos (registry 400/401, transmission 401/409).
> - Serviços locais ao ybytu monitorados via **`127.0.0.1`** (host net); `glances` via IP da tailnet (escuta só lá).
> - Método: Socket.IO (`login` → `deleteMonitor` → `add`), por script Node descartável dentro do container.

### Lista histórica (41 monitores, pré-16/09)

41 monitores configurados diretamente no SQLite (`/app/data/kuma.db`), organizados em 4 grupos:

| Grupo | Qtd | Alvos |
|---|---|---|
| Kavure | ~12 | Swarm sae-core (API, backup, Valkey), Jogos (Minecraft/Crafty, Zomboid, Valheim), Home Assistant, Pi-hole, Glances |
| Psicopompo | 4 | StênioREC, Glances, Ping, Syncthing |
| Ybytu | 7 | AdGuard, Homepage, Uptime Kuma, Filebrowser, Syncthing, Glances, Changedetection, Ntfy |
| Ybyra | 6 | Proxy API (externo), SPA, Funnel, Umami, Datavis, Glances, Ping |
| Kuaray | ~5 | Standby mirror, Glances, Ping |

### DNS — resolução (reconstruídos 06/10/2026)

Criados via **Socket.IO** (a API do próprio app, não por edição do SQLite):

| ID | Nome | Tipo | Alvo |
|---|---|---|---|
| 1 | DNS · Pi-hole (kavure) | DNS (A) | `100.124.146.77` |
| 2 | DNS · AdGuard (ybytu) | DNS (A) | `100.115.253.109` |
| 3 | DNS · Caminho da casa | DNS (A) | `100.100.100.100` (corrida Tailscale) |

> Estes três cobrem a cadeia inteira: se o `unbound` (ou, na era anterior, o `dnscrypt-proxy`) do kavure morrer, o monitor 1 dispara; o 3 valida o que os aparelhos realmente usam. Ver [`unbound`](unbound.md).

> **Histórico de migração:** anteriormente, Crafty/Minecraft e a API ficavam no Psicopompo, e *arr/HA no Kuaray. Após a consolidação no Kavure (08-09/2026), os probes de serviços foram remapeados para seus respectivos hosts reais.

### Divisão Borda vs Física

Todo monitor de serviço que passa pelo Nginx do Ybyra foi renomeado com prefixo `Proxy` para deixar claro que é o ponto de entrada de borda, não o serviço físico:

| ID | Nome | URL | O que monitora |
|---|---|---|---|
| 4 | Ybyra - Proxy API Sumænimá (Externo) | `http://100.66.224.34/api/health` | Proxy reverso Nginx → API no kavure |
| 5 | Ybyra - Proxy Umami | `http://100.66.224.34/` | Proxy Nginx → Umami no Ybyra |
| 15 | Ybyra - Proxy SPA Sumænimá | `http://100.66.224.34/` | Proxy Nginx → Frontend SPA |
| 48 | ~~Ybyra - Proxy Datavis Sumænimá~~ | ~~`http://100.66.224.34/api/datavis/health`~~ | ~~Proxy Nginx → Datavis no Ybyra~~ **removido 22/09/2026 (legado)** |
| 46 | Ybyra - Funnel Sumænimá | `https://sumaenima.chimaera-heptatonic.ts.net` | Tailscale Funnel público (HTTPS) |
| 50 | Psicopompo - Sumænimá API (Interno) | `http://100.124.146.77:9090/api/health` | API no kavure via Tailscale |

> ⚠️ **Achado (22/09/2026):** o container `uptime-kuma` foi **recriado em 16/09** e o DB (`~/homelab/uptime-kuma/data/kuma.db`) ficou **sem NENHUM monitor e sem usuário** (tabela `monitor` vazia, `user` vazia, `/setup` ativo). Todos os monitores documentados acima (e o monitor #48 datavis) **foram perdidos na recriação**.
>
> **Parcialmente corrigido em 06/10/2026:** usuário `admin` recriado e os **3 monitores DNS** adicionados (tabela acima) via Socket.IO. **Pendente:** reconstruir os demais (~38) monitores de serviço listados nesta página — ver [`services/monitoring.md`](monitoring.md) para a lista completa. Método usado (script Node descartável dentro do container, removido após uso): eventos `needSetup` → `setup` → `login` → `add`.

### Notificações — ntfy (recriado 07/10/2026)

A recriação de 16/09 apagou **também as notificações** (tabela `notification` com 0 linhas).
Recriada via Socket.IO — evento `addNotification(notification, notificationID, callback)`
**três** argumentos; passar dois faz o callback ser interpretado como ID e a chamada trava:

| Campo | Valor |
|---|---|
| Tipo | `ntfy` |
| Servidor | `http://127.0.0.1:8083` (o Uptime Kuma roda no mesmo host, em `network_mode: host`) |
| Tópico | **`alerts`** (o mesmo do Alertmanager — `http://ybytu…:8083/alerts`) |
| Autenticação | nenhuma (o ntfy do homelab não usa auth) |
| Prioridade | 3 |
| `isDefault` / `applyExisting` | `true` / `true` → **51 vínculos** (todos os monitores) |

**Validado de ponta a ponta:** `testNotification` enviou mensagem real e ela chegou ao tópico
`alerts` (`alerts [Uptime-Kuma]`).

> O outro tópico em uso no homelab é **`backup`** (alertas do `config-backup`).

### Kernel Guard

O driver `pm_tailscale_funnel` (kernel) verifica periodicamente:
- `edge.yml` tem `configs:` e `ports: 80` corretos
- `serve.json` montado via Docker Configs
- Funnel responde HTTPS 200
- Falha se qualquer config for removida — impede perda acidental do funnel

## Observações

- Configurado sem Docker Compose (comando `docker run` direto).
- Monitores foram inseridos via SQLite porque o Uptime Kuma não expõe API REST para criação; usa Socket.IO.
- O hash bcrypt da senha foi corrompido uma vez pelo bash (expansão de `$`); corrigido gerando o hash dentro do container via `node -e "bcrypt.hashSync(...)"`.
