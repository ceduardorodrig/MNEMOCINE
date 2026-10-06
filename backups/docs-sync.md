---
tags: [homelab, backup, config, automation, meta]
---

# `homelab-docs-sync` — Publicação de Repositórios de Documentação (vault → público)

Publica no GitHub os repositórios cuja **fonte da verdade é o vault Obsidian**.
Engine única (script `homelab-docs-sync`) com **perfis por repo**; substituiu o
`mnemocine-docs-sync` em **06/10/2026** ao onboardar o currículo.

| Repo público | Vault (fonte) | Clone (trabalho) | Escopo do gate | Agenda |
|---|---|---|---|---|
| [`ceduardorodrig/MNEMOCINE`](https://github.com/ceduardorodrig/MNEMOCINE) | `agentic-ai/mnemocine` | `homelab/mnemocine` | `--scope homelab` | **04:45** |
| [`ceduardorodrig/ceduardorodrig`](https://github.com/ceduardorodrig/ceduardorodrig) | `agentic-ai/curriculum-vitae` | `homelab/ceduardorodrig` | `--scope cv` | **04:40** |

## O circuito

```
vault (fonte da verdade)                    cópia de trabalho                 destino
/mnt/NVME_PCI/agentic-ai/<proj>  ──rsync──>  /mnt/NVME_PCI/homelab/<repo>  ──git push──>  repo PÚBLICO
                                                                    │
                                                              gate do Stênio
                                                              ANTES do push
```

> ⚠️ **Os destinos são PÚBLICOS.** O gate do Stênio roda **antes** do push (no
> escopo do repo): um segredo publicado aqui é irreversível na prática.

| Peça | Onde |
|---|---|
| Script | `/usr/local/bin/homelab-docs-sync` (versionado em `sumaenima-hub/provisioning/scripts/`) |
| Units | `hl-mnemocine-docs-sync.{service,timer}` e `hl-ceduardorodrig-docs-sync.{service,timer}` (em `sumaenima-hub/provisioning/systemd/`) |
| Agendamento | **04:40** (currículo) e **04:45** (mnemocine), diário, `Persistent=true`, **roda como `edu`** |
| Log | `~/.local/state/<repo>-docs-sync.log` + journal |
| Alerta | ntfy `/backup` em falha de gate ou de push |

**Por que 04:40/04:45:** ambos rodam **antes** do `config-backup` (05:00). Publicar
primeiro garante que o espelho privado do NAS capture o estado **já sincronizado**,
não um meio-termo. Os horários são escalonados (5 min) para não concorrerem.

## Como a engine unifica (perfis por repo)

O `case` no topo do `homelab-docs-sync` define, por repo: `VAULT_SRC`, `REPO_DST`,
`SCOPE` (gate), `EXCLUDES` e o prefixo do commit. A **lógica é uma só** — corrigir
um bug corrige todos os repos.

Os `EXCLUDES` são o ponto sensível: o `rsync --delete` apagaria qualquer arquivo
que só exista no repo (sem contraparte no vault). No **currículo**, os excluídos
são `.git`, `.github` (o CI do repo, mais novo que o do vault), `.gitignore` e
`steniocheck.toml`. No **mnemocine**, além desses, `README.md`/`AGENTS.md`/
`LICENSE*` (mantidos só no repo) e os formatos de segredo.

## Por que roda como `edu` (e não root)

O push usa o **credential store do git** (`~/.git-credentials`, `0600`, dono
`edu`). Root não tem esse credential, e rodar o git como root num repo de usuário
reescreveria a posse dos arquivos. O script **não** precisa de privilégio: os
diretórios são do `edu`.

## 🐛 Lições herdadas (não regredir)

Cinco bugs corrigidos em 30/09/2026 no `mnemocine-docs-sync` e **preservados** na
engine unificada:

| # | Bug | Consequência |
|---|---|---|
| 1 | **`rsync --delete` apagava o `.github/`** | Destruiria o CI do próprio repo — o gate que protege o push. `.github` só existe no repo |
| 2 | **Nunca fazia `git pull`** | Push rejeitado — ou, pior, **reintroduzir** um segredo já removido |
| 3 | **Gate com `--path` genérico** | Escopo errado; o correto é o escopo do repo (`homelab`/`cv`) |
| 4 | **Log em `/var/log`** | `edu` não escreve lá → serviço falhava na primeira linha |
| 5 | **Sem árvore limpa obrigatória** | Edição manual no espelho seria sobrescrita em silêncio |

## O que o script faz

1. Exige árvore limpa (`git status --porcelain` vazio) — senão **aborta**.
2. `git fetch` + fast-forward se estiver atrás do `origin`.
3. `rsync -a --delete` do vault → repo, com os `EXCLUDES` do perfil.
4. **Gate obrigatório** `stenio --scope <escopo> --path <repo>` — qualquer
   violação **aborta** e alerta no ntfy.
5. `git add -A`; se não há mudança, sai limpo.
6. Commit `docs(<repo>): auto-sync documentation updates (<timestamp>)` + push.

## Operação

```bash
# rodar manualmente (e ver o resultado)
sudo systemctl start hl-ceduardorodrig-docs-sync.service
sudo systemctl start hl-mnemocine-docs-sync.service
systemctl status hl-ceduardorodrig-docs-sync.service -n 20

# quando rodam a seguir
systemctl list-timers 'hl-*-docs-sync.timer'

# logs
tail -30 ~/.local/state/ceduardorodrig-docs-sync.log
tail -30 ~/.local/state/mnemocine-docs-sync.log

# dry-run do rsync (não escreve)
rsync -an --delete --exclude=.github --exclude=.gitignore --exclude=steniocheck.toml \
  /mnt/NVME_PCI/agentic-ai/curriculum-vitae/ /mnt/NVME_PCI/homelab/ceduardorodrig/
```

## Regras de ouro

- **Nunca editar `/mnt/NVME_PCI/homelab/<repo>` à mão.** É cópia de trabalho: a
  fonte é o vault, e o próximo ciclo sobrescreve. A árvore suja faz o script
  **abortar** justamente para não perder trabalho por engano.
- **Nunca publicar sem o gate.** Os repos são **públicos**.
- **Segredo só no cofre sops** ([`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md)).
- **Repos de código não entram aqui:** `with-smooth-motion`, `macrokey-driver`,
  `mcmojave-cursor-unified`, `kururu-tab3lite-linux`, `mnemocine-acl` e o
  `sumaenimahub` **não têm fonte no vault** — são editados/commitados no próprio
  clone. O `homelab-docs-sync` só se aplica a repos de documentação.

## Ver também

- [`config-backup.md`](config-backup.md) — o circuito privado (NAS + git privado)
- [`strategy.md`](strategy.md) — visão geral da estratégia de backup
- [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) — o cofre
- [`../guides/stenio-ci-unificado.md`](../guides/stenio-ci-unificado.md) — o CI do `MNEMOCINE`

---
Última revisão: **2026-10-06** (unificação + onboarding do currículo).
