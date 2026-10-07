---
tags: [homelab, docker, monitoring, tutorial]
---

# Healthchecks dos containers (padrão do homelab)

**Regra:** todo serviço Docker deve ter **healthcheck** — é o que permite o `autoheal`
reiniciar um container doente. Exceção única e documentada: imagens **distroless** (sem
shell), cobertas por **watchdog externo**.

## Padrão

```yaml
healthcheck:
  test:
    - CMD-SHELL
    - <comando>
  interval: 60s
  timeout: 10s
  retries: 3
  start_period: 30s   # 40s em apps lentos
```

Regras de aplicação:

- **Testar o comando DENTRO do container antes de aplicar** — porta, bind e ferramentas variam
  por imagem (ex.: `glances`/`node-exporter` escutam no IP da tailnet, não no loopback;
  `wordpress`/`flaresolverr`/`npm` só têm `curl`; `crafty` só tem `bash`).
- Preferir `wget -q -O /dev/null <url>`; `curl -fsS -o /dev/null <url>` quando não houver wget;
  `nc -z 127.0.0.1 <porta>` para TCP sem HTTP; `bash -c 'exec 3<>/dev/tcp/127.0.0.1/<porta>'`
  como último recurso; `valkey-cli ping` / `redis-cli ping` para caches.
- Inserir o bloco **logo após a linha `image:`** do serviço (método seguro, evita quebrar
  blocos multi-linha) e **validar o YAML** (`docker compose config -q`) antes de recriar.
- Backup do compose antes de editar (`*.bak-YYYYMMDD-healthcheck`).

## Exceção: distroless → watchdog externo

`dnscrypt-proxy` (kavure) usa imagem **sem shell** → não aceita healthcheck interno. Coberto
por [`scripts/dns-watchdog`](../../scripts/dns-watchdog/) (Rust) + `hl-dns-watchdog.timer`
(2 min) no kavure — cobre até o caso "processo travado".

## Cobertura (07/10/2026)

| Host | Com healthcheck | Pendente |
|---|---|---|
| **kavure** | 14 (monitoring, searxng, HA, navidrome, node-exporter, glances, dockerproxy, crafty, pihole…) + `dnscrypt-proxy` via watchdog + `sae-core_backup` (Swarm) | — (ver órfão abaixo) |
| **kuaray** | 16 (miracena-*, *arr, transmission, syncthing, glances, promtail, node-exporter, dockerproxy) | — |
| **ybytu** | 8 (adguardhome, changedetection, glances, promtail, node-exporter, ntfy, dockerproxy, homepage, uptime-kuma) | — |
| **ybyra** | 6 (glances, promtail, node-exporter, dockerproxy, edge proxy/tunnel, **umami** via Swarm) | — |
| **psicopompo** | 5 (registry, glances, promtail, node-exporter, dockerproxy) | — |

> **Serviços Swarm:** `sae-core_backup` e `sae-edge_umami` receberam healthcheck **no stack file**
> (`provisioning/stacks/{core,edge}.yml`) **e** via `docker service update` (cirúrgico).

> **`autoheal` padronizado (07/10/2026):** o ybyra usava `AUTOHEAL_CONTAINER_LABEL=autoheal`
> (só containers com esse label) — os healthchecks novos **não** disparariam restart. Agora usa
> `all`, como os outros 4 hosts, e ganhou `compose.yml` (`/home/ubuntu/homelab/autoheal/`).

### ⚠️ Órfão encontrado: `sae-core_asciline`

O serviço Swarm `sae-core_asciline` (imagem `sumaenima-asciline-launch:latest`, porta 8766,
criado **29/09**) **não existe no `core.yml` atual** — é resquício de uma versão anterior do
stack (a doc o chama de `n`/`sae-core_n`). Fica **sem healthcheck** até se decidir o destino
(remover, como foi feito com o `datavis`). Não foi tocado nesta passada.

> **Composes criados nesta passada** (containers que eram `docker run`): `dockerproxy` (ybytu,
> ybyra, psicopompo), `glances` (ybyra, psicopompo), `node-exporter` (psicopompo),
> `adguardhome` (ybytu). Todos agora seguem o padrão config-as-code.

## Enforcement no Stênio (regra `INFRA-COMPOSE-HEALTHCHECK` — 07/10/2026)

O motor ganhou uma regra nativa **irmã** da `INFRA-COMPOSE-RESTART` (em `infra.rs`, via
`serde_yaml`): percorre `services:` e exige, **por serviço**, `healthcheck` **ou** a exceção
explícita para imagens *distroless*:

```yaml
    labels:
      homelab.healthcheck: watchdog
```

**Cobertura:** o escopo `homelab` audita a árvore do vault **e** o **espelho do NAS**
(`/mnt/BACKUP/configs-homelab`, mantido pelo `config-backup`) — sem isso a regra não veria
nenhum compose real (o vault tem 0). Só as checagens **estruturais de compose** rodam no
espelho (as regras `SEC-*` não se aplicam a conteúdo capturado), e `golden/` é ignorado para
não duplicar achados. A varredura do espelho só ocorre quando o alvo é o vault real (um
`--path` externo não arrasta o NAS).

- **Severidade:** `Warning` — não bloqueia o gate. Pode ser promovida a `Error` quando o
  espelho estiver atualizado e o número de avisos for zero.
- **Estado (07/10):** ~60 avisos, **todos do espelho desatualizado** (captura de 05:00, antes
  do rollout) — devem cair após a sincronização da madrugada. Exceções legítimas que podem
  restar: composes cujo **próprio image** já traz `HEALTHCHECK` (ex.: `valheim`).
- **Validação:** teste sintético (`--path` externo) confirma que a regra acusa **só** o serviço
  sem `healthcheck`/label. `cargo test` 20/20, `--self-test` 60/60, `--guardian` zero adulteração.

## Comandos úteis

```bash
# quem está sem healthcheck
for c in $(docker ps --format '{{.Names}}'); do
  docker inspect --format '{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}SEM{{end}}' "$c"
done

# ferramentas disponíveis na imagem (para escolher o check)
docker exec <c> sh -c 'for b in wget curl nc bash; do command -v $b; done'
```
