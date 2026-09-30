---
tags: [homelab, backup, config, automation, meta]
---

# `mnemocine-docs-sync` — Publicação da Documentação no Repo Público

Publica a documentação do Homelab (vault) no repositório **público**
[`ceduardorodrig/MNEMOCINE`](https://github.com/ceduardorodrig/MNEMOCINE).
Canonizado e agendado em **30/09/2026**.

## O circuito

```
vault (fonte da verdade)              cópia de trabalho            destino
/mnt/NVME_PCI/agentic-ai/mnemocine  ──rsync──>  /mnt/NVME_PCI/homelab/mnemocine  ──git push──>  MNEMOCINE (PÚBLICO)
                                                                          │
                                                                    gate do Stênio
                                                                    ANTES do push
```

> ⚠️ **O destino é PÚBLICO.** O gate do Stênio roda **antes** do push
> (`--scope homelab`): um segredo publicado aqui é irreversível na prática.

| Peça | Onde |
|---|---|
| Script | `/usr/local/bin/mnemocine-docs-sync` (versionado em `provisioning/scripts/`) |
| Units | `hl-mnemocine-docs-sync.{service,timer}` (versionadas em `provisioning/systemd/`) |
| Agendamento | `04:45` diário (`Persistent=true`), **roda como `edu`** |
| Log | `~/.local/state/mnemocine-docs-sync.log` + journal |
| Alerta | ntfy `/backup` em falha de gate ou de push |

**Por que 04:45:** é 15 min antes do `config-backup` (05:00). Publicar primeiro
garante que o espelho privado capture o estado **já sincronizado**, não um
meio-termo.

## Por que roda como `edu` (e não root)

O push usa o **credential store do git** (`~/.git-credentials`, `0600`, dono
`edu`) com o PAT `GH_PUSH_TOKEN` do repo. Root não tem esse credential, e rodar
o git como root num repo de usuário reescreveria a posse dos arquivos. O script
**não** precisa de privilégio: ambos os diretórios são do `edu`.

## 🐛 Cinco bugs corrigidos em 30/09/2026

O script existia desde 25/09 mas **nunca havia sido agendado** — nenhum dos bugs
chegou a se manifestar em produção. Foram encontrados ao ligar o timer.

| # | Bug | Consequência se tivesse rodado |
|---|---|---|
| 1 | **`rsync --delete` apagava o `.github/`** | O CI do próprio `MNEMOCINE` (criado em 29/09) seria **destruído** — o gate que protege este push. `.github` só existe no repo, não tem contraparte no vault |
| 2 | **Nunca fazia `git pull`** | O repo local ficou 2 commits atrás do `origin` (que já tinha o PR #1 removendo a senha do Valheim). O push seria rejeitado — ou, numa base pior, **reintroduziria o segredo** no repo público |
| 3 | **Gate usava `stenio --path` genérico** | Escopo errado. O correto é `--scope homelab` (frontmatter, tags, NFS-hard e `SEC-SECRETS`) |
| 4 | **Log em `/var/log`** | O serviço roda como `edu`, que não escreve lá → `Permission denied` e o serviço **falhava na primeira linha** |
| 5 | **Sem árvore limpa obrigatória** | Um working tree sujo (edição manual no espelho) seria silenciosamente sobrescrito pelo rsync |

Correções aplicadas: `.github` no `--exclude`; `git fetch` + `merge --ff-only`
antes de tudo; gate `--scope homelab`; log no `$HOME`; **aborta se a árvore
estiver suja**; ntfy em falha de gate/push.

## Skill do procedimento (o que o script faz)

1. Exige árvore limpa (`git status --porcelain` vazio) — senão **aborta**.
2. `git fetch` + fast-forward se estiver atrás do `origin`.
3. `rsync -a --delete` do vault → repo, excluindo `.github`, `.git`, segredos
   (`*.enc.env`, `*.key`, `*.pem`) e temporários.
4. **Gate obrigatório** `stenio --scope homelab --path <repo>` — qualquer
   violação **aborta** e alerta no ntfy.
5. `git add -A`; se não há mudança, sai limpo.
6. Commit `docs(homelab): auto-sync documentation updates (<timestamp>)` + push.

## Operação

```bash
# rodar manualmente (e ver o resultado)
sudo systemctl start hl-mnemocine-docs-sync.service
systemctl status hl-mnemocine-docs-sync.service -n 20

# quando roda a seguir
systemctl list-timers hl-mnemocine-docs-sync.timer

# log
tail -30 ~/.local/state/mnemocine-docs-sync.log
journalctl -u hl-mnemocine-docs-sync.service -n 50

# dry-run do rsync (não escreve)
sudo rsync -an --delete --exclude=.github ... /mnt/NVME_PCI/agentic-ai/mnemocine/ /mnt/NVME_PCI/homelab/mnemocine/
```

## Regras de ouro

- **Nunca editar `/mnt/NVME_PCI/homelab/mnemocine` à mão.** É cópia de trabalho:
  a fonte é o vault, e o próximo ciclo sobrescreve. A árvore suja faz o script
  **abortar** justamente para não perder trabalho por engano — se você editar
  ali, o sync para (e alerta) em vez de apagar.
- **Nunca publicar sem o gate.** É repo **público**.
- **Segredo só no cofre sops** ([`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md)).
  O rsync exclui os formatos de segredo, mas isso é a segunda linha; a primeira
  é não escrever segredo na doc.

## Ver também

- [`config-backup.md`](config-backup.md) — o outro circuito (privado) e por que
  `mnemocine/` é **excluído** dele
- [`strategy.md`](strategy.md) — visão geral da estratégia de backup
- [`../guides/secrets-centralizados.md`](../guides/secrets-centralizados.md) — o cofre
- [`../guides/stenio-ci-unificado.md`](../guides/stenio-ci-unificado.md) — o CI do `MNEMOCINE`

---
Última revisão: **2026-09-30**.
