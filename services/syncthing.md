---
tags: [homelab, service, syncthing, storage]
---

# Syncthing

Sincronização de arquivos entre dispositivos — mantém o vault Obsidian e outros dados sincronizados.

**Servidor:** Malha distribuída (psicopompo ↔ kuaray ↔ ybytu ↔ celulares)

## Instâncias

| Servidor | Tipo | Usuário | Pasta | Status |
|---|---|---|---|---|
| psicopompo | Nativo — systemd user unit `syncthing.service` (config em `~/.local/state/syncthing/config.xml`) | edu | folders abaixo | ✅ **ativo** (10/08) |
| kuaray | Container (`syncthing/syncthing`) | — | `/config/Sync/...` | ✅ ativo |

> **Ybytu removido (06/08/2026):** container + pastas do Syncthing deletados (não era necessário). Device Ybytu removido do config do psicopompo.

## Folders (07/08/2026)

| id | label | psicopompo | kuaray | Conteúdo |
|---|---|---|---|---|
| `default` | `default-folder-syncthing` | `/home/edu/Default Folder Syncthing/` (**sendreceive**, fonte) | `/home/kuaray/Default/` (container `/default`, **receiveonly**) | kdbx (KeePass), CNH, docs pessoais |
| `agentic-ai` | `agentic-ai` | `/mnt/NVME_PCI/agentic-ai/` | `/home/kuaray/agentic-ai/` (container `/agentic-ai`, **receiveonly**) | **Vault Obsidian + pasta de trabalho** |
| `backup` | `backup` | `/mnt/BACKUP/` (fonte, **sendreceive**) | `/mnt/storage/backup/` (**receiveonly**) | **Espelho frio do backup** — música, books, recovery, dumps |

> **Folder `default` (10/08/2026):** kuaray passou a ser **espelho receiveonly** do `default` do psicopompo (path movido de `/config/Sync/` → `/home/kuaray/Default/`, fora do config dir). Naming consistente nos dois hosts. Antes disso o `default` do kuaray era um folder **local-only** (não conectado ao psicopompo) e vazio.

> **Folder `music` removido (07/08):** a música NÃO é mais sincronizada para o kuaray — os serviços (Navidrome, Lidarr) leem via **NFS do psicopompo** (`/mnt/storage/data/media/music` = mount NFS). Ver [`network/nfs.md`](../network/nfs.md).

> **Labels padronizados** (06/08): iguais nos dois lados — `default-folder-syncthing`, `music`, `agentic-ai`.
>
> **Kuaray:** folder `agentic-ai` fica em `/DATA/AppData/agentic-ai/` (**SSD do sistema**, `/dev/sda2`) — fora de `/config/Sync` para evitar aninhamento com o folder `default`.

> **⚠️ Folder `agentic-ai` (crítico):** aponta para a **raiz da pasta de trabalho** (que é a vault Obsidian). Configuração especial:
> - `.stignore` na raiz exclui `.venv/`, caches, backups → não sincronizam.
> - **Espelho real + versioning (06/08):** `ignoreDelete=false` (deleções propagam — qualquer device pode deletar) + **`versioning` `simple`** (keep 5 no psicopompo / keep 3 no kuaray) → arquivos deletados vão para `.stversions/` local em vez de sumir. Protege contra "tempestade de deleção" de disco defeituoso.
> - **Aula 06/08:** sem `ignoreDelete`, o syncthing propagou deleções do kuaray e apagou arquivos do antigo repo git (recuperados via `git checkout`). Com versioning, deleções viram histórico recuperável.
> - `.obsidian`/`.pandoc` (config do Obsidian) sincronizam; `.smart-env`/`.SMART CHATS` (caches) são ignorados.

## Portas

| Porta | Protocolo | Função |
|---|---|---|
| `8384` | TCP | Interface web (apenas Tailscale) — **bind `127.0.0.1:8384` + exposta via `tailscale serve --tcp 8384`** (10/08) |
| `22000` | TCP/UDP | Transferência de dados |
| `21027` | UDP | Descoberta local |

## Acesso

Interface web (apenas na tailnet):
- **psicopompo:** `http://100.82.51.112:8384` (via `tailscale serve`, que faz proxy TCP → `127.0.0.1:8384`)
- **kuaray:** `http://100.94.209.99:8384`

