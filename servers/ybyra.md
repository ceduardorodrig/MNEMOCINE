---
tags: [homelab, server, ybyra, docker, monitoring, tailscale]
---

# ybyra

**Papel:** Servidor cloud (Oracle Cloud) — Borda primária Sumaenima (proxy, tunnel, umami)
**Shell padrão:** bash (`/bin/bash`)
**Swarm role:** `primary` — nó worker do Docker Swarm (stack `sae-edge`)

> **Atualizado 28/08/2026:** `apt dist-upgrade` completo (41 pacotes, incl. Docker engine → 29.7.2) + reboot. Kernel **6.17.0-1016 → 6.17.0-1020-oracle**. Swarm services e borda primária OK pós-reboot.
>
> **🛡️ Bomba do `live-restore` desarmada preventivamente (02/10/2026):** o ybyra é o
> **3º nó do Swarm** e recebeu `"live-restore": true` no `daemon.json` em 29/09 —
> opção **incompatível com Swarm**, cujo erro só aparece no **próximo start** do daemon.
> **Nunca detonou** porque o host tinha uptime de 5 semanas. Correção: backup
> `/etc/docker/daemon.json.bak-20261002` → chave removida → `systemctl reload docker`
> (10 containers, **zero downtime**; o estado `LiveRestore=true` continua só na instância
> em execução e vale até o próximo restart). Sem isso, o **próximo reboot derrubaria a
> borda primária** (nginx, tunnel, umami) — e é exatamente esse tipo de falha que derrubou
> kavure (02/10) e psicopompo (30/09). Regra + runbook: [`AGENTS.md`](../AGENTS.md)
> §`live-restore` PROIBIDO em host Swarm · registro do incidente:
> [`guides/docker-registry.md`](../guides/docker-registry.md).

## Hardware

| Item | Especificação |
|---|---|
| **SO** | Ubuntu 24.04.4 LTS (KVM — QEMU Standard PC) |
| **Kernel** | 6.17.0-1020-oracle |
| **CPU** | AMD EPYC 7551 32-Core (2 vCPUs — 1 core/2 threads, Oracle free tier) |
| **RAM** | 954 MB |
| **Disco Sistema** | **50 GB** — Boot Volume (Oracle Block Storage) — `sda1` ext4 — recriado 08/10/2026 (era 150 GB) |
| **Swap** | 4 GB (4.095 MB) — recriado 08/10/2026 |
| **Tailscale IP** | 100.66.224.34 |
| **Tailscale DNS** | ybyra.chimaera-heptatonic.ts.net |
| **Rede** | Oracle internal network (`ens3`: 10.0.0.40/24) |

## Papéis

- Novo servidor cloud (Oracle free tier)
- Futuro host de Single Page Application (Docker)

## Tailscale Funnels

| URL | Destino | Status |
|---|---|---|
| `https://sumaenima.chimaera-heptatonic.ts.net` | `http://proxy:80` | Ativo — proxy para o nginx Swarm |

## Containers Docker — Utilitários (Standalone)

| Container | Imagem | Portas | Função |
|---|---|---|---|
| glances | nicolargo/glances:latest | `0.0.0.0:61208` | Monitoramento |
| autoheal | willfarrell/autoheal:latest | — | Auto-restart containers |
| watchtower | containrrr/watchtower:latest | — | Auto-update containers |

## Swarm Services (Gerenciados pelo Docker Swarm — **manager: kavure**)

| Service | Imagem | Portas | Função |
|---|---|---|---|
| proxy | nginx-sumaenima:latest | `0.0.0.0:80` | Proxy reverso (SPA, API, Umami) |
| tunnel | tailscale/tailscale:latest | — | Tailscale Funnel (sumaenima.chimaera-heptatonic.ts.net) |
| umami | sumaenima-umami:latest | 3000 | Analytics (acessível via nginx `/umami/`) |
| ~~datavis~~ | ~~datavis-server:latest~~ | ~~9091~~ | **removido de fato em 06/10/2026** — o serviço Swarm seguiu rodando (1/1 em ybyra) apesar de "removido 22/09"; legado sem consumidores, CVE-2025-67221 (orjson) já eliminado. Registro abaixo |

## Programas Nativos

| Programa | Função |
|---|---|
| tailscaled | Agente Tailscale |
| Docker Engine | Container runtime (v29.7.2) |
| nginx | Borda Primária (Roteamento de tráfego, virtual DNS, SPA Frontend) |

## Portas Importantes

| Porta | Serviço | Bind |
|---|---|---|
| 22 | SSH | Tailscale |
| 80 | Nginx (Borda Primária — SPA, API, Umami) | `0.0.0.0` |
| 61208 | Glances | `0.0.0.0` |

## Observações

