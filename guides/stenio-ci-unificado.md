---
tags: [homelab, governance, ci, stenio, github, rust]
---

# Stênio em CI — Abordagem Unificada

Como **qualquer** repositório do ecossistema audita a própria governança pelo
**StenioSentinel**, sem compilar Rust e sem duplicar configuração.

Estabelecido em **29/09/2026**.

## O problema que isto resolve

Cada repositório que usava o Stênio tinha o **seu próprio** workflow de CI, que:

1. clonava o código do motor de dentro de outro repositório e rodava
   `cargo build --release` — **~1 min por CI**, por repo;
2. **quebrava** sempre que o caminho do motor mudava;
3. congelava cada repo numa versão diferente do motor.

O caso concreto: o CI do repositório de currículos (`ceduardorodrig`) compilava
`sumaenima-hub/scripts/steniocheck-rs`, **purgado** no commit `70d7132` do hub.
Passou a falhar com `error: manifest path ... does not exist`. Pior: **houve runs
marcados como "success"** enquanto o checkout pegava um estado antigo do hub — ou
seja, a falha ficava **mascarada**.

## A arquitetura

```
STENIO-SENTINEL (repositório do motor, PÚBLICO)
├── .github/workflows/release.yml              ← builda e publica o binário
│      disparo: push de tag v*.*.*
│      asseta: stenio + stenio.sha256
└── .github/actions/stenio-check/action.yml    ← composite action reutilizável
       baixa o binário da release e executa

CONSUMIDORES (qualquer repositório)
└── .github/workflows/ci.yml
       - uses: ceduardorodrig/STENIO-SENTINEL/.github/actions/stenio-check@v1
         with:
           scope: all
```

**Resultado:** CI em **~9 s** (só download), **uma única versão** do motor para
todos os repos, e atualizar o motor = publicar uma tag.

## Como usar num repositório

```yaml
name: ci

on: [push, pull_request]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  check:
    name: Governance Audit (Rust Native)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: StenioSentinel — auditar repositório
        uses: ceduardorodrig/STENIO-SENTINEL/.github/actions/stenio-check@v1
        with:
          scope: all
          path: .
          github-format: "true"
```

### Inputs da action

| Input | Obrigatório | Default | Descrição |
|---|---|---|---|
| `scope` | ✅ | — | `hub`, `homelab`, `vault`, `cv`, `fork`, `mirror`, `all` |
| `path` | ❌ | `.` | Raiz a escanear |
| `strict` | ❌ | `false` | Reprova também com avisos |
| `github-format` | ❌ | `true` | Emite anotações `::error`/`::warning` no PR |
| `version` | ❌ | release mais recente | Fixa uma release (ex.: `v3.8.1`) |

### Qual `scope` usar

| Repositório | Scope |
|---|---|
| `SUMAENIMA-HUB` | `hub` |
| `ceduardorodrig` (currículos) | `cv` |
| `MNEMOCINE` / vault | `vault` |
| `MNEMOCINE-CONFIGS` (espelho gerado) | **`mirror`** |
| `macrokey-driver` (fork) | **`fork`** |
| Tier A genéricos (Rust/C) | `all` |

> ⚠️ **`MNEMOCINE-CONFIGS` NÃO usa `homelab`.** É um espelho automático do estado
> dos hosts, não a documentação do homelab. Ver
> [`../governance/stenio-troubleshooting.md`](../governance/stenio-troubleshooting.md) §4.

## Convenção de tags (dois conceitos diferentes!)

⚠️ **Esta é a parte que mais confunde:**

| Tag | O que versiona | Exemplo |
|---|---|---|
| **`v1`** (major, flutuante) | A **action** — re-apontada a cada release | `uses: …/stenio-check@v1` |
| **`vX.Y.Z`** (imutável) | A **release do binário** | `releases/download/v3.2.0/stenio` |

> A action **não** deduz a versão do binário a partir do próprio ref: a primeira
> versão fazia isso e tentava baixar `releases/download/v1/stenio` → **404**.
> Hoje ela usa sempre a release **mais recente**; quem precisa fixar passa
> `with: version: v3.8.4`.

### ⚠️ A trilha `v1` é movida automaticamente — nunca à mão

A tag `v1` é a **major da action** (o contrato de interface dos consumidores),
**não** a major do binário (`v3.8.4`). São espaços de versão independentes.

O `release.yml` move a `v1` sozinho a cada release publicada, com verificação
pós-push que falha alto se a trilha não ficar no commit esperado:

```
🛡️ Movendo a trilha da action 'v1' → v3.8.4
   alvo: v3.8.4 (d5325807…)
 + a19c594…2c02cf8 v1 -> v1 (forced update)
✅ v1 → v3.8.4 (d5325807…)
```

Mover à mão **não** é o procedimento — foi o que deixou a `v1` 8 commits atrás em
29/09/2026. Ver `governance/release-policy.md` §3b.

**Publicar uma versão nova do motor:**

```console
$ cd governance/stenio
$ # 1. bump do Cargo.toml conforme a política SemVer (governance/release-policy.md)
$ cargo build --release && ./target/release/stenio --self-test && ./target/release/stenio --guardian
$ git commit -am "release: vX.Y.Z"
$ git tag -a vX.Y.Z -m "…" && git push origin main vX.Y.Z   # dispara o release.yml
$ # A trilha v1 é movida pelo PRÓPRIO workflow — não é passo manual.
```

