---
tags: [homelab, governance, stenio, tooling, rust, guides]
---

# Ferramentas de Operação — Fonte Única no Repositório

Como (e por que) **todo código que roda em `/usr/local/bin`** passa a viver em
`SUMAENIMA-HUB/provisioning/`. Estabelecido em **29/09/2026**.

## O problema

Scripts de operação viviam **apenas nos hosts**, fora de qualquer repositório:

- **invisíveis ao gate** — o Stênio audita repositório, não sistema de arquivos;
- **sem diff** — não havia versão anterior para comparar;
- **sem revisão** — mudar um backup não passava por PR.

Três custos reais e medidos:

| Caso | Consequência |
|---|---|
| **`smart-metrics.py`** violou `ARCH-NO-PYTHON` em **3 hosts** | Semanas sem ninguém ver |
| **`scryfall-prefetch`** vivia em `/tmp` | Evaporou num reboot; cobertura do mirror **congelada em 62% por ~1 mês** |
| Um `scryfall-prefetch` **instalado corrompido** | Sem diff, ninguém percebeu |

## A regra

| Onde | O que fica |
|---|---|
| **`provisioning/scripts/`** | Ferramentas de operação (shell e wrappers) |
| **`provisioning/<crate>/`** | Ferramentas Rust (binário compilado e distribuído) |
| **`provisioning/systemd/`** | Units e timers |
| **`/usr/local/bin`** | **Só o que foi instalado daqui** |

> **Vale para os 5 hosts:** psicopompo, kavure, kuaray, ybyra, ybytu.

## Como operar

```console
# o que existe e onde
$ ./provisioning/scripts/install-homelab-tools.sh --list

# o que está fora do repo (o comando que importa)
$ ./provisioning/scripts/install-homelab-tools.sh --audit
$ stenio --tools --path .        # equivalente, via motor

# instalar
$ ./provisioning/scripts/install-homelab-tools.sh smart-metrics
$ ./provisioning/scripts/install-homelab-tools.sh --host kavure --all
$ ./provisioning/scripts/install-homelab-tools.sh --uninstall
```

## Como as ferramentas Rust são distribuídas

O binário é **compilado uma vez no psicopompo** (build-node, ADR-026) e copiado.
Os hosts de destino **não têm toolchain Rust** — e não precisam.

```
provisioning/<crate>/  --cargo build-->  target/release/<tool>
                                              │
                              install-homelab-tools.sh (scp)
                                              ▼
                                    /usr/local/bin/<tool>
```

## Gates

Três camadas, cada uma pegando uma classe de erro:

| Gate | O que detecta |
|---|---|
| **`stenio --tools`** | Ferramenta no host e **fora** do repo (órfã) |
| **`stenio --diff`** no hub | Qualquer regra do ecossistema sobre o código versionado |
| **`stenio --scope homelab`** | Documentação e infraestrutura |

> **Como `--tools` funciona:** cruza `/usr/local/bin` de cada nó com o que
> `provisioning/` declara. A fonte da verdade é o próprio instalador
> (`install-homelab-tools.sh`), lido em tempo de execução — assim auditar e
> instalar nunca divergem.
>
> **Provado com canário:** uma ferramenta plantada em `/usr/local/bin` apareceu
> como órfã e foi removida em seguida.

## Armadilhas do systemd encontradas no caminho

Registradas porque **aparecem sem aviso** e já custaram tempo:

| Diretiva | Problema |
|---|---|
| `RuntimeMaxSec=` com `Type=oneshot` | O systemd **ignora** e avisa só no boot: *"has no effect in combination with Type=oneshot"*. Ordenar o teto dentro do script |
| `Restart=` com `Type=oneshot` | Mesmo caso — não tem efeito. Usar `Type=simple` (como o `sumaenima-gpu.service`) |
| `OnFailure=` apontando para template inexistente | Falha **silenciosa**. O `notify-backup-failure@` não existia em nenhum host até 29/09 |
| `User=root` com sops | A chave age é `0600` do dono; **root não decripta**. Usar `User=` do dono |

## Python no operacional

A lei `ARCH-NO-PYTHON` vale para o que **nós escrevemos**. Em 29/09 foram
migrados:

| Antes | Depois |
|---|---|
| `smart-metrics.py` (+ `.sh` orquestrador) | crate **`smart-metrics`** + `.sh` versionado |
| `scryfall-prefetch` (Python em `/tmp`) | crate **`scryfall-prefetch`** + timer |
| `scryfall-sync` (2× `python3 -c json.load`) | crate **`scryfall-sync`** |
| `zomboid-save` (87 linhas de RCON) | crate **`zomboid-ctl`** + wrapper de nome |

> **Ferramentas de terceiros** (ex.: `bat`, `fd`) não entram nessa regra — a
> allowlist do auditor as ignora explicitamente.

## Ver também

- [`stenio-ci-unificado.md`](stenio-ci-unificado.md) — como o CI consome o motor
- [`../governance/agent-conventions.md`](../governance/agent-conventions.md) — convenções
- [`../backups/config-backup.md`](../backups/config-backup.md) — o espelho das configs

---
Última revisão: **2026-09-29**.