- Servidor Oracle free tier (Junho 2026): 2 vCPUs, 1 GB RAM, 150 GB disco.
- Servidor **exclusivamente como borda primária** do Sumænimá Hub.
- Todo o tráfego público entra via Tailscale Funnel (`sumaenima.chimaera-heptatonic.ts.net` → proxy:80).
- Nginx roteia:
  - `/` → SPA (React + Vite)
  - `/api/` → FastAPI (steniobot-api no psicopompo, overlay network)
  - `/umami/` → Umami (no próprio ybyra, overlay network)
- ~~`/api/datavis/`~~ → removido 22/09/2026 (legado) — 404 agora, era 502
- **Não** roda filebrowser, syncthing nem outros utilitários — estes ficam no ybytu.
- Containers utilitários (glances, autoheal, watchtower) rodam standalone fora do Swarm.
- Nenhum serviço do Kuaray roda aqui — kuaray é o servidor multimídia separado.
- Ver `network/topology.md` para topologia de rede completa.
- **Fix NFS (10/09/2026):** Entries `hard` → `soft` no fstab (`configs-homelab`, `repos/git`). Backup: `/etc/fstab.bak.20260910`. Drop-in Docker: `/etc/systemd/system/docker.service.d/nfs-ordering.conf` (`After=remote-fs.target`, `TimeoutStopSec=30s`). Ver [`network/nfs.md`](../network/nfs.md).

## 06/10/2026 — Limpeza do serviço fantasma `datavis`

- **Achado:** o serviço Swarm `sae-edge_datavis` (`datavis-server:latest`) estava **`Running 4 days`** em ybyra — apesar de a doc registrar "removido 22/09/2026" e de a rota `/api/datavis/` já ter saído do nginx. Serviço órfão, sem consumidores.
- **Correção:** `docker service rm sae-edge_datavis` executado no manager (**kavure**). A stack `sae-edge` passou de 7 → **6 serviços**, batendo com a definição: `proxy`, `proxy-standby`, `tunnel`, `tunnel-standby`, `umami`, `umami-standby`.
- **Definição do stack:** bloco `datavis` removido das **duas** cópias de `edge.yml`:
  - canônica (repo git, usada pelo `scripts/deploy-swarm.sh`): `/mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/provisioning/stacks/edge.yml` (no psicopompo);
  - **duplicata solta no kavure**: `/srv/data/sumaenimahub/SUMAENIMA-HUB/stacks/edge.yml` (não é repositório git e estava com o bloco defasado — armadilha de ressurreição se alguém deployasse a partir dela). Backup: `edge.yml.bak-20261006`.
- **Pendência registrada:** existem **duas cópias** do projeto SUMAENIMA-HUB (repo no psicopompo + cópia solta no kavure). A fonte de verdade é o repositório; vale desativar/limpar a cópia do kavure para eliminar a divergência.
- **Divergências de doc corrigidas nesta passada:** manager do Swarm é o **kavure** (não o psicopompo); swap é de **12 GB** (não "nenhum").

## 07/10/2026 — Healthchecks

- Todos os containers **standalone** deste host receberam `healthcheck` (padrão: ver [`guides/docker-healthchecks.md`](../guides/docker-healthchecks.md)), habilitando o `autoheal`. Containers que eram `docker run` ganharam `compose.yml`.

## 08/10/2026 — Gestão via API (OCI CLI) + reboot pendente

- **Escopo novo:** a instância passou a ser **gerenciável por API, direto do terminal** (do
  psicopompo), via **OCI CLI** com API key RSA guardada no cofre sops — cobre inventário,
  boot/block volumes, rede, imagens e a **captura da ARM**. Guia:
  [`guides/oracle-oci-cli.md`](../guides/oracle-oci-cli.md).
- **CLI instalado no próprio ybyra** (`~/bin/oci`, 3.94.2), além do psicopompo — útil para o
  loop de captura da ARM rodar local (latência mínima à API da Oracle).
- **⚠️ Reboot pendente de kernel:** há kernel novo aguardando (`/var/run/reboot-required`).
  O ybyra é a **borda primária** (nginx + Tailscale Funnel) → o reboot exige **janela**;
  não executar sem combinar.

## 08/10/2026 — Backup restaurado (automount NFS morto → *stale file handle*)

- **Achado:** o `config-backup` deste host **falhava desde 27/09/2026** (`Result=exit-code`;
  ntfy "config-backup FALHOU (ybyra)"), com o espelho no NAS **congelado** naquela data.
- **Causa raiz:** a unit `srv-backup\x2dconfigs.automount` estava **`inactive (dead)` desde
  28/08**. O mount sobreviveu num estado obsoleto (opções antigas, `hard`) até o servidor NFS
  invalidar o *file handle* → `rsync: cannot stat destination ... Stale file handle (116)`.