## Histórico (06/08/2026)

1. **Fix IP:** `syncthing@edu` falhava no boot — `config.xml` apontava p/ IP antigo. Corrigido p/ `100.82.51.112`.
2. **Reorganização:** Default Folder movida p/ `/home/edu/Default Folder Syncthing/`; MUSIC p/ `/mnt/BACKUP/media/music/` (migração em andamento); Calibre Ingest deletada.
3. **Vault Obsidian:** migrada de `~/Syncthing/Default Folder/OBSIDIAN/Mnemocine` para a **raiz do agentic-ai** (vault = pasta inteira).
4. **Repos git consolidados:** `git [SUMAENIMA-INFRA]` e `git [CURRICULUM-VITAE]` incorporados à **pasta única agentic-ai** (removidos `.git` aninhados, backup em `.backup-git-nested/`). Pastas renomeadas para `mnemocine/` e `curriculum-vitae/` (06/08). **agentic-ai deixou de ser repo git** (07/08) — é pasta de trabalho/vault sincronizada via Syncthing. Repos originais continuam no GitHub.
5. **Folder id/label:** `obsidian` → **`agentic-ai`** (re-aceitar em todos os devices).
6. **Paridade kuaray:** folder `agentic-ai` movido de `/config/Sync/obsidian` (aninhado no default) → **`/DATA/AppData/agentic-ai/`** (SSD, fora do default). Lixo `obsidian` (3.2G, cópia duplicada) removido do Default Folder do psicopompo. **Labels padronizados** nos dois lados. Ocultos `.obsidian`/`.pandoc` re-sincronizados.
7. **Encoding:** 3 nomes de arquivo NFD→NFC (git via `git checkout`); `core.precomposeunicode=true`.
8. **Crise HDD kuaray (06/08):** folder `music` do kuaray dava `Bad message` — causa raiz foi **double-mount** do `/dev/sdb` (loop0 stale + loop100, ambos rw) que corrompeu o ext4. Folder `music` **removido** do kuaray (mídia consolidada no psicopompo). Device Ybyra órfão removido do config do psicopompo. Ver `servers/kuaray.md`. Detalhe: no kuaray, `ignoreDelete=true` também aplicado no folder `agentic-ai`.
9. **Restauração música (06/08, noite):** HDD reformatado (MBR/LBA2048, fs saudável — `mnt-storage.service` removido). Folder `music` (`gtuwj-mspep`) **recriado** no syncthing do kuaray → `/mnt/storage/data/media/music`. Prompt "adicionar pasta música" resolvido.
10. **Storm de deleção (06/08, noite):** recriar o folder `music` do kuaray **vazio** fez o índice do kuaray reportar a biblioteca como deletada → psicopompo (espelho) começou a aplicar deleções. **Perdeu ~18 arquivos reais (~465MB)** antes dos erros "directory not empty" protegerem; restaurados de `/mnt/HDD_SATA/Music` (fonte original intacta). **Solução aplicada:** folder `music` do kuaray → **`receiveonly`** (espelho recebe tudo, mas nunca envia estado → um HD defeituoso/folder recriado não consegue disparar storm). Aplicável até migrar o Lidarr/arr-stack do kuaray. Lixo `.syncthing.*.tmp` (445) removido do HDD_SATA.

## Histórico (07/08/2026) — "tudo 100%"

