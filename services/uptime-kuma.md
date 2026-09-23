---
tags: [homelab, service, uptime-kuma, monitoring, server, ybytu]
---

# Uptime Kuma

**Função:** Monitoramento de uptime com probes HTTP(S), TCP e Ping sobre Tailscale.

## Deployment

- **Servidor:** ybytu
- **Container:** `uptime-kuma`
- **Imagem:** `louislam/uptime-kuma:latest`
- **Porta:** `3002` (bind `0.0.0.0`)
- **Volume:** `uptime-kuma` → `/app/data`
- **Rede:** `bridge`
- **Restart:** `unless-stopped`
- **Comando inicial:**

```bash
docker run -d \
  --restart unless-stopped \
  -p 3002:3001 \
  -v uptime-kuma:/app/data \
  --cap-add=NET_RAW \
  louislam/uptime-kuma:latest
```

## Acesso

- **URL:** `http://ybytu.chimaera-heptatonic.ts.net:3002`
- **Login:** admin — a senha é **hash (bcrypt)** no SQLite (`kuma.db`), **não vai ao store sops** (não reutilizável).
- **Reset de senha (28/08/2026):**
  ```bash
  docker exec -it uptime-kuma npm run reset-password
  ```
  (interativo; ou `npm run reset-password -- --new_password='<nova>'`). Remove 2FA: `npm run remove-2fa`. Ver [Reset-Password-via-CLI](https://github.com/louislam/uptime-kuma/wiki/Reset-Password-via-CLI).

## Motivação

Oracle Cloud reivindica VMs gratuitas (AMD Free Tier) se o uso médio de CPU ficar abaixo de 20% e rede abaixo de 20% por 7 dias consecutivos. Uptime Kuma foi instalado para gerar tráfego de monitoramento real (HTTP, TCP, Ping) via Tailscale para todos os serviços do homelab, mantendo as VMs ativas.

## Monitores

41 monitores configurados diretamente no SQLite (`/app/data/kuma.db`), organizados em 4 grupos:

| Grupo | Qtd | Alvos |
|---|---|---|
| Psicopompo | 8 | API (interno), Backup, Crafty, Minecraft, Glances, Ping, Syncthing |
| Ybytu | 7 | AdGuard, Homepage, Uptime Kuma, Filebrowser, Syncthing, Glances, Changedetection, Ntfy |
| Ybyra | 6 | Proxy API (externo), SPA, Funnel, Umami, Datavis, Glances, Ping |
| Kuaray | ~14 | *arr stack, streaming, DNS |

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

> ⚠️ **Achado (22/09/2026):** o container `uptime-kuma` foi **recriado em 16/09** e o DB atual (`~/homelab/uptime-kuma/data/kuma.db`) está **sem NENHUM monitor** (tabela `monitor` vazia, `sqlite_sequence` = 0, API `/api/status-page/heartbeat/1` vazia). Todos os monitores documentados acima (e o monitor #48 datavis) **foram perdidos na recriação**. O volume docker `uptime-kuma-data` (nomeado) existe mas está vazio. **Pendente:** reconstruir os monitores no painel (porta 3002) ou restaurar de backup antigo — ver [`services/monitoring.md`](monitoring.md) para a lista completa.

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
