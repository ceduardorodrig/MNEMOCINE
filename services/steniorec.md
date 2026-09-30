---
tags: [homelab, service, gpu, psicopompo]
---

# StênioREC (Whisper Daemon em Rust)

Serviço unificado de transcrição de áudio e streaming STT com aceleração de GPU (CUDA 13) no host **Psicopompo**, desenvolvido 100% em Rust (Axum 0.8 + `whisper-rs`).

Substitui os antigos workers fragmentados em Python (`steniobot-audio`, `steniobot-vision`, `transcribe_server.py`) por um daemon único de alta performance.

---

## 1. Topologia & Hardware

- **Host físico:** Psicopompo (Xeon E-2246G + RTX 5050 8GB Blackwell)
- **Porta:** `9090/tcp` (vinculada a `0.0.0.0:9090` no host)
- **Acesso Tailnet:** `http://100.82.51.112:9090` (ou `http://psicopompo:9090`)
- **Container:** `steniorec` (imagem `sumaenima-server:latest`)
- **Compose:** `/mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/provisioning/stacks/gpu.yml`
- **Modelo:** Whisper `Large-v3-Turbo Q8_0` GGML (`/mnt/NVME_PCI/homelab/sumaenimahub/llm_model_cache/whisper-ggml/ggml-large-v3-turbo-q8_0.bin`, 874 MB)
- **Consumo de VRAM:** ~1.6 GB na RTX 5050

---

## 2. Ciclo de Vida do Serviço

O serviço é standalone e controlado via `sumaenima-ctl`:

| Comando | Ação |
|---|---|
| `sumaenima-ctl gpu up` | Sobe o container `steniorec` na porta 9090 |
| `sumaenima-ctl gpu status` | Checa se o container está rodando, o status da VRAM e se o binário é CUDA |
| `sumaenima-ctl gpu down` | Para o container e libera a VRAM da GPU |

### Subida automática no boot (fix 29/09/2026 — supervisor em Rust)

Uma **única** unit de sistema, rodando o supervisor nativo:

| Unidade / binário | Caminho | Função |
|---|---|---|
| `sumaenima-gpu.service` | `/etc/systemd/system/` | `Type=simple` + `Restart=always` → o systemd ressuscita o supervisor |
| `gpu-supervisor` (Rust) | `/usr/local/bin/` | Supervisor event-driven (fonte: `app/gpu-supervisor/` no hub) |

**Ordem de boot garantida:** `tailscaled-wait.service` → `docker.service` → `sumaenima-gpu.service`.