1. **Limpeza de tombstones `agentic-ai`:** os folders `.venv`/`.smart-env` (ignorados) tinham tombstones de deleção registrados pelo kuaray em 06/08 → o syncthing local recusava deletá-los (contêm arquivos ignorados) → **2 erros + completion 95%** no psicopompo (e 95% nos celulares). **Solução:** folder `agentic-ai` **removido e recriado** (mesma config) no kuaray e no psicopompo via API → índice re-scaneado, tombstones sumiram. Resultado: **100% em todos os devices** (psicopompo, kuaray, Pira-Nuya, Anansi), 0 erros, caches preservados.
2. **`.stignore` kuaray limpo:** removidas refs da era git (`.git/`, `.gitignore`, `.backup-*`) e adicionados padrões de segurança (`.env`, `*.key`, `*.pem`, `*.cert`, `secrets/`) + lixo de SO/editor.
3. **Fix `.env.template`:** no Syncthing vale "1ª regra que casa decide" — `!.env.template` tinha que vir **antes** de `.env.*`. Corrigida a ordem no `.stignore` de ambos (comentário explicativo incluído).
4. **Música kuaray — espelho exato ABANDONADO:** o resgate do disco deixou ~975 itens "receive only changed" (duplicatas da biblioteca antiga) → completion 92,5%. Backup dos 582 arquivos reais (19G, depois removido — conteúdo confirmado duplicado no source) + `db/override` → reverteu parcialmente, mas o disco recuperado tem **versões diferentes do source em ~5500 itens** → forçar espelho exato exigiria baixar **~134 GiB** de volta. **Decisão (07/08):** transferência inviável no HD moribundo → folder `music` **removido** (ver item 5). kuaray = pihole "glorificado".
5. **Nova arquitetura (07/08) — psicopompo = NAS + backup frio via Syncthing:**
   - **Folder `music` removido** do syncthing (psicopompo + kuaray). HD do kuaray limpo (lixo divergente apagado, 864G livres).
   - **NFS:** psicopompo exporta `/mnt/BACKUP/media/music` e `/media/books` (NFSv4, `all_squash,anonuid=1000`); kuaray monta em `/mnt/storage/data/media/music` (mesmo caminho dos binds dos containers) → Navidrome/Lidarr lêem a biblioteca do psicopompo **sem sync**. Ver [`network/nfs.md`](../network/nfs.md).
   - **Folder `backup` (frio):** `/mnt/BACKUP` inteiro (fonte, sendreceive) → `/mnt/storage/backup` no kuaray (**receiveonly**, **sem versioning** — decisão: espelho simples; disco moribundo + 2 cópias já existem no psicopompo). Primeira transferência ~179G em background; depois incremental. `.stignore` do backup exclui `.syncthing.*.tmp`/lixo.
   - **Fix permissão (07/08):** o daemon do syncthing do kuaray roda como **`kuaray` (uid 1000)** (container `linuxserver/syncthing`, PUID=1000) — não como root. A pasta `/mnt/storage/backup` (criada via `docker exec` como root) impedia a escrita → **`chown -R kuaray:kuaray /mnt/storage/backup`** (mesmo dono de `/mnt/storage/data`). Transferência então iniciou normalmente.

## Cluster (09/08/2026)
- **kuaray device ID (novo):** `MYBTGZG-W6AMRCA-CRBXOVE-OLBIUCS-4MED42G-LDDYJ7D-6MTMAPI-Y4GV6AO` (identidade antiga `XC3YRZ6-...` perdida 08/08).
- Re-pareado 09/08 via API: kuaray = **receiveonly** em `backup` (/mnt/storage/backup) e `agentic-ai` (/home/kuaray/agentic-ai).
- psicopompo (master) removeu o device antigo e adicionou o novo.

## Histórico (10/08/2026) — erros do watcher/scan resolvidos

