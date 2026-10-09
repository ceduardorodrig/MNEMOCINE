---
tags: [homelab, service, docker, compose, tailscale, ybyra]
---

# Sumænimá Hub — Edge (stack `sae-edge`)

> Documento do **lado homelab** do edge do Sumænimá Hub: como o tráfego público entra, como o
> stack é composto, o **failover** para o kavure e o que aprendemos na **reconstrução do ybyra**
> (08/10/2026). O lado de aplicação vive no repo `SUMAENIMA-HUB` (`docs/deployment.md`).

## Visão geral

O Sumænimá Hub é servido publicamente por **`https://sumaenima.chimaera-heptatonic.ts.net`**
(Tailscale Funnel). Dois stacks Swarm compõem o serviço:

| Stack | Host | Serviços | Papel |
|---|---|---|---|
| **`sae-core`** | kavure | api, db (Postgres), valkey, backup, **umami-db** | aplicação/estado |
| **`sae-edge`** | **ybyra** (primário) | `proxy` (nginx), `tunnel` (Funnel), `umami` | borda pública |

```
Internet ──► Tailscale Funnel (nó "sumaenima") ──► container tunnel ──► proxy:80 (nginx)
                                                                        ├── /          → SPA (/var/www/sumaenima)
                                                                        ├── /api/      → sae-core_api (overlay)
                                                                        └── /umami/    → umami (edge)
```

## O stack `sae-edge`

- **`proxy`** — nginx (`nginx-sumaenima`). Publica a porta **80** em `mode: host`. Roteia SPA,
  `/api/` e `/umami/`. Config por bind mount: `/home/ubuntu/homelab/sumaenima/nginx.conf`.
- **`tunnel`** — `tailscale/tailscale`. Registra o nó **`sumaenima`** e habilita o **Funnel**.
  O estado do Tailscale **mora no volume `tailscale-state`** (⚠️ ver lições).
- **`umami`** — analytics (`sumaenima-umami:latest`).
- **`*-standby`** — as mesmas peças **no kavure** (`node.labels.edge_backup == true`),
  `replicas: 0` — usadas só no **failover**.

> Firmware das réplicas: `proxy`/`tunnel`/`umami` exigem `node.labels.role == primary`
> (hoje = **ybyra**); os `-standby` exigem `edge_backup == true` (hoje = **kavure**).

## Failover (kavure assume a borda)

Testado em **08/10/2026** (funciona). No **manager (kavure)**:

```bash
# 1) sobe o standby PRIMEIRO, valida
docker service scale sae-edge_proxy-standby=1 sae-edge_tunnel-standby=1 sae-edge_umami-standby=1
curl -sI https://sumaenima-1.chimaera-heptatonic.ts.net    # ~200
# 2) baixa o primário (ybyra)
docker service scale sae-edge_proxy=0 sae-edge_tunnel=0 sae-edge_umami=0
```

**Nuances aprendidas:**
- O standby registra o nó **`sumaenima-1`** (o nome canônico `sumaenima` é do primário) → o
  **URL muda** durante o failover. Para o primário reassumir o nome canônico, é preciso
  **remover os nós `sumaenima*`** no console do Tailscale antes de subir o túnel.
- O standby precisa de **auth key válida** (ver [`network/tailscale.md`](../network/tailscale.md)).
- Os nós criados **não são efêmeros** → depois do teste, **deletar no console** (ou usar uma
  auth key **efêmera**, que some sozinha).

## Deploy

`scripts/deploy-swarm.sh` (repo `SUMAENIMA-HUB`, no psicopompo) faz `set -a; source .env` e
`docker stack deploy` remoto no kavure. Ele **constrói** `nginx-sumaenima` e `sumaenima-server`
e publica no **registry** (`psicopompo…:5000`). O `edge.yml` referencia
`psicopompo…:5000/nginx-sumaenima:latest`.

