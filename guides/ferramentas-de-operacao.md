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

### Ferramentas de terceiros sem pacote na distro — mapa `VENDOR_TOOLS` (06/10/2026)

Padronizamos as ferramentas CLI Rust nos **5 nós** usando o **gerenciador de pacotes nativo**
(pacman no Arch, apt no Ubuntu/Mint) — caem em `/usr/bin`, são atualizadas pelo sistema e
**não** passam pela auditoria de `/usr/local/bin`. Mas 5 ferramentas **não têm pacote no
Ubuntu**: `dust`, `procs`, `btm`, `ouch`, `tokei`.

Para essas, o próprio **instalador** ganhou um mapa `VENDOR_TOOLS` (binário upstream em
`/usr/local/bin`, ou `cargo:<crate>` compilado no build-node). Como o motor lê o instalador
em tempo de execução, elas passam a ser **declaradas** → o `stenio --tools` não as acusa mais
como órfãs. Sem editar o motor.

```bash
./provisioning/scripts/install-homelab-tools.sh --list      # mostra os 3 grupos
./provisioning/scripts/install-homelab-tools.sh --all       # instala tudo (inclui VENDOR_TOOLS)
./provisioning/scripts/install-homelab-tools.sh dust        # instala uma ferramenta de terceiros
```

> Antes disso, instalar essas 5 direto em `/usr/local/bin` gerava **10 órfãs** no `stenio --tools`
> (falso-positivo: elas são de terceiros, mas a allowlist/declaração não as conhecia). O mapa
> `VENDOR_TOOLS` fecha esse gap **sem tocar no motor**.

### Integração de shell — `zoxide` e `atuin` (06/10/2026)

Ferramentas de navegação/histórico só funcionam com o **hook no shell** — o binário sozinho é gap:

| Host | Shell | Onde | Linha |
|---|---|---|---|
| psicopompo | **fish** | `~/.config/fish/config.fish` | `zoxide init fish \| source` + `atuin init fish \| source` |
| kavure, kuaray, ybytu, ybyra | bash | `~/.bashrc` (shell **interativo**) | `eval "$(zoxide init bash)"` |

- `~/.config/fish` **passou a entrar no `config-backup`** (06/10/2026) — antes a config do shell
  do psicopompo não era espelhada.
- `atuin` existe no **Arch** (pacman) — **não há pacote no Ubuntu**, então nos servidores ficou só o `zoxide`.

### `~/.ssh/config` — ybyra pelo tailnet (06/10/2026)

O `Host ybyra` apontava para o **IP público** da Oracle (`140.238.179.219`) — instável, e por isso o
`stenio --tools` falhava aquele nó de forma **intermitente** (`ssh falhou, exit=255`). Passou a usar
o **IP da tailnet** (`100.66.224.34`), como o `ybytu` já fazia. Validado 3/3.
O `~/.ssh/config` entrou nos **GOLDEN FILES** do `config-backup` (só o arquivo — as chaves privadas
**não** são espelhadas).

## ⚠️ Pendência aberta (06/10/2026) — tooling do Dominium

As ferramentas do modpack **Dominium** (`client-push.sh`, `sync_mods.py`, `export_mrpack.py`,
`README.md`) vivem em `/srv/data/minecraft/minecraftserver [dominium]/` **no kavure** — ou seja,
**fora do repo**, exatamente o padrão que esta regra existe para evitar. O conflito:

- esta regra manda código de operação para `SUMAENIMA-HUB/provisioning/`;
- o **ADR-036** proíbe `.py` no repositório.

→ O caminho compliant é **reescrever em Rust** (crate em `provisioning/`, como os demais).
Mitigação já aplicada: os scripts **entram no espelho do `config-backup`** (exclusões do kavure
ajustadas) — sobrevivem a defeito de disco, mas seguem **invisíveis ao gate** até o rewrite.
Ver [`../services/crafty.md`](../services/crafty.md) e [`../services/crafty/dominium-permissions.md`](../services/crafty/dominium-permissions.md).

## Ver também

- [`stenio-ci-unificado.md`](stenio-ci-unificado.md) — como o CI consome o motor
- [`../governance/agent-conventions.md`](../governance/agent-conventions.md) — convenções
- [`../backups/config-backup.md`](../backups/config-backup.md) — o espelho das configs

---
Última revisão: **2026-09-29**.