## Repositórios cobertos (29/09/2026)

| Repositório | CI | Scope | Estado |
|---|---|---|---|
| `STENIO-SENTINEL` | `ci.yml` + `release.yml` | — | ✅ motor (v3.8.1) |
| `ceduardorodrig` (CV) | `ci.yml` | `cv` | ✅ (era **quebrado**) |
| `WITH-SMOOTH-MOTION` | `ci.yml` | `all` | ✅ (não tinha CI) |
| `MCMOJAVE-CURSOR-UNIFIED` | `ci.yml` | `all` | ✅ (não tinha CI) |
| `KURURU-TAB3LITE-LINUX` | `ci.yml` | `all` | ✅ (não tinha CI) |
| `MNEMOCINE` | `ci.yml` | `homelab` | ✅ (não tinha CI; achou a senha do Valheim) |
| `MNEMOCINE-CONFIGS` | `ci.yml` | **`mirror`** | ✅ (não tinha CI; achou o token do rclone + CrowdSec) |
| `macrokey-driver` | `ci.yml` | **`fork`** | 🍴 derivado — verde em ~6 s |
| `SUMAENIMA-HUB` | `ci.yml` | — | ⚠️ sem auditoria do Stênio (só `cargo check` + build) |

### O espelho `MNEMOCINE-CONFIGS` roda `scope: mirror`

Este repositório ficou **dois meses sem CI** e, quando a auditoria foi ligada, o
escopo `mirror` encontrou **credencial real commitada desde 09/08/2026**: o token
OAuth do rclone (GDrive) e as credenciais da API do CrowdSec. Ver §4 do
[`stenio-troubleshooting.md`](../governance/stenio-troubleshooting.md).

```yaml
      - name: StenioSentinel — auditar espelho de configs
        uses: ceduardorodrig/STENIO-SENTINEL/.github/actions/stenio-check@v1
        with:
          scope: mirror
          github-format: "true"
          strict: "false"   # auditoria de estado, não bloqueio de merge
```

> ⚠️ O espelho é **regenerado todo dia às 05:55**. Se o CI ficar vermelho após um
> commit do bot, a correção é **na origem (no host)** — editar arquivo do espelho
> à mão é apagado no próximo ciclo.

## Histórico de releases do motor (29/09/2026)

| Versão | Mudança |
|---|---|
| `v3.2.0` | primeiro binário publicado + composite action |
| `v3.3.0` | `--scope fork` (repo derivado) |
| `v3.4.0` | `--tools` (auditoria de ferramentas de operação) |
| `v3.5.0` | detector de segredo com prefixo YAML |
| `v3.6.0` | 🐛 **correção de segurança**: `SEC-*` de infra passou a rodar no `fork` |
| `v3.7.0` | `--scope mirror` (repo gerado) + templates ignorados |
| `v3.8.0` | 🐛 **`SEC-SECRETS` detecta senha em Markdown** (era ponto cego) |
| `v3.8.1` | `ARCH-LEGACY-PYTHON` só no código próprio (`code_debt`) |

### ⚠️ O `macrokey-driver` é um repositório **derivado** (fork)

Ele é **fork** de `nonatofabio/macrokey-driver` (Python), onde você fez correções
pontuais (media keys, persistência). Rodar `--scope all` nele dá **305 erros** —
quase todos de `ARCH-NO-PYTHON`, que proíbe Python.

**Isso não é falso-positivo**: a regra está certa para o ecossistema. O problema é
que ela **não se aplica a código de terceiros**. Ver a categoria **Repositório
Derivado** em [`../governance/agent-conventions.md`](../governance/agent-conventions.md) §2b:

- **Não prometer reescrever o upstream** — uma diretiva que você não vai cumprir é
  lei morta, e leis mortas corroem as vivas.
- **O que SE aplica:** `SEC-SECRETS`, inglês, disclaimer, licença/atribuição.
- **O que NÃO se aplica:** `ARCH-*`, `GOV-AGENT-LAWS` (38 leis do hub), `RUST-*`.

> ✅ **IMPLEMENTADO em 29/09/2026** (motor `v3.3.0`): o escopo `--scope fork`
> (alias `derived`) existe e aplica **só** o subconjunto que protege um derivado:
> `SEC-*`, `VAULT-*`, `DOC-*`, higiene de artefatos e regras de infra quando o
> alvo for infra. Medido no fork: **305 erros → 0 violações**, e um token
> plantado continua sendo pego por `SEC-SECRETS`.
>
> O CI do `macrokey-driver` já roda com `scope: fork` (verde em ~6 s).

## Segurança

- O repositório do motor é **público** → o download do binário **não exige token**
  nem `ssh-key` (o antigo `STENIOCHECK_SSH_KEY` foi eliminado junto com o workflow
  quebrado).
- O binário é **verificado por `sha256`** após o download — ele executa com os
  privilégios do runner e vem da rede.
- A release só é publicada **depois** de `--self-test` e `--guardian` passarem:
  uma release com motor defeituoso contaminaria **todos** os consumidores de uma
  vez.

## Ver também

- [`../governance/release-policy.md`](../governance/release-policy.md) — SemVer
- [`../governance/stenio/README.md`](../governance/stenio/README.md) — o motor
- [`../governance/stenio-troubleshooting.md`](../governance/stenio-troubleshooting.md)

---
Última revisão: **2026-09-29**.