O supervisor:
1. Espera `tailscale status → BackendState=Running` (o IP é atribuído **depois** do
   serviço reportar *ready* — [tailscale#11504](https://github.com/tailscale/tailscale/issues/11504)).
2. Espera a **sessão do Swarm** (`LocalNodeState=active` + manager:2377 alcançável +
   rede `ingress` presente). Em worker NÃO existe `docker node inspect self`.
3. Sobe o worker via `docker compose up -d` **com retentativas** — o attach é a
   operação que materializa a overlay (ver §5).
4. Confirma `healthy` e valida o **contrato de imagem** (`:cuda`).
5. Entra em supervisão **event-driven**: assina `/events` do Docker e reage a
   `die`/`kill`/`stop`/`oom` em **milissegundos** (um tick de 30 s fica só como
   rede de segurança, porque streams de evento podem cair).

`gpu-supervisor --check` roda os 5 gates uma vez e reporta (útil para diagnóstico).

> ⚠️ A primeira implementação (29/09, manhã) foi em **bash** + `Type=oneshot` + timer
> de 5 min. Foi substituída porque `Type=oneshot` **não aceita `Restart=`** no systemd
> (a resiliência dependia de polling, com janela de até 5 minutos). Medido depois da
> troca: recuperação de um `docker kill` caiu para **~10 s**.
> A unit antiga de **usuário** (`~/.config/systemd/user/sumaenima-gpu.service`) foi
> removida — units de usuário não conseguem ordenar contra units de sistema.

---

## 2b. Contrato de Imagem (nunca `:latest`)

| Nó | Papel | Dockerfile | Tag |
|---|---|---|---|
| **psicopompo** | GPU (Whisper/CUDA) | `app/server/Dockerfile` | `sumaenima-server:cuda` |
| **kavure** | core/API (sem GPU) | `app/server/Dockerfile.cpu` | `sumaenima-server:cpu` |

A tag `sumaenima-server:latest` **não deve ser usada**. Ver §6 para o incidente
de 28/09 em que a colisão de tag fez o worker de GPU rodar binário CPU.

---

## 3. Endpoints

| Método | Endpoint | Função |
|---|---|---|
| `GET` | `/v1/health` | Estado do processo + `device` (`cuda`/`cpu`) e `device_count` |
| `GET` | `/v1/ready` | **Readiness semântica**: `503` se este build exige GPU e não está em CUDA |
| `POST` | `/v1/transcribe` | Transcrição batch de áudio (JSON PCM 16kHz s16le Base64) |
| `WS` | `/ws/transcribe` | Streaming bidirecional em tempo real (AudioWorklet) |

### Rota da página web (corrigida 29/09/2026)

A barra de gravação do site fala `wss://<host>/api/ws/transcribe`. Esse caminho é
roteado pelo **nginx da borda DIRETO para este worker** (`100.82.51.112:9090`), e
**não** para a API do kavure:

| | |
|---|---|
| **Por quê** | A API roda no kavure com a imagem `:cpu` e **sem o modelo montado** (`MODEL_PATH` apontava para um caminho inexistente) — ela respondia `Failed to auto-load model`. |
| **Segurança do desenho** | É o **mesmo binário e o mesmo handler WS** (`app/server/src/ws.rs`) que o frontend já falava — só rodando onde o modelo está. **Zero mudança de protocolo.** |
| **Validado** | Teste real com fala (`Front_Center.wav`) pela URL pública: `TRANSCRIPT (final=True): 'Front Center'` + `DRAIN_COMPLETE`. |

> Alternativa arquitetural (delegação via Valkey, conforme `docs/architecture.md`) está
> descrita mas **não implementada** no lado da API — exigiria reescrever o protocolo do
> WebSocket. Registrada como evolução futura.


> **Por que `/v1/ready` existe:** o `/v1/health` só diz "o processo está vivo" — um
> binário CPU-only responde `200` nele. O `/v1/ready` é o que distingue
> "funcionando" de "funcionando no dispositivo certo", e é ele que o healthcheck
> do `gpu.yml` consome. Ver §8.

---

## 4. Documentação de Integração

Para guias de como agentes e clientes remotos da Tailnet devem consumir a API, consulte:
- [`docs/transcricao-remota-steniorec.md`](../../docs/transcricao-remota-steniorec.md) — Manual de integração e script cliente Python.
- Repositório Sumænimá Hub: `scripts/st-transcribe/` (CLI oficial em Rust).

---

## 5. Incidente — corrida de boot (27/09/2026, corrigido em 29/09)

**Sintoma:** o StênioREC ficou **fora do ar por ~26h**. Clientes da Tailnet recebiam
conexão recusada na `:9090`.

**Causa-raiz:** três defeitos que se somaram.

1. `sumaenima-gpu.service` era unit de **usuário** com apenas `After=network.target`
   → disparava ~40s antes da tailnet estar utilizável.
2. `sumaenima-ctl` **engolia o erro**: um `docker compose up` que falhasse tinha o
   stdout seguido de um `echo` de sucesso, e a função retornava 0 → o systemd
   reportava `status=0/SUCCESS` com o container morto.
3. `gpu.yml` tinha `restart: "no"` → o Docker nunca re-tentava.

**Evidência (journal do dockerd):**
```
22:38:05  Starting Sumaenima GPU workers
22:38:05  ⚠️ Não foi possível conectar ao Kavure via SSH (verifique Tailscale)
22:38:32  Container steniorec Starting
22:38:53  ✗ failed to set up container networking:
          Could not attach to network vr7y0e13...: context deadline exceeded
22:39~    agent: session failed — dial tcp 100.124.146.77:2377: network is unreachable
22:40:24  swarm agent finalmente conecta  ← tarde demais
```

**Correção (2 iterações):**
1. *Primeira* — unit de sistema + `sumaenima-boot.sh` + `set -euo pipefail` no
   `sumaenima-ctl` + `restart: unless-stopped` + watchdog de 5 min.
2. *Definitiva* — **supervisor em Rust** (`app/gpu-supervisor/`), `Type=simple` +
   `Restart=always`, event-driven. Ver §2 para a descrição e o motivo da troca.

> ⚠️ **Premissa corrigida no caminho:** a primeira versão do `sumaenima-boot.sh`
> exigia que a overlay `sumaenima_sumaenima-net` já existisse localmente antes de
> subir o container. **Isso está errado.** Redes overlay *attachable* são criadas
> **preguiçosamente no worker, no momento do attach** (commit oficial
> [moby/moby c379d26](https://github.com/moby/moby/commit/c379d2681ffe8495a888fb1d0f14973fbdbdc969)):
> o worker pede o attach ao manager, que agenda uma task; o worker espera essa task
> para receber a configuração da rede. Logo, `network not found` **antes** do attach
> é o estado NORMAL, e o erro `context deadline exceeded` significa que o manager
> não agendou a task a tempo (nó não estava prontamente `Ready`).
> O gate correto é a **prontidão da sessão do Swarm** + **retentativa do
> `docker compose up`** — que é a operação que materializa a rede.

Mesmo padrão canônico de espera de tailnet já usado em `network/nfs.md` e
`services/wol-relay.md`.


---

## 6. Incidente — colisão de tag (`:cpu` vazou para o papel GPU) — 28/09/2026

**Sintoma:** o StênioREC subiu, respondia `/v1/health` 200, mas transcrevia **na CPU**
(~20s por bloco, 400% de CPU, GPU ociosa). **Violação do [ADR-020 (GPU-Only)](../../../../homelab/sumaenimahub/sumaenima-hub/docs/adr/020-gpu-only.md)**.

**Evidência:** `whisper_init_with_params_no_state: use gpu = 0` +
`whisper_backend_init_gpu: no GPU found` + `CPU total size = 873.55 MB`.
A GPU estava disponível dentro do container (`nvidia-smi` funcionava) — o problema
era o **binário**, construído sem `--features cuda`.

**Causa-raiz:** a tag `sumaenima-server:latest` era **compartilhada** pelos dois papéis.

| Alvo | Dockerfile | Tag antiga | Tag nova |
|---|---|---|---|
| kavure (i3, sem GPU) | `Dockerfile.cpu` | `:latest` | `:cpu` |
| psicopompo (RTX 5050) | `Dockerfile` (CUDA) | `:latest` | `:cuda` |

Como o `scripts/deploy-swarm.sh` executa `docker build` **localmente no psicopompo**
(só o `docker stack deploy` é remoto), construir a imagem do kavure **sobrescrevia a
tag**, deixava a imagem CUDA *dangling* e o `docker image prune -f` do fim do script
a **apagava**. A imagem CUDA original não existia em nenhum nó.

**Correção:** tags explícitas por papel (`:cuda` / `:cpu`), `prune` escopado
(`until=168h`), comentários de contrato nos dois Dockerfiles e no `deploy-swarm.sh`.
Stack `sae-core` do kavure redeployada com `:cpu` (4 usuários intactos).

**Lição:** ao distribuir artefatos entre nós com papéis heterogêneos (com/sem GPU),
a **tag é parte do contrato** — `:latest` compartilhado esconde divergência de alvo.

---

## 7. Auditoria de boot-race nos 6 nós (29/09/2026)

| Nó | `tailscaled-wait` | Docker espera TS | Swarm | Falhas de sessão desde boot |
|---|---|---|---|---|
| psicopompo | ✅ (nfs-server, wol-relay, sumaenima-gpu) | ❌ | worker | 24 (corrigido) |
| kavure | ❌ | ✅ (`nfs-ordering.conf`) | manager | 4 |
| ybyra | ❌ | ✅ | worker | — |
| ybytu | ❌ | ❌ | inativo | — |
| kuaray | ❌ | ❌ | `pending` (verificar) | — |

**Pendências registradas (não bloqueiam o StênioREC):**
- kavure: criar `tailscaled-wait.service` e adicionar `wol-relay` à espera
- kuaray: investigar `Swarm.LocalNodeState=pending` (uptime > 30 dias)
- ybyra/ybytu: units de backup com `After=network` sem espera de tailnet

---

## 8. ADR-020 (GPU-Only) agora é código, não boa intenção — 29/09/2026

O [ADR-020](../../../../homelab/sumaenimahub/sumaenima-hub/docs/adr/020-gpu-only.md)
é **bloqueante** e exige *hard-fail na inicialização* e *NVML obrigatório*. Ele não
estava sendo cumprido: o `whisper.cpp` faz **fallback silencioso para CPU** e apenas
imprime `no GPU found` no log — foi assim que o worker de GPU rodou em CPU em 28/09
sem que nada acusasse (§6).

**Implementação (fonte: `app/server/src/device.rs`):**

| Requisito do ADR | Como está implementado |
|---|---|
| Hard-Fail (Exit Code 1) | `device::enforce()` em `main()`, antes de qualquer trabalho |
| NVML obrigatório | `nvml-wrapper` — `Nvml::init()` + `device_count()` |
| Sem fallback CPU | gate só no build `feature = "cuda"`; o `:cpu` do kavure não é afetado |
| Monitoramento | `/v1/ready` (503 se device ≠ cuda) → healthcheck → **autoheal** |

**Validação executada (29/09):**
```
$ docker run --rm --runtime nvidia -e NVIDIA_VISIBLE_DEVICES=none sumaenima-server:cuda
WARN  [Device] NVML initialised but reported 0 devices
ERROR ADR-020 violation: this build requires an NVIDIA GPU, but NVML reports
      none. CPU fallback is forbidden. Refusing to start.
exit_code=1                                        ← Exit Code 1, como o ADR manda

$ docker run --rm sumaenima-server:cpu             ← kavure (sem GPU): NÃO aborta
[Main] Listening on http://0.0.0.0:9098

$ curl -s http://127.0.0.1:9090/v1/ready
{"device":"cuda","device_count":1,"ready":true}    ← HTTP 200
```

> **Cinto e suspensório:** sem o runtime nvidia o container nem carrega
> (`libcuda.so.1: cannot open shared object file`, exit 127). Com o runtime mas sem
> devices, o gate NVML aborta. Com devices, o `/v1/ready` confirma. Três camadas.

---
