---
tags: [homelab, service, ntfy, monitoring, ybytu]
---

# Ntfy

Servidor de notificações push. Roda no ybytu (Docker).

**Servidor:** ybytu

## Deploy

Config-as-code (Docker Compose) no ybytu: `/home/ubuntu/homelab/ntfy/compose.yml`.

```yaml
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    command: ["serve"]
    volumes: [ "./data:/etc/ntfy" ]
    ports: [ "8083:80" ]
    healthcheck: wget -q -O /dev/null http://127.0.0.1:80/v1/health
```

> ⚠️ **Não há `server.yml`** — o ntfy roda no **padrão** (sem auth/ACL). `./data` está vazio.

## Acesso

- URL: `http://ybytu:8083` (MagicDNS) · `http://100.115.253.109:8083` · `http://ybytu.chimaera-heptatonic.ts.net:8083`
- Publicar: `curl -d "msg" -H "Title: ..." http://ybytu:8083/<topico>`

## Tópicos (09/10/2026)

| Tópico | Origem | Uso |
|---|---|---|
| **`backup`** | scripts de backup (config, restic, agentic-ai, docs-sync, n8n, monitoring, zomboid, valheim, sumaenima, miracena, rclone, scryfall, arandu) | **OK/FALHOU** de cada backup |
| **`alerts`** | **Uptime Kuma** (todos os ~40 monitores Down/Up) **+ `alertmanager-ntfy`** (Prometheus/Alertmanager) **+ `arm-hunt`** | downtime de serviços + alertas do homelab + captura da ARM |
| `chimaera-heptatonic` | Changedetection.io | mudanças em páginas |
| ~~`uptimekuma`~~ | **não usado** — o Uptime Kuma publica em **`/alerts`** (opção A, 08/10/2026) | — |

> **Assinaturas no celular (estado atual):** **`backup`** e **`alerts`** (o `/alerts` cobre uptime + ARM).

> **Tópicos sem auth** — qualquer nó da tailnet pode publicar/assinar. O ntfy **é privado à tailnet** (bind `0.0.0.0` mas o host só é acessível via tailnet). Considerar um `server.yml` com `auth` se quiser restringir.

## Integrações

- **App ntfy no celular** — assinar os tópicos **`backup`** (singular!) e **`alerts`**.
  No app: *Settings → Manage users → Add* → URL do servidor `http://ybytu.chimaera-heptatonic.ts.net:8083` (ou via tailnet), depois **Subscribe** em cada tópico.
- Uptime Kuma → ntfy **em `/alerts`** (config `ntfy (alerts)`), não `/uptimekuma`.
- **Prometheus/Alertmanager → ntfy via bridge `alertmanager-ntfy`** (09/10/2026): o
  Alertmanager **não aceita template** no `webhook_configs` — apontar direto pro tópico
  publicava o **JSON cru** como mensagem (sem título), poluindo o `/alerts` com "código".
  O bridge (container `monitoring-alertmanager-ntfy` no kavure) formata: título
  `🚨 Disparou`/`✅ Resolvido` + summary, prioridade `urgent`/`default`, clique → gráfico.
  Detalhes em [`monitoring.md`](monitoring.md).
- Changedetection.io → `ntfy://100.115.253.109:8083/chimaera-heptatonic`

> **Backup da config:** o `config-backup` do ybytu espelha `/home/ubuntu/homelab` (inclui o `compose.yml`). O `./data` (vazio hoje) **não** é espelhado — se um `server.yml` for criado, adicionar ao `SRC_DIRS`.


## RAM

~15 MB.
