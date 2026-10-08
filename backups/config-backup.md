---
tags: [homelab, backup, config, docker, compose]
---

# Backup Canônico de Configs — `config-backup`

> Espelho central das CONFIGURAÇÕES de todos os hosts no NAS (psicopompo `/mnt/BACKUP/configs-homelab`).
> Nasceu da lição do CasaOS (08/08/2026): configs de ~12 containers apagadas sem backup porque **não havia código nem espelho**.

## Arquitetura

```
Cada host (05:00) → /usr/local/bin/config-backup (systemd timer hl-config-backup.timer)
  0. GUARDA DE ROOT (10/08): `id -u` != 0 → aborta ANTES de rsync/ntfy
  1. check TCP 2049 (NAS alcançável) — fail-fast
  2. rsync -a --delete --delete-excluded --no-o --no-g -x  (só espelho; fontes são só lidas)
  3. golden files (composes + /etc selecionado) → <dest>/golden/
  4. ntfy /backup (falha=high, sucesso=low) + health file /srv/health/
      → espelho em /mnt/BACKUP/configs-homelab/{host}/
         ├─ git → GitHub privado mnemocine (05:55)
         ├─ restic → /mnt/BACKUP/repos/restic/configs (05:40, retenção 14d/8s/6m)
         └─ snapper (config `backup`) — anti-deleção do próprio espelho
```

**Horário padronizado (janela 05:00–06:00 BRT; VPS em 08:00 UTC):**

| Hora | Job |
|---|---|
| 04:40 / 04:45 | **homelab-docs-sync (psicopompo)** — publica os repos de docs do vault: currículo (04:40) e `MNEMOCINE` (04:45) (ver [`docs-sync.md`](docs-sync.md)) |
| 04:55 | **noctalia-config-export (psicopompo, user)** — `noctalia config export` → `~/.config/noctalia/export/merged-config.toml` (camada efetiva: declarativa + overrides GUI). **Subpasta de propósito** — o Noctalia só auto-carrega `*.toml` na raiz da pasta de config |
| 05:00 | config-backup (todos) |
| 05:00 | zomboid-restart (kavure, inalterado) |
| 05:15 | zomboid-backup (kavure) |
| 05:20 | agentic-ai-backup (psicopompo) |
| 05:40 | restic-configs-backup |
| 05:55 | etckeeper-push + configs-git-push |
| dom 06:00 | restic check |

> **Nota de política (24/09/2026):** o override `~/.local/state/noctalia/settings.toml` contém a política de idle do desktop Hyprland/Noctalia (lock 900 s; screen off desativado enquanto desbloqueado e 60 s quando bloqueado; lock+suspend desativado). Esse arquivo é espelhado junto com `~/.config/noctalia`; `merged-config.toml` é somente saída gerada e não deve ser editado manualmente.
>
> **⚠️ Correção de rota (06/10/2026):** o dump `merged-config.toml` passou a ser gravado em `~/.config/noctalia/export/` (subpasta). Antes ficava na **raiz** da pasta de config, onde o Noctalia o carregava como camada declarativa (ordem alfabética, último vence) — ordenando depois de `config.toml`, ele **anulava o config escrito à mão** e o export seguinte reconsagrava o valor antigo (chave congelada). Subpastas não são auto-carregadas, então `export/` é ponto cego do shell e o artefato continua versionado aqui no espelho. Detalhes em [`../guides/hyprland-noctalia-guide.md`](../guides/hyprland-noctalia-guide.md) → "Fontes e manutenção".

## Componentes

| Peça | Onde |
|---|---|
| Script | `/usr/local/bin/config-backup` (idêntico em todos) |
| Config por host | `/etc/config-backup.conf` (`SRC_DIRS`, `EXCLUDES`, `GOLDEN_FILES`, `MOUNT`, `HOST`, `POST_CMD`) |
| Export NFS | `/mnt/BACKUP/configs-homelab` (rw, all_squash, anonuid=1000) + `/mnt/BACKUP/repos/git` |
| Mounts | `/srv/backup-configs` (configs), `/srv/backup-gitrepos` (git bare) — fstab `nofail` |
| Agendamento | systemd timer `hl-config-backup.timer` (05:00, `Persistent=true`) — migrado do cron em 10/08 |
| **Autenticação git push (GitHub)** | `hl-configs-git-push.service` roda como `User=edu`; usa **credential store** do git (`~/.git-credentials`, 0600, dono `edu`) com token PAT escopo `repo` do repo privado `MNEMOCINE`. O token **NUNCA** vai em claro pro vault/NAS — backup no **store sops** como `GH_PUSH_TOKEN` (`guides/secrets-centralizados.md`; restore: `sops-decrypt.sh GH_PUSH_TOKEN` → recriar `~/.git-credentials`). Canonizado 21/09/2026 — antes o helper era `gh auth git-credential` (token vazio → push falhava silenciosamente desde ~09/2026) |

