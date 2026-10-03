---
tags: [homelab, tutorial, docker, registry, psicopompo, storage]
---

# Registry de Imagens Docker (Sumænimá)

Registry privado que é a **fonte única** das imagens do Swarm. Rodando no
**psicopompo** (build-node), acessível pela tailnet com **TLS + autenticação**.

## Por que existe

A documentação oficial é direta ([Deploy a stack to a swarm](https://docs.docker.com/engine/swarm/stack-deploy/)):

> *"Because a swarm consists of multiple Docker Engines, **a registry is required**
> to distribute images to all of them."*

E o sintoma de **não** tê-lo aparecia em **todo** deploy, como aviso da própria CLI:

> `image X could not be accessed on a registry to record its digest. Each node will
> access X independently, possibly leading to **different nodes running different
> versions** of the image.`

**O que isso custou (29/09/2026):** o `deploy-swarm.sh` **não atualizou a API** —
a imagem `:cpu` mudou de conteúdo mas manteve a tag, e sem registry o Docker não
tem como perceber. Foi preciso `docker save | ssh | docker load` + `--force` manual.

## Topologia

| Item | Valor |
|---|---|
| Host | **psicopompo** (`100.82.51.112`) |
| Imagem | `registry:3` |
| Porta | `5000/tcp` — **apenas** loopback + tailnet (nunca `0.0.0.0`) |
| Storage | `/mnt/NVME_PCI/registry` (bind mount — exige réplica única) |
| Config | `~/homelab/registry/compose.yml` |
| URL | `https://psicopompo.chimaera-heptatonic.ts.net:5000` |

## Segurança (requisitos da doc do Distribution)

| Requisito | Como está |
|---|---|
| **TLS obrigatório** | *"A production-ready registry **must** be protected by TLS"* — certificado via **`tailscale cert`** (Let's Encrypt, já confiável pelos nós) |
| **Auth exige TLS** | *"You cannot use authentication with schemes that send credentials in clear text"* — por isso TLS **antes** do htpasswd |
| **htpasswd em bcrypt** | Hash `$2y$` derivado do cofre sops — o registry **só** aceita bcrypt |
| **Rede local/privada** | Bind **só** na tailnet + loopback (regra [`network/ports.md`](../network/ports.md)) |

### Credenciais — agora no cofre sops (29/09/2026)

| Item | Onde vive |
|---|---|
| Usuário | `REGISTRY_USER` (`sae`) no store sops |
| Senha | `REGISTRY_PASSWORD` no store sops |
| Hash bcrypt | `auth/htpasswd` (modo `600`) — **artefato derivado**, não é fonte da verdade |
| Nós autenticados | `~/.docker/config.json` em psicopompo/kavure/ybyra ✅ |

O arquivo `auth/registry-password.txt` (senha em claro, `600`) **foi removido em
29/09/2026** — a senha agora vive apenas no cofre cifrado
([`guides/secrets-centralizados.md`](secrets-centralizados.md)). O
`deploy-swarm.sh` **não** lê a senha: usa `--with-registry-auth` com os nós já
autenticados.

```console
# ler a senha do cofre
$ /mnt/NVME_PCI/secrets/sops-decrypt.sh REGISTRY_PASSWORD

# regenerar o htpasswd num host novo (o registry só aceita bcrypt)
$ docker run --rm httpd:2-alpine htpasswd -Bbn "$REGISTRY_USER" "$REGISTRY_PASSWORD" \
    > ~/homelab/registry/auth/htpasswd && chmod 600 ~/homelab/registry/auth/htpasswd
```

> **Nota:** `htpasswd` **não** está instalado no psicopompo (pacote `apache-tools`);
> por isso a regeneração usa o container oficial `httpd`.

## Operação

```console
# status
$ docker compose -f ~/homelab/registry/compose.yml ps

# saúde (a doc: um registry protegido responde 401 sem credencial)
$ curl -s -o /dev/null -w '%{http_code}\n' https://psicopompo.chimaera-heptatonic.ts.net:5000/v2/     # 401
$ curl -s -u "sae:$(/mnt/NVME_PCI/secrets/sops-decrypt.sh REGISTRY_PASSWORD)" \
       https://psicopompo.chimaera-heptatonic.ts.net:5000/v2/_catalog                                  # lista

# publicar uma imagem
$ docker tag minha-imagem:tag psicopompo.chimaera-heptatonic.ts.net:5000/minha-imagem:tag
$ docker push psicopompo.chimaera-heptatonic.ts.net:5000/minha-imagem:tag

# login em um nó novo (senha vinda do cofre, nunca digitada em claro)
$ /mnt/NVME_PCI/secrets/sops-decrypt.sh REGISTRY_PASSWORD \
    | docker login psicopompo.chimaera-heptatonic.ts.net:5000 -u sae --password-stdin
```

## Como o deploy usa

O `scripts/deploy-swarm.sh` (no repo do hub):

1. Builda com a **tag qualificada pelo registry** (`$REG/sumaenima-server:cpu`);
2. **`docker push`** (substituiu o `docker save | ssh | docker load`);
3. `docker stack deploy **--with-registry-auth**` — as credenciais vão aos agentes
   e cada nó **puxa** a imagem sozinho.

**Ganhos:** o serviço passa a referenciar a imagem **por digest** (fim do risco de
versões diferentes entre nós), e um reagendamento em outro nó funciona (o nó puxa
em vez de depender de a imagem já estar lá).

### O que **não** passa pelo registry

- **`sumaenima-server:cuda`** (4,3 GB): é construída **e** consumida só no
  psicopompo — não faz sentido trafegar.
- Imagens de terceiros (`pgvector`, `valkey`, `tailscale`, …): vêm do Docker Hub.

## Resiliência a restart do daemon (29/09/2026)

**Incidente:** durante um `pacman -Syu`, o hook do sistema disparou
`systemctl restart docker.service` **duas vezes em 4 minutos**. O `dockerd` estourou
o **timeout de parada** e levou `SIGKILL` — e o **registry não voltou** (ficou
`Exited (2)`), apesar do `restart: unless-stopped`. Todos os outros containers do host
subiram; só o registry ficou caído, e o `deploy-swarm.sh` falharia ao empurrar imagens
para ele (padrão do Docker: um container que morre **junto** com o daemon não é
necessariamente religado pelo restart-manager).

**Causa raiz do SIGKILL:** o CachyOS define **`DefaultTimeoutStopSec=10s`** em
`/usr/lib/systemd/system.conf.d/00-timeout.conf` — é **global** (vale para `docker`,
`containerd`, `tailscaled`, `NetworkManager`…). Um `dockerd` com Swarm leva mais que
10 s para encerrar → o systemd mata com SIGKILL.

**Fix aplicado em 29/09/2026 — ✗ ERRADO · REVERTIDO EM 02/10/2026:** a escolha foi
habilitar `live-restore`, o que resolveu o sintoma imediato mas era **incompatível com o
Swarm** dos 3 hosts:

```json
{ "live-restore": true, "...": "restante do daemon.json inalterado" }
```

> ⚠️ **O que a doc oficial realmente diz:** *"The live restore option only pertains to
> **standalone** containers, and not to Swarm services"* — é uma **limitação**, não um
> aval de compatibilidade. Com Swarm ativo o `dockerd` **se recusa a subir**:
> `failed to start cluster component: --live-restore daemon configuration is incompatible
> with swarm mode`
> ([moby/swarmkit#2381](https://github.com/moby/swarmkit/issues/2381) ·
> [docker/docs#16059](https://github.com/docker/docs/issues/16059) ·
> [live-restore](https://docs.docker.com/engine/daemon/live-restore/)).

**Por que ficou latente:** o daemon só lê o `daemon.json` no **start**. A chave entrou
via `systemctl reload` nos 3 hosts com o daemon já rodando — e detonou no **próximo
reboot** de cada um:

| Host | Detonou em | Consequência |
|---|---|---|
| psicopompo (worker) | reboot **30/09 00:58** | **2 dias sem daemon** · Swarm sem worker |
| kavure (manager) | reboot **02/10 13:08** | sae-core inteiro fora · `docker ps` inoperante |
| ybyra (borda primária) | **não detonou** — config limpa preventivamente em 02/10 | desarmada |

**Efeito colateral que mascara o sintoma:** o `live-restore` mantém **vivos** os
containers que o daemon já tinha subido antes de abortar → no kavure, **33 containers
rodavam como órfãos** enquanto `docker ps` respondia `Cannot connect to the Docker
daemon`. Parecia "alguns serviços no ar", mas não havia gerência alguma.

**Correção (02/10/2026, nos 3 hosts):** remover a chave (backup
`daemon.json.bak-20261002`) → `systemctl reset-failed docker && systemctl start docker`
→ religar os `unless-stopped` que o daemon parou no takeover → validar `docker node ls`
(3/3 `Ready`). Runbook completo: [`AGENTS.md`](../AGENTS.md)
§`live-restore` PROIBIDO em host Swarm.

**Fix correto para o problema original (SIGKILL durante upgrade):** aumentar o timeout de
parada do daemon — **não** habilitar `live-restore`:

```ini
# /etc/systemd/system/docker.service.d/timeout.conf
[Service]
TimeoutStopSec=60s
```

aplicado com `sudo systemctl daemon-reload`. É o mesmo padrão que o kavure já usa no
drop-in `nfs-ordering.conf` (`TimeoutStopSec=30s`).

> Nuance de host (mantida): **só o psicopompo** tem o `DefaultTimeoutStopSec=10s` do
> CachyOS (`/usr/lib/systemd/system.conf.d/00-timeout.conf`); kavure e ybyra têm **30 s**
> — por isso o SIGKILL do incidente original aconteceu só no psicopompo.
>
> 🔖 **Pendência:** aplicar o drop-in `TimeoutStopSec=60s` no psicopompo para fechar a
> falha original (registry não religado após SIGKILL).

**Recuperação manual (se algum container não voltar):**

```console
$ cd ~/homelab/registry && docker compose up -d
$ docker ps --filter name=registry --format '{{.Names}} | {{.Status}}'
$ curl -s -o /dev/null -w '%{http_code}\n' https://psicopompo.chimaera-heptatonic.ts.net:5000/v2/   # 401
```

## Ver também

- [`guides/docker-log-rotation.md`](docker-log-rotation.md) — rotação de log
- [`network/ports.md`](../network/ports.md) — catálogo de portas
- Runbook de Swarm/Tailscale no hub: `docs/swarm-tailscale-troubleshooting.md`

---
Última revisão: **2026-09-29**.