> ✅ **Resolvido (08/10/2026):** a `sumaenima-umami` foi **publicada no registry**
> (`sha256:1c05593d…`) e o `edge.yml` passou a referenciar
> `psicopompo…:5000/sumaenima-umami:latest`; o spec do serviço foi atualizado por
> `docker service update --image …`. O `Dockerfile.umami` usa o **upstream do Umami** como
> contexto (clone da fonte) — por isso **não** é buildado pelo `deploy-swarm.sh`; é tratada
> como imagem externa no registry (puxada pelos nós via `--with-registry-auth`).
>
> ✅ **Resolvido (08/10/2026) — pelos specs.** Docker e o Sumænimá concordam: configs de Swarm
> são **imutáveis** e o certo é **versionar o nome** (Docker: *"consider adding a version number or
> date to the config name"*; `swarm-tailscale-troubleshooting.md` §253: *"trocar = novo config +
> `--config-rm/--config-add`"*). O `nginx-conf-standby` virou **`nginx-conf-standby-20261008`** →
> o `docker stack deploy` **passou** (criou a config nova) e a config implantada agora **bate com
> o arquivo** (`sha256 862b195a…`). **Convenção:** ao mudar o arquivo de um `configs:`, **bump o
> nome** (data/versão). A config antiga fica até um `stack rm` (comportamento do Docker).

## Lições da reconstrução do ybyra (08/10/2026)

Detalhes do procedimento: [`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md).
O que o Sumænimá ensinou:

| Lição | Detalhe |
|---|---|
| **Estado do Tailscale no volume** | O nó `sumaenima` era do **container**, não do host: o estado morava em `tailscale-state` (volume do ybyra). Ao recriar o host, ele **se perde** e o túnel **re-registra** — exige **auth key válida**. |
| **A `TS_AUTH_KEY` precisa estar viva** | O primário só voltou a subir o Funnel depois de a chave ser atualizada no **spec do serviço** (`docker service update --env-rm/--env-add`), porque o spec implantado guardava a chave **velha**. |
| **`autoheal` × healthcheck lento** | O `autoheal` do ybyra roda com `AUTOHEAL_CONTAINER_LABEL=all` e **reiniciava o `umami`** antes ele subir (o check na 3000 falhava nos primeiros ~60 s). **Corrigido:** `start_period` do `umami` **30s → 120s** no `edge.yml` (aplicado por `docker service update --health-start-period 2m`). |
| **Imagem fora do registry** | **Corrigido:** `sumaenima-umami` publicada no registry e referenciada por lá — uma reconstrução de host não a perde mais. |
| **Configs do Swarm imutáveis** | ✅ **Corrigido:** versionamos o nome (`nginx-conf-standby-20261008`) conforme o spec — o deploy passou e a config bate com o arquivo. Ao mudar o arquivo, **bump o nome**. |
| **Foi fácil** | Terminar + recriar + restaurar o host levou ~1 h, **com a borda no ar** (failover no kavure). O que tornou fácil: **configs no espelho**, **segredos no cofre**, **Tailscale restaurável** e **Swarm** (reentrar com um token). |

## Arquivos-chave

| O quê | Onde |
|---|---|
| Stack edge (fonte) | `SUMAENIMA-HUB/provisioning/stacks/edge.yml` |
| Stack core (fonte) | `SUMAENIMA-HUB/provisioning/stacks/core.yml` |
| nginx (primário) | `ybyra:/home/ubuntu/homelab/sumaenima/nginx.conf` |
| SPA | `ybyra:/var/www/sumaenima` (**fora do espelho** — feito backup manual) |
| `.env` | cofre sops (`sops-decrypt.sh` → `sumaenima.env`) |
| Deploy | `SUMAENIMA-HUB/scripts/deploy-swarm.sh` |

## Referências

- [`servers/ybyra.md`](../servers/ybyra.md) · [`servers/kavure.md`](../servers/kavure.md)
- [`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md) — reconstrução do host
- [`network/tailscale.md`](../network/tailscale.md) — auth key e Funnel
- [`guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) — cofre sops