> **Guarda de root (10/08/2026):** o script **deve rodar como root** (o timer roda como root). Execução manual como não-root aborta imediatamente (`exit 1`, sem rsync/ntfy) — evita alerta "FALHOU" falso. O script lê configs root e escreve em `/var/log` + `/srv/health`. Para rodar manualmente: `sudo /usr/local/bin/config-backup` (ou `pkexec`).
| Health | `/srv/health/config-backup-{host}-last-ok` |

## Fontes por host (o que é espelhado)

| Host | SRC_DIRS | Excludes principais |
|---|---|---|
| psicopompo | `/home/edu/homelab` (**composes dos serviços** — primeiro na lista, ver nota abaixo), `/mnt/NVME_PCI/homelab` (raiz de **projetos**: sumaenimahub, transcribe, …), `/usr/local/bin`, syncthing state, **desktop configs** (`~/.config/hypr`, `~/.config/noctalia`, `~/.config/uwsm` — env: cursor McMojave + NVIDIA, `~/.config/environment.d`, `~/.config/steam-launch-options`, `~/.local/state/noctalia`, `~/.config/gtk-3.0`, `~/.config/gtk-4.0`, `~/.config/qt6ct`, **`~/.config/fish`** — shell config (zoxide/atuin), 06/10/2026), **instância do Prism `Dominium`** (`~/.local/share/PrismLauncher/instances/Dominium` — fonte de verdade do modpack, adicionado 06/10/2026: mods/config/loader, ~484 MB), rclone, wallpapers. **GOLDEN FILES:** `/var/lib/noctalia-greeter/greeter.toml`, `/etc/greetd/config.toml`, `/etc/systemd/sleep.conf.d/60-freeze.conf`, `/etc/systemd/system/tailscaled-wait.service`, `/etc/systemd/system/nfs-server.service.d/10-tailscaled-wait.conf`, `/etc/smartd.conf`, `/etc/sudoers.d/99-edu-homelab`, `/etc/ufw/user{,6}.rules`, `~/.gtkrc-2.0`, **`~/.ssh/config`** (hosts/usuários/chaves — o arquivo, **sem** as chaves privadas; adicionado 06/10/2026), fstab, exports, pacman, snapper configs. | `ollama`, `index-v2`, `*.log`, **`target`** (build Rust), **state Noctalia** (`clipboard`, `notification_history*`, `recently_used.json`, `usage_counts.json`, `wallpaper_shuffle.json`, `plugin-cache`, `community-*`, `plugins/materialized`, `plugins/sources`, `plugins/data`), **Prism pesado/pessoal** (`minecraft/Distant_Horizons_server_data`, `saves`, `logs`, `crash-reports`, `debug`, `xaero`, `XaeroWaypoints_BACKUP*`, `screenshots`, `essential`, `pfm`, `downloads`, `server-resource-packs`, `.fabric`, `hs_err_pid*`, `replay_pid*`, `nvngx*`, `config/super_resolution`) |
| kavure | `/srv/data` | `zomboid/data`, `pz-dedicated`, `workshop-mods`, `sumaenimahub/SUMAENIMA-HUB`, `volumes`, `backup`, `aiostreams/anime-database`, **`minecraft/minecraftserver \[dominium\]/MINECRAFT SERVER`**, **`minecraft/minecraftserver \[dominium\]/crafty`**, **`minecraft/minecraftserver \[dominium\]/DOMINIUM-MODPACK`**, `minecraft/offbox`, `minecraft/pre-update` (06/10/2026 — antes excluía `minecraft` inteiro; agora o **tooling** em `minecraft/minecraftserver [dominium]/` entra no espelho) |
| kuaray | `/home/kuaray/docker`, `/home/kuaray/homelab` | (genéricos) |
| ybytu | `/home/ubuntu/homelab` | (genéricos) |
| ybyra | `/home/ubuntu/homelab`, `docker-compose.ybyra.yml` | `*.tar.gz`/`*.zip`/`*.tgz`/`*.tar` |

**Excluídos globalmente (segredos — NUNCA vão pro espelho):** `.env`, `secrets.yaml`, `slskd.yml`, `passwd`, `config.xml` (API keys), **`htpasswd`**, **`registry.key`** (segredos do registry, 07/10/2026), `*.db`, `*.log`, `*.lock`, `.venv`, `node_modules`, `.git`, `.cache`, `.stversions`. Segredos vivem no **store sops/age** (`/mnt/NVME_PCI/secrets/`), que sincroniza criptografado via Syncthing.