1. **Erro no psicopompo — `backup` (fonte):** watcher + rescan falhavam em `/mnt/BACKUP/.snapshots` (`permission denied`) — o `.snapshots` é o **subvol de snapshots do snapper** (`root:root`, `drwxr-x---`). **Solução:** adicionado ao `/mnt/BACKUP/.stignore` os padrões `(?d).snapshots` e `(?d).Trash-*/`. A doc de ignoring do Syncthing confirma: padrão sem `!` (negação) faz o scan E o watcher **pular** o diretório. Após o edit: 0 erros novos, folder `backup` em `idle` (152774/152774).
2. **Erro no kuaray — `backup` (receiveonly):** "Failed to sync 12 items / directory not empty" — o `.Trash-1000` local (23G, lixo da recuperação do HDD 06/08) divergia do global (`.Trash-1000` do psicopompo vazio); receiveonly preserva arquivos locais → não conseguia deletar. **Solução:** removidos manualmente `/mnt/storage/backup/.Trash-1000` (23G liberados) e `/mnt/storage/backup/.snapshots` (leftover) → folder `backup` em `idle`, `needFiles=0`.
3. **Folder `default` — consistência:** kuaray não tinha o `default` conectado ao psicopompo (era local-only em `/config/Sync`, dentro do config dir — prática ruim). Reconectado via API: path `/home/kuaray/Default` (volume novo no compose), **receiveonly**, device psicopompo adicionado (e vice-versa). `ignorePerms=true` alinhado com o master. **Label corrigido (10/08):** `Default Folder` → `default-folder-syncthing` (igual ao psicopompo).
4. **`ignorePerms`:** kuaray agora `true` nos 3 folders (padrão = psicopompo).
5. **Tailscale SSH:** `ssh kuaray` (via Tailscale SSH) pediu o "additional check" do dono (re-verificação periódica) — aprovado pelo owner; sem mudança de config.
6. **Local Additions no `backup` do kuaray (10/08):** o mirror mostrava 5 "local additions" em `sumaenima-server-kavure/sumaenima_borg/` — 2 `*.sync-conflict-*-KSNJAZU` (conflitos do período sendreceive) + 3 versões obsoletas do repo Borg (`hints.9`/`index.9`/`integrity.9`; o master está em `.17`). Removidos manualmente (folder receiveonly, sem borg ativo no kuaray) → `local = global` (153030/153030).
7. **`.stignore` no mirror kuaray (10/08):** criado `/mnt/storage/backup/.stignore` com os mesmos padrões do master (`(?d).snapshots`, `(?d).Trash-*/`, temp, lixo de SO) — boa prática: mirror receiveonly honra os mesmos ignores. Pendência de `receiveOnlyChangedDeletes=1` (item `.snapshots`) resolvida com **Revert Local Changes** (`POST /db/revert`) → `receiveOnlyChanged = 0/0/0`.

## Histórico (10/08/2026, noite) — boot race do GUI + fix definitivo

**Sintoma:** após o reboot de ~15:46, o `syncthing.service` (user) ficou **morto** (`start-limit-hit`) e o vault não sincronizava mais do psicopompo.

**Causa raiz:** o GUI estava fixo em **`100.82.51.112:8384`** (IP Tailscale). O syncthing subiu 4s após o tailscaled, antes do IP TS ser atribuído → `bind: cannot assign requested address` → 4 tentativas em 60s → `start-limit-hit`. **Mesma classe de bug de 06/08** ("IP antigo") — hardcodar bind em IP da tailnet é frágil no boot.

**Fix aplicado (Opção A — localhost + Tailscale Serve):**
1. GUI → **`127.0.0.1:8384`** no `config.xml` (não depende mais do IP TS no boot).
2. **`tailscale serve --bg --tcp 8384 tcp://127.0.0.1:8384`** → o tailscaled (dono do IP TS) expõe `http://100.82.51.112:8384` na tailnet; persiste entre reboots (estado do serve fica no tailscaled).
3. **Host check do GUI** (`Host check error` 403 ao acessar via `100.82.51.112`): na **v2.1.3** o campo é **elemento-filho** `<insecureSkipHostcheck>true</insecureSkipHostcheck>` dentro de `<gui>` (atributo XML é **ignorado**). Setado via `POST /rest/system/config` (PUT dá 405).
4. `systemctl --user reset-failed syncthing.service` + start.

**Validação:** restart preserva o setting (runtime `insecureSkipHostcheck=true`), GUI 200 via `100.82.51.112:8384` e via MagicDNS, serve ativo, folders `agentic-ai`/`backup`/`default` em sync (`need=0`).

> **Lição:** serviço com GUI "apenas tailnet" **não** deve dar bind no IP TS — usar `127.0.0.1` + `tailscale serve` (ou firewall). Reboot-safe.

## Histórico (28/08/2026) — HDD não montou no boot → folder `backup` em erro

**Sintoma:** folder `backup` do kuaray em estado **erro "folder path missing"** (o "stopped" na GUI).

