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

**Fix aplicado (psicopompo):** `live-restore: true` no `/etc/docker/daemon.json`,
aplicado com **`systemctl reload docker`** — a doc oficial é explícita:

> *"On Linux, you can avoid a restart (and avoid any downtime for your containers) by
> reloading the Docker daemon."*

```json
{ "live-restore": true, "...": "restante do daemon.json inalterado" }
```

- **Por que é seguro com o Swarm** — a doc: *"The live restore option only pertains to
  **standalone** containers, and not to Swarm services."* Serviços do Swarm
  continuam sob o manager.
- **Efeito:** containers standalone (registry, promtail, glances, steniorec…) agora
  **sobrevivem** a restart/upgrade do daemon.
- **Verificação:** `docker info --format '{{.LiveRestoreEnabled}}'` → `true`, e os
  containers seguiram **sem interrupção** (uptimes preservados após o reload).
- **Ressalvas da doc:** vale para upgrades de **patch** do Docker (não de major); se
  opções do daemon mudarem, o restore pode não reconectar (parar containers à mão);
  com o daemon fora por muito tempo, o buffer FIFO de log (64K) pode encher.
- **Reverter:** remover a chave e `systemctl reload docker`
  (backup: `/etc/docker/daemon.json.bak-liverestore-20260929`).
- **Aplicado nos 3 hosts em 29/09/2026** — psicopompo, **kavure** (37 containers, é o
  manager do Swarm) e **ybyra** (10 containers). Todos com `sysctl reload` e
  **zero interrupção**: kavure 37→37 e ybyra 10→10 containers vivos após o reload, e o
  Swarm seguiu `Ready/Active` com o kavure `Leader` e 10/10 serviços `1/1`.
  Validado com `dockerd --validate --config-file` **antes** de aplicar em cada host.
  > Nuance de host: **só o psicopompo** tinha o `DefaultTimeoutStopSec=10s` do CachyOS
  > (`/usr/lib/systemd/system.conf.d/00-timeout.conf`); kavure e ybyra têm **30 s** —
  > por isso o SIGKILL do incidente aconteceu só no psicopompo.

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