**`mnemocine/` é excluído no psicopompo (30/09/2026):** `/mnt/NVME_PCI/homelab/mnemocine` é **derivado** — o `homelab-docs-sync` copia do vault `agentic-ai/mnemocine` e publica no repo público `MNEMOCINE`. O circuito privado não precisa versionar uma segunda cópia da mesma documentação, e a cópia intermediária ficava **congelada** (o sync não tinha timer), gerando 97 divergências e re-acusando segredos já corrigidos no espelho. Ver [`docs-sync.md`](docs-sync.md).

**Duas fontes com o mesmo basename (07/10/2026):** `/home/edu/homelab` (composes dos serviços)
e `/mnt/NVME_PCI/homelab` (projetos) espelham **as duas** para `psicopompo/homelab/`. O `rsync`
resolve **caminho repetido mantendo a PRIMEIRA fonte** — por isso `/home/edu/homelab` vem
**primeiro**. Sem isso, as cópias velhas de setembro (em `/mnt/NVME_PCI/homelab`, sem
healthcheck) venciam e os composes novos não apareciam no espelho (era a causa dos avisos
`INFRA-COMPOSE-HEALTHCHECK` do psicopompo). O `--delete` respeita a **união** das fontes
(testado em dry-run: **0 deleções indevidas**). Segredos do `registry` (`htpasswd`,
`registry.key`) ficam de fora por `EXCLUDES` — o `registry.crt` (público) entra.

## Como adicionar um serviço/host novo

1. No host: criar/confirmar o compose em `/home/{user}/homelab/{serviço}/`.
2. Incluir a pasta em `SRC_DIRS` do `/etc/config-backup.conf` (e `EXCLUDES` p/ dados pesados).
3. `docker compose config --quiet` para validar o compose.
4. Rodar `sudo /usr/local/bin/config-backup` → conferir no NAS + `git log`/`restic snapshots`.
5. Documentar no vault + README-INDEX.

## Restore

- **Espelho (NAS):** copiar do `/mnt/BACKUP/configs-homelab/{host}/` de volta pro host.
- **Versões:** `restic -r /mnt/BACKUP/repos/restic/configs --insecure-no-password snapshots` + `restore`.
- **Anti-deleção:** `sudo snapper -c backup list` (snapshot do próprio espelho).
- **Etckeeper (/etc):** `git --git-dir=/srv/backup-gitrepos/etckeeper-{host}.git log` (NAS) ou no host `git -C /etc log`.

## Incidente 08/10/2026 — automount morto → *stale file handle* (ybyra)

**Sintoma:** `config-backup` do **ybyra** falhando desde **27/09/2026** (ntfy "config-backup
FALHOU (ybyra)"), com o espelho no NAS **congelado** naquela data. O `rsync` reportava:

```
rsync: [Receiver] ERROR: cannot stat destination "/srv/backup-configs/ybyra/": Stale file handle (116)
```

**Causa raiz:** a unit `srv-backup\x2dconfigs.automount` estava **`inactive (dead)` desde
28/08** (pós-reboot). O mount continuou servindo de um **estado obsoleto**, com as opções
antigas (`hard,timeo=600`) — e só quebrou quando o servidor NFS invalidou o *file handle*.

**Correção (por host):**

```bash
U=$(systemd-escape -p --suffix=automount /srv/backup-configs)
umount -l /srv/backup-configs
systemctl daemon-reload
systemctl restart "$U"
ls /srv/backup-configs        # retrigger do automount
```

**Também corrigido:** `/srv/backup-gitrepos` do **ybyra** e do **ybytu** (estavam `hard`).
Depois: backup OK + `push ybyra ok`.

> ⚠️ **Lição:** `x-systemd.automount` pode ficar **dead** após reboot **sem o mount parecer
> quebrado** (segue servindo um estado velho). A falha só aparece quando o *file handle*
> expira — **dias** depois. Um mount `hard` onde deveria haver `soft` é o **sinal** de que o
> automount recriou com opções antigas. Checagem rápida:
> `findmnt -rn -t nfs4 -o OPTIONS | grep -c hard` (esperado: **0**).
> Verificado na frota em 08/10/2026: **0** em ybyra, ybytu, kuaray e kavure.

## Segurança

- `--delete-excluded`: espelho fica EXATO (não acumula lixo/segredos). Risco limitado ao espelho (protegido por snapper + refeito da fonte toda noite).
- Fontes dos hosts são **apenas lidas**; o script nunca escreve/apaga nos hosts.
- `-x` impede cruzar mounts NFS (evita varrer 62G de offbox — lição do kavure).