**Causa raiz:** após reboot (kernel 7.0.0-30), o HDD `/dev/sdb1` **não montou** — `systemd-fsck` falhou (dependency) → `mnt-storage.mount` `dead`. O disco degradou além do documentado: **`Current_Pending_Sector` 3 → 37**, **novo erro de leitura em ~464 GB** (sector 973545360, dmesg) e o `e2fsck -fn` reportava **erros no filesystem** (inode 7 / group descriptors, "Illegal block"). O fsck de boot bateu nos setores ruins e abortou o mount. Sem o mount, o caminho `/mnt/storage/backup` não existia → erro no folder.

**Efeito colateral:** o mount NFS de música (`/mnt/storage/data/media/music`) ficava **aninhado sob o mountpoint do HDD** → também caiu → **Lidarr sem biblioteca** (música segura no NAS, mas caminho local sumiu).

**Resolução (28/08):**
1. `e2fsck -fy /dev/sdb1` — reparado (diretórios, bitmaps, contadores, inodes órfãos). Não bateu de novo no setor ruim (~464 GB parece estar fora da região usada).
2. `/etc/fstab`: `/mnt/storage` com **`nofail,errors=continue`** (boot não trava com disco doente). Backup em `/etc/fstab.bak-20260828`.
3. `mount /mnt/storage` → mirror `backup/` + `data/` acessíveis.
4. **`docker restart syncthing`** — o bind `/mnt/storage:/mnt/storage` foi criado antes do HDD montar e apontava para a pasta vazia do SSD (mesma regra `rprivate` da `nfs.md:69`); sem o restart o container não via o mount.
5. Scan + **`POST /rest/db/revert?folder=backup`** — o e2fsck deixou **2334 itens "receive only changed"**; revert alinhou o mirror com o master. Folder `backup` → **`idle`, local = global = 155628**.
6. **NFS de música desacoplado do HDD** (ver [`network/nfs.md`](../network/nfs.md)): mount movido para `/mnt/nas/media/music`; bind do Lidarr ajustado. HDD nunca mais derruba a biblioteca.

> **Estado (28/08):** folders `agentic-ai` (1482) e `default` (4) **idle**; `backup` **idle** (155628/155628). Disco segue degradado (37 pending) — recomendação de troca do HDD mantida (`servers/kuaray.md`).

## Histórico (22/09/2026) — conflito de unidades (duplicação de 06/08) + 40 erros do repo restic

**Sintomas:**
1. `syncthing.service` (user) terminava o boot em **`start-limit-hit`** ("is another Syncthing instance already running") — a `syncthing@edu.service` (system) ganhava a corrida do lock.
2. Folder `backup` com **40 `pullErrors`** por boot: `permission denied` em `/mnt/BACKUP/repos/restic/configs/data/*`.

**Causas raiz:**
1. **Unidades duplicadas:** a `syncthing@edu` (system) foi habilitada em **06/08 15:00** (symlink criado naquele dia) durante o "Fix IP" (histórico 06/08) — junto com a user canônica (preset padrão desde 28/05) → corrida em todo boot. A doc contradizia a si mesma (seção Instâncias declara a **user** como canônica).
2. **Repo restic dentro do folder `backup`:** o timer do restic (05:45) cria packs como **`root:root` modo 400** — o syncthing (edu) não lê → falha de scan/hash (40 erros neste boot; 321 via instância system antes de desabilitar).

**Fix:**
1. `sudo systemctl disable --now syncthing@edu` — remove a duplicação de 06/08.
2. `systemctl --user reset-failed syncthing` + `start` — user unit canônica assume.
3. `/mnt/BACKUP/.stignore` += **`repos/restic/`** — scan/watcher pulam (mesma receita do `(?d).snapshots` de 10/08; o `.stignore` precisa de folder restart/novo scan p/ recarregar).

**Validação (22/09):** `syncthing.service` (user) **active+enabled**; `syncthing@edu` **disabled**; folders `backup`/`agentic-ai`/`default` **`idle`, `need=0`, `errors=0`**, zero `permission denied` após o fix (scan de controle 12:29+).

> **Lições:** (1) o Arch oferece user unit E system template — habilitar as duas = corrida de lock em todo boot; manter só a canônica declarada na doc. (2) repos com permissão root-only (restic/git) dentro de um folder syncthing devem ir para `.stignore` — o syncthing nunca deve escanear conteúdo que não pode ler (o `.stignore` é recarregado no restart do folder/serviço, não em scan quente).