- **Correção:** `umount -l` + `systemctl daemon-reload` + `systemctl restart` do `.automount`
  → o mount recriou com as opções do fstab (`soft,timeo=30,retrans=2`). **Backup OK** no run
  manual e `push ybyra ok` (etckeeper). Mesmo desvio corrigido no `/srv/backup-gitrepos`
  (estava `hard`) e no `gitrepos` do **ybytu**. Frota inteira: **0 mounts NFS `hard`**.
- **Lição:** `x-systemd.automount` pode ficar **dead** após reboot sem que o mount pareça
  quebrado (segue servindo de um estado velho) — a falha só aparece quando o handle expira.
  Ver [`backups/config-backup.md`](../backups/config-backup.md) → "Incidente 08/10/2026".

## 08/10/2026 — RECONSTRUÇÃO do host: 150 GB → 50 GB (destrava a ARM)

O boot volume era de **150 GB** e a cota *Always Free* (200 GB) estava cheia — sem espaço para a
VM ARM. Como a OCI **não encolhe** volume e a tenancy tem **`custom-image-count: 0`** (sem
imagem custom), a única saída foi **terminar e recriar** o host menor. Runbook:
[`guides/oci-shrink-boot-volume.md`](../guides/oci-shrink-boot-volume.md).

**Sequência executada:**
1. **Backup** do boot volume de 150 GB (`bootvolumebackup…`, rede de segurança) + staging do
   estado Tailscale (`/var/lib/tailscale` → mantido em `/mnt/BACKUP/ybyra-pre-rebuild/tailscale/`)
   e do SPA (`/var/www/sumaenima`, que **entrou no espelho** depois).
2. **Failover** da borda para o **kavure** (standbys do `sae-edge`) — borda no ar durante tudo.
3. **Terminar** o ybyra antigo → liberou 150 GB.
4. **Criar** o novo ybyra: Ubuntu 24.04, **50 GB**, IP privado fixo `10.0.0.40`, nome `ybyra`.
5. **Restaurar**: Tailscale (identidade `100.66.224.34`), Docker + reentrar no Swarm, `daemon.json`,
   fstab (NFS + swap), configs do espelho, SPA e o `.env` do cofre.
6. **Fail back** → borda de volta ao ybyra (URL canônico **200**).

**Novo instance OCID:** `ocid1.instance.oc1.sa-saopaulo-1.antxeljr7bfkjrycmelegdv3qris5li7qr67zdgh7gsvh2qdszmv32xuthla`
**Cota agora:** ybytu 50 + ybyra 50 = **100 GB** (100 livres → a ARM cabe).

**Achados desta operação:**
- ⚠️ **O estado do Tailscale do container `tunnel` mora no volume do ybyra** — ao recriar o host,
  ele se perde e o túnel **re-registra** com o `TS_AUTH_KEY`. Por isso a auth key **precisa** ser
  válida (a rotação de hoje foi o que salvou).
- ⚠️ **`sumaenima-umami:latest` (2.5 GB) não está no registry** — é imagem local do kavure/kuaray.
  No host novo ela **não existe** → o serviço `umami` fica `Rejected`. Corrigido copiando a
  imagem; **débito:** publicar a `sumaenima-umami` no registry (hoje só `nginx-sumaenima` e
  `sumaenima-server` estão lá).
- O `swarm join --token … 100.124.146.77:2377` e o rótulo `docker node update --label-add role=primary ybyra`
  restauraram a participação no Swarm.
- ⚠️ **`umami` travado pelo `autoheal`:** o `autoheal` deste host roda com
  `AUTOHEAL_CONTAINER_LABEL=all` e **reiniciava o `umami`** antes de ele subir (o healthcheck na
  `:3000` falha nos primeiros ~60 s de boot). Só estabilizou com o `autoheal` **pausado** durante o
  start. **Débito:** aumentar o `start_period` do healthcheck do `umami` no `edge.yml` (hoje 30 s).
- 🔧 **Tooling de operação reinstalado:** host novo não traz `/usr/local/bin` nem units. Instalados
  via `SUMAENIMA-HUB/provisioning/scripts/install-homelab-tools.sh --host ybyra config-backup etckeeper-push`
  + `/etc/config-backup.conf` + units `hl-config-backup.{service,timer}` e `hl-etckeeper-push.{service,timer}`
  (**com `RequiresMountsFor=/srv/backup-configs`** — os units do repo têm `/mnt/BACKUP`, que é do
  psicopompo) + `etckeeper init`. Backup validado à mão: **OK**.
- 🆕 **SPA entrou no backup:** `/var/www/sumaenima` adicionado ao `SRC_DIRS` (antes ficava **fora**
  do espelho — só existia no host). No espelho vira `ybyra/sumaenima/` (basename; não colide com o
  app, que é `ybyra/homelab/sumaenima/`).
