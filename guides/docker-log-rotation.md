---
tags: [homelab, tutorial, docker, storage, kavure, psicopompo]
---

# Rotação de Logs do Docker (evitar esgotar disco)

Guia canônico da política de logs de containers do homelab — **por que**, **onde** e
**como diagnosticar**. Criado em 29/09/2026 depois de encontrar **1,9 GB** de logs sem
rotação no kavure.

## O problema

O Docker usa por padrão o driver `json-file` **sem rotação**. A documentação oficial é
explícita ([Configure logging drivers](https://docs.docker.com/engine/logging/configure/)):

> *"Use the `local` logging driver to prevent disk-exhaustion. By default, **no
> log-rotation is performed**. As a result, log-files stored by the default `json-file`
> logging driver can cause a significant amount of disk space to be used for containers
> that generate much output, which can lead to **disk space exhaustion**."*

**Medição real (29/09/2026) no kavure:** 1,9 GB, sendo:

| Container | Log |
|---|---|
| `monitoring-cadvisor` | **870 MB** |
| `node-exporter` | **519 MB** |
| `monitoring-loki` | **380 MB** |

O psicopompo tinha apenas 6 MB no total.

## ⚠️ A decisão específica deste homelab: **NÃO** usar o driver `local`

A doc **recomenda** o driver `local` (rotação automática). **Mas aqui isso quebraria a
observabilidade:** o **promtail** lê diretamente os arquivos
`/var/lib/docker/containers/*/*-json.log`. O driver `local` usa outro formato e outro
nome de arquivo → a coleta de log de container pararia.

**Portanto: mantemos `json-file` + rotação explícita.**

## A política aplicada

### Camada 1 — padrão do daemon (novos containers)

`/etc/docker/daemon.json` nos **3 hosts** (psicopompo, kavure, ybyra):

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

> No psicopompo o arquivo já existia (data-root, runtimes, builder) e foi **mesclado**
> via `jq` — nunca sobrescrever. Validar com `dockerd --validate
> --config-file=/etc/docker/daemon.json`.
>
> ⚠️ A doc avisa: *"Existing containers **don't** use the new logging configuration
> automatically"* — só containers **novos** herdam. Por isso a camada 2.
>
> 🛑 **Regra de ouro (02/10/2026):** ao editar este `daemon.json`, **nunca adicionar
> `"live-restore": true`** — os 3 hosts são **nós Swarm** e a chave faz o `dockerd`
> **recusar a subir** no próximo boot (`failed to start cluster component … incompatible
> with swarm mode`). Isso deixou o psicopompo 2 dias sem daemon (30/09) e o kavure sem
> core (02/10). Ver [`AGENTS.md`](../AGENTS.md) §`live-restore` PROIBIDO em host Swarm.

### Camada 2 — por serviço (aplicação imediata, sem restart de daemon)

`logging:` no compose de cada serviço. Aplicado em:

| Onde | Arquivo | Como aplica |
|---|---|---|
| Stack de monitoramento (kavure) | `/srv/data/monitoring/compose.yml` | `docker compose up -d` |
| Node exporter (kavure) | `/srv/data/node-exporter/compose.yml` | `docker compose up -d` |
| Promtail (psicopompo) | `~/homelab/promtail/compose.yml` | `docker compose up -d` |
| Serviços do Swarm | `provisioning/stacks/{core,edge,gpu}.yml` | `docker stack deploy` |

Exemplo do bloco:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## Diagnóstico

```console
# Quanto cada log ocupa (o glob precisa expandir como ROOT — use sudo bash -c)
$ sudo bash -c 'du -b /var/lib/docker/containers/*/*-json.log | sort -nr | head'

# Total
$ sudo du -sh /var/lib/docker/containers

# A rotação está ativa neste container?
$ docker inspect <container> --format '{{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}'
# esperado: json-file map[max-file:3 max-size:10m]
```

**Alívio imediato** (sem parar nada — seguro, o Docker continua escrevendo no mesmo
inode):

```console
$ sudo truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log
```

## 🐛 Bônus: o promtail NÃO estava coletando log de container (corrigido)

Dois defeitos somados, ambos silenciosos (nenhum erro visível):

| Defeito | Estava | Correto |
|---|---|---|
| **Glob** do `__path__` | `*-log.json` | **`*-json.log`** (é o que o driver `json-file` grava) |
| **Mount** no psicopompo | `/var/lib/docker/containers` | `/mnt/NVME_PCI/docker-data/containers` (o `data-root` daquele host não é o padrão) |

Corrigidos em `~/homelab/promtail/promtail-config.yml` (psicopompo e kavure) e no
compose. **Sinal de que funcionou:** o log do promtail mostra
`msg="tail routine: started"` para vários arquivos.

> Adicionado também um **volume persistente de `positions`** (`/var/lib/promtail`).
> Sem ele, **todo recreate do container faz o promtail reler TODO o histórico** dos
> arquivos — um *replay* enorme, e o Loki rejeita entradas antigas com
> `400 entry too far behind`.

> ⚠️ O compose do promtail no psicopompo era **órfão** (o container existia sem arquivo
> no repositório, violando a regra `mnemocine/AGENTS.md` #3). Foi reconstruído.

## Ver também

- [`guides/docker-disk-cleanup.md`](docker-disk-cleanup.md) — limpeza de cache/imagens
- [`guides/docker-containerd-cleanup-kavure.md`](docker-containerd-cleanup-kavure.md)
- Runbook de Swarm/Tailscale (MTU, drift, bind mount) no repo do hub:
  `docs/swarm-tailscale-troubleshooting.md`

---
Última revisão: **2026-09-29**.
