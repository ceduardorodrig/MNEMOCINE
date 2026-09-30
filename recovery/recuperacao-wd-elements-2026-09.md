---
tags: [homelab, recovery, storage, hardware, usb, kernel, psicopompo, handoff]
---

# Recuperação — WD Elements SE 1TB (MORIBUNDO) — set/2026

> **Status:** ⏸ **PAUSADO** — parada programada em 30/09/2026 01:50 (iniciado 29/09/2026)
> **Onde parou:** mapa `fase1a_700-1000.map` com **218,61 GB pendentes** (parede ≈ 820,86 GB)
> → procedimento de **retomada em §8.1** (nenhum processo rodando, nada a perder)
> **Máquina:** psicopompo (CachyOS, kernel 7.2.8-1-cachyos-bore — boot no **LTS** pendente, ver §8.1)
> **Arquivos de trabalho:** `/mnt/HDD_SATA/recuperacao-elements/` (scratch — apagar no fim)
> **Tracking detalhado:** `RECUPERACAO_TRACKING_2026.md` no diretório acima
> **Destino dos arquivos recuperados:** `/mnt/SSHD/recuperacao/`

## 1. Contexto

Disco externo **WD Elements SE 1TB** (NTFS) com falha física progressiva. SMART: **FAILED**
("failure expected in <24h"), `Raw_Read_Error_Rate = 234718`, `Reallocated_Sector_Ct = 0`
(não realoca — apenas **trava** na leitura).

Recuperação iniciada originalmente na máquina **morfosear** e retomada no **psicopompo**
(handoff em `/home/edu/Downloads/HANDOFF_COMPLETO.md`).

## 2. Discos envolvidos (SEMPRE identificar por serial — as letras mudam!)

| Papel | Serial | Label | FS | Porta USB |
|---|---|---|---|---|
| **MORIBUNDO** | `WD-WX51A68876FE` | MORIBUNDO-WD-WX51A68876FE | NTFS | bus 2 / 2-2 (`usb-storage` BOT) |
| **RESGATE** | `WD-WXW1A976UPD4` | RESGATE | ext4 | bus 2 / 2-3 |
| **SSHD-1TB** | `0123456789ABCDEF` | SSHD-1TB | ext4 | bus 2 / 2-7 (`uas`) |
| HDD SATA (scratch) | `S1DFKB80` | HDD SATA | btrfs | SATA interno (`/mnt/HDD_SATA`) |

> As letras (`sdg`/`sdh`/`sdf`) **mudam a cada reboot/replug**. Sempre resolver por serial:
> `lsblk -dn -o NAME,SERIAL,SIZE`. No handoff era `sdb`/`sdc`; no psicopompo virou `sdg`/`sdd` e depois `sdg`/`sdh`.

## 3. Metodologia (image-first — zero desgaste desnecessário do disco doente)

1. **Imagem primeiro:** ddrescue → imagem sparse em disco saudável; depois PhotoRec **sobre a imagem**
   (o disco doente é lido uma única vez).
2. **Mapfiles sempre retomam** — nunca reiniciar trabalho. 3 sessões travadas no mesmo ponto →
   avançar 256 MB (perda aceita).
3. **Nunca** usar `-a` (auto-skip agressivo) neste disco: gerou 274 falsos *skips*.
4. **Regra de ouro:** sempre identificar discos por serial.

## 4. Mapa do terreno (medido 29/09/2026)

| Faixa | Estado | Velocidade |
|---|---|---|
| 0–3 GB | bom (boot + `$MFT` @ 3,0 GB, LCN 786432) | 67–93 MB/s |
| 4–32 GB | ruim episódico (medium error em 29,57 GB) | lento |
| 32–570 GB | bom (não re-testado a fundo) | — |
| 570–575 GB | bom, porém lento | 39–44 MB/s |
| **576–599 GB** | **PAREDE / ATOLEIRO** | ~0,26 GB/17 min |
| **600–1000 GB** | **bom** (às 17:00) | 88–91 MB/s |
| 625–700 GB | **morreu às 18:15** (travava 17 s/leitura) | ~0 |
| 668,96 GB | parede estreita (medium error) | — |

`rescue.map` do handoff: **658 GB resgatados, 0 setor marcado como erro, 341 GB nunca tentados** —
prova de que o disco **trava**, não rasga.

## 5. Achado-chave: o NTFS ABRE com nomes

`ntfsls -f -l /dev/<MORIBUNDO>1` funciona (volume marcado DIRTY → exige `-f`):

```
ANNA/  Aniversario Aurora 2022/  Documentos/  Downloads/  Imagens/  JOBS/
Pedro Saliba/  Programas/  REBECA/  REF. DE ANTROVISUAL/  201202 - Cartao Camera/
IMG_1113.jpg  IMG_1120.jpg  IMG_1126.jpg  IMG_8587.CR2  _MG_8586.CR2
doc vivencia amazonica 2.0.mp4   1° corte Viv. Amaz. 2019.mp4
```

→ Recuperação **com nomes e pastas** é possível a partir da região do `$MFT` (3 GB).

## 6. ⚠️ LIMITE OPERACIONAL CRÍTICO: o disco CONGELA a máquina

### Sintoma
29/09 18:15 — o sistema travou por completo; só foi possível reiniciar **após desconectar os HDs USB**.

### Causa raiz — **bug de kernel** (não é só "excesso de resets")

```
BUG: kernel NULL pointer dereference, address: 00000000000001b8
#PF: supervisor write access in kernel mode
CPU: 1  Comm: usb-storage   Tainted: [O]=OOT_MODULE [E]=UNSIGNED_MODULE
RIP: 0010:scsi_complete+0x3f/0x270
Call Trace:
  usb_stor_control_thread+0x262/0x2d0 [usb_storage]
  kthread+0xe4/0x120 → ret_from_fork
Hardware: Dell Precision 3630 Tower · kernel 7.2.8-1-cachyos-bore
```

O disco falho entra em **tempestade de erros/resets**; a cada ~10–15 resets de USB o kernel
executa `scsi_complete()` e **desreferencia NULL** (oops). O oops deixa a pilha de armazenamento
inconsistente → **congelamento total**.

### Evidência (journalctl -b -1)
```
18:13:44  usb 2-2: reset SuperSpeed USB device number 3 using xhci_hcd
18:14:20  usb 2-2: reset SuperSpeed USB device number 3 using xhci_hcd
18:14:57  usb 2-2: reset SuperSpeed USB device number 3 using xhci_hcd
18:15:16  dd ... skip=667572          ← sonda em 700 GB
18:15:27  [última linha do journal]   ← congelou
```

### Proteções aplicadas (29/09 18:35 — **ativas**)

| # | Proteção | Implementação |
|---|---|---|
| 1 | **SysRq habilitado** (`kernel.sysrq = 1`) | `/etc/sysctl.d/99-homelab-sysrq.conf` |
| 2 | **Watchdog de hardware** | `RuntimeWatchdogSec=30s` em `/etc/systemd/system.conf` → `intel_oc_wdt` **active** |
| 3 | **`reset-guard.sh` (v6)** | vigia o journal **permanentemente**; 1ª tempestade (**3 resets/45 s**) → `SIGINT` + drenagem (sem unbind se o disco está presente); **2ª tempestade com I/O já parado** = disco travou → `unbind`+`bind`; **KILL em 12 s** se o `SIGINT` não derrubar o ddrescue (com backup do mapfile); reaplica `timeout=5` **a cada reset** |
| 4 | **SCSI timeout = 5 s** | `/sys/block/sdX/device/timeout` (não persistente — reaplicar após reboot) |

**Efeito:** no pior caso a máquina **reinicia sozinha em ~30 s** em vez de congelar para sempre,
e a recuperação **retoma do mapfile** sem perder nada.

**Rollback (1 linha cada):**
```bash
rm /etc/sysctl.d/99-homelab-sysrq.conf
sudo cp /etc/systemd/system.conf.bak-pre-watchdog /etc/systemd/system.conf
sudo systemctl daemon-reexec
```

### Duas quedas reais (30/09) — o que elas provaram

| | Crash n.º 1 (00:18:06) | Crash n.º 2 (00:57:03) |
|---|---|---|
| Guarda | **viva, NÃO disparou** (4 resets / limiar 5-90 s) | **disparou e encerrou** após a `PARADA` |
| I/O | corria normalmente | `SIGINT` não derrubou o ddrescue → 8 resets **sem vigia** (00:55:11–00:56:31) |
| Sequência | `offline` 00:17:08 → oops 00:18:06 (58 s) | `offline` 00:56:43 → oops 00:57:03 (20 s) |
| Reboot | watchdog 00:18:56 | watchdog 00:57:48 |

Assinatura idêntica nos dois: `Device offlined - not ready after error recovery` →
`BUG: kernel NULL pointer dereference, address: 00000000000001b8` em
`scsi_complete+0x3f/0x270` (a partir de `usb_stor_control_thread`) → watchdog reinicia.

- **Causa raiz = bug do kernel** no error recovery do `usb-storage` com este disco falhando
  (**crash n.º 1 aconteceu sem nenhuma intervenção nossa** — prova documental). O `unbind`
  nosso **não** é o gatilho.
- O que o bug da guarda (n.º 2) fez foi **perder a chance de conter**: sem vigia, a escalada
  seguiu até o `offline`. Corrigido na **v6** (guarda persistente, KILL, 2 estágios, `timeout=5`
  reaplicado) — **reduz a probabilidade, não zera** (a janela dos 3 primeiros resets fica).
- Evidência adicional do n.º 2: o `SIGINT` **não regravou o mapfile** (mtime ficou em 00:53) →
  por isso a v6 faz `cp` do mapa antes do KILL e a retomada prevê backup por sessão.

**Pendência abordada ao usuário (ainda não executada):** boot no **LTS** como aposta
complementar contra o bug do kernel + apertar o gatilho para **2/30 s**.

### O que **não** foi mexido (preservar otimizações CachyOS)
- `nowatchdog` do cmdline **intacto** (é o tweak real de performance — desliga NMI/lockup detectors).
- Nenhuma mudança em scheduler/BORE/OMD/governors/sysctl de performance.
- Decisão **pendente**: adotar o boot no **LTS** (`linux-cachyos-lts 6.18.52` já instalado;
  Limine 12.9.0 traz a entrada `linux-cachyos-lts` = `default_entry: 2`, `timeout: 5`,
  `remember_last_entry: yes`) — aposta contra o bug do kernel, **sem garantia**. Enquanto não
  se decide, segue o `bore` 7.2.8 (com as duas quedas já sobrevividas pelo watchdog).

### Documentação oficial consultada
- `systemd-system.conf(5)`: *"By default, RuntimeWatchdogSec= defaults to 0 (off)"*;
  *"The system manager will ensure to contact it **at least once in half the specified timeout interval**"*.
- systemd issues **#27427** (timeout não suportado → EINVAL silencioso → watchdog não arma) e
  **#5014** (salto de relógio para trás interrompe os pings).
- Fórum do Arch: relatos de `iTCO_wdt`/watchdogs Intel mal alimentados pelo systemd (aqui o journal
  confirma `Using hardware watchdog /dev/watchdog0: 'intel_oc_wdt'` e estabilidade).

## 7. Playbook — recuperação segura de disco USB moribundo no psicopompo

Ordem para **não congelar a máquina** e **não perder trabalho**:

1. **Isolar:** identificar por serial; manter o disco doente **desmontado** (leitura crua).
2. **Preparar proteções:** `sysrq=1`, watchdog via systemd (`RuntimeWatchdogSec=30s`),
   `reset-guard.sh` (corta a tempestade de resets), `timeout=5` no SCSI.
3. **Ler o mapa antigo antes de gastar o disco:** se existir um mapfile/log anterior, ele diz
   **o que já foi copiado**. Gastar a vida útil do disco relendo o que já está salvo é o pior erro.
4. **Imagem em DUAS PASSADAS** (best practice Rossmann/labs de recuperação):
   - **Passada 1:** `ddrescue -n` (sem *scrape*) — copia o fácil e **abandona rápido** o que trava;
   - **Passada 2:** volta só nas áreas ruins (`-r1`, sem `-n`).
   Sessões curtas com teto rígido (`timeout 120`), `-T60s`, `--skip-size`, `--sparse`.
   **Nunca `-a` agressivo** (gerou 274 falsos *skips* neste disco).
5. **Carvar sobre a imagem** com **loop device** (`--offset/--sizelimit`) para ler só onde há dado.
   PhotoRec: **nunca `everything,enable`** (gera ~185k falsos "dovecot" + 55k ".ts");
   usar lista curada de **famílias** válidas (ver §9 do tracking).
6. **Telemetria contínua:** `monitor-smart.sh` grava temperatura, erros e resets a cada 2 min.
   Métrica-chave: **`Current_Pending_Sector`** — se crescer, o disco está piorando.
7. **Inventário de referência:** `ntfsls -R -f -l /dev/sdX1` lê **só o `$MFT`** e lista todos os
   arquivos com nome e tamanho → permite responder "quanto de X GB foi salvo".
8. **Deduplicar** (`fdupes`) contra o que já estava recuperado.
9. **Limpeza obrigatória** do scratch ao final.

**Ferramentas avaliadas e descartadas:** HDDSuperClone/OpenSuperClone é a melhor para
**cabeça ruim**, mas seu `OSCDriver` só suporta kernel ≤ 6.18 (aqui é 7.2.8) e suas vantagens
(Direct AHCI) exigem SATA direto — o disco é USB com bridge. Fica como alternativa documentada.

Antes de qualquer passo: **pesquisar na documentação oficial** (Arch Wiki, systemd, CachyOS,
manual GNU ddrescue, cgsecurity).

### 7.1 Não apostar a recuperação no sistema de arquivos

O FS é a parte **mais frágil** de um disco moribundo: metadados muito requisitados e
concentrados. Neste caso, o `$MFT` do NTFS caiu justamente num ponto ruim (~3,24 GB) e o
`ntfsls -R` **parou de recursar** (listou 0 arquivos em `Imagens/` e `Documentos/` onde o
mount via 4.227 e 1.260).

**Regra:** a recuperação é feita em **nível de setor** (imagem + carving). O sistema de
arquivos só serve como **bônus oportunista** (nomes/estrutura), nunca como caminho principal.

### 7.2 Armadilhas operacionais (todas custaram tempo real)

| Armadilha | Sintoma | Correção |
|---|---|---|
| Rodar o runner sem root | `ddrescue: Permission denied`; o "avanço por travamento" consome o início da faixa | executar com `sudo` |
| Guarda com contador **cumulativo** | aborta a fase por desgaste acumulado em horas, não por surto | **janela de tempo** (5 resets/120 s) |
| `unbind`/`bind` do USB | **zera o SCSI `timeout`** (30 s) silenciosamente | reaplicar o timeout após cada replug |
| Telemetria SMART frequente | envia comando SCSI pelo bridge USB e pode gerar resets | no máximo a cada ~15 min |
| Abortar a fase na primeira zona hostil | perde horas de leitura boa | **fugir da zona e voltar depois** (passada 2) |
| `pkill -f <nome do script>` no próprio terminal | mata a **própria** sessão do agente (casa com a própria linha de comando) | matar por **PID** registrado em arquivo |

## 8. Progresso

### Resgatado
- **530 GB / ~71,8 mil arquivos** no disco **RESGATE** (ext4) — cópia única, não tocar.
- **27,85 GB** da cauda 600–630 GB na imagem (`cauda2.map`).
- **3,06 GB** em 0–3 GB (`meta.map`, inclui `$MFT` para nomes).
- **14,78 GB** em 584–599 GB (`cauda_a.map`) + **6,40 GB** em 570–576 GB (`cauda_b_576-584.map`).

### ⚠️ Descoberta que reorganizou o plano (29/09 19:00)

Analisando `legado/rescue-antigo.map` (do morfosear, 18–24/set):

```
*:      0,02 GB
+:    658,18 GB   ← 0–658 GB JÁ FORAM COPIADOS (com 0 erros, disco ainda saudável)
?:    341,97 GB   ← 658–1000 GB NUNCA TENTADO
```

**0–658 GB já está salvo** e o carving está no RESGATE. O prêmio real é
**658–1000 GB (342 GB virgens)**. Priorizar isso em vez de 0–570 GB multiplica o
rendimento por unidade de desgaste do disco que está morrendo.

### 📋 Inventário NTFS — o que EXISTIA no disco (29/09 19:20)

`ntfsls -R -f -l /dev/sdh1` — só lê o `$MFT`, levou **12,7 s** (área boa). 1 registro ilegível.

| Métrica | Valor |
|---|---|
| **Arquivos com conteúdo** | **2.009** |
| **Volume total de dados** | **64,29 GB** |
| Pastas | 271 |

| Tipo | Volume | Arquivos |
|---|---|---|
| `.mov` (vídeo Canon) | **40,63 GB** | 268 |
| `.cr2` (RAW Canon) | **13,81 GB** | 572 |
| `.jpg` | **5,14 GB** | 1.039 |
| `.mp4` | 4,10 GB | 42 |

Pastas principais: `0.Visual` (19,0 GB), `videos` (7,4 GB), `fotos` (6,1 GB),
`editadas jpeg` (3,3 GB), raiz (2,2 GB), `$RECYCLE.BIN` (2,9 GB).

> **Isto é o denominador do relatório final.** O disco de 1 TB tinha apenas ~64 GB de dados
> reais — o resto era espaço livre (por isso os 658 GB do rescue antigo eram majoritariamente
> zeros). A pergunta "recuperamos a maior parte?" agora tem resposta exata, por arquivo.

### ✅ Carve curado da cauda (570–631 GB) — concluído
141 arquivos / **31 GB**, só tipos reais (69 `mov`, 66 `mp4`, 4 `m2ts`, 1 `xml`, 1 `txt`).
Maiores: vídeos de até 1,15 GB. Comparado ao `everything,enable` (239 mil falsos-positivos),
a lista curada foi **~1.700× mais precisa**.

### ❗ Interpretação correta: *fog of war*, não degradação

Os "mapas de piora" comparavam **amostragens diferentes** de regiões diferentes, não o mesmo
ponto no tempo. O disco revela o dano **incrementalmente**, conforme lemos regiões novas.

Evidência de que **não** há degradação acelerada: `Current_Pending_Sector = 2342` em medições
consecutivas (19:09, 19:11) — estável.

**Regra adotada:** só comparar **a mesma métrica ao longo do tempo** (SMART). Comparar pontos
distintos do disco não mede degradação — mede apenas o quanto ainda não exploramos.

### Fases
- [x] Instalar ferramentas (`ddrescue testdisk photorec fdupes ntfs-3g foremost`)
- [x] Desbloquear o loop de retry do USB
- [x] Sondar o terreno
- [x] Imagem 600 GB → 630 GB (`cauda2.map`)
- [x] **Proteções anti-congelamento** (sysrq + watchdog + reset-guard)
- [x] **Sintaxe do PhotoRec decifrada** + lista curada de 79 famílias (`carve.sh`)
- [x] **Telemetria SMART** contínua (`monitor-smart.sh`)
- [x] 🔄 **Carve da cauda 570–631 GB** → `/mnt/SSHD/recuperacao/01_carve_cauda` — **OK: 141 arq / 31 GB**
- [x] **Carve 658–790 GB** → `02_carve_658-790` — **51 arq / 38 GB** (interrompido 00:15; última pasta pode estar truncada → **re-rodar**)
- [ ] 🔄 **Fase 1a — imagem 700 → 1000 GB** (2 passadas: `-n` + retry) — **pausada em 820,86 GB, pendente 218,61 GB**
- [ ] **Fase 5d — inventário NTFS** (`ntfsls -R -f -l`) para medir o que foi salvo
- [ ] Fase 1b/c — 630–658 GB e atoleiro 576–599 GB (já cobertos; baixa prioridade)
- [ ] Fase 4 — 0–570 GB (já coberto pelo rescue antigo; só se sobrar tempo)
- [ ] `fdupes` contra os 530 GB do RESGATE + organização para o cliente
- [ ] Relatório final + limpeza do scratch + fechamento deste doc

### 8.1 Retomada após a pausa (30/09/2026 01:50)

Nenhum processo rodando e **nada a perder** — o mapa é o único estado que importa.
Passos, na ordem:

1. **Identificar os 3 discos USB por serial** (as letras mudam a cada reboot/replug):
   `lsblk -dn -o NAME,SERIAL,SIZE,TRAN` → MORIBUNDO `WD-WX51A68876FE`,
   RESGATE `WD-WXW1A976UPD4`, SSHD `0123456789ABCDEF` (ignorar fantasmas de 0 B).
2. **Remontar**: `/mnt/SSHD` (rw) e `/mnt/RESGATE` (ro) — caem a cada reboot. Conferir se os
   carves `01_carve_cauda.*` e `02_carve_658-790.*` sobreviveram.
3. **`echo 5 > /sys/block/<sdX>/device/timeout`** (volta a 30 a cada reboot — e a cada reset).
4. **Relançar a fase 1a** (retoma do mapfile):

   ```bash
   cd /mnt/HDD_SATA/recuperacao-elements
   sudo bash -c 'setsid nohup env GUARDMAX=3 JANELA=45 SKIP_STORM=1000000000 REST=30 \
     bash supervisor.sh fase1a_700-1000.map 700 1000170586112 f1a >> supervisor-f1a.log 2>&1 < /dev/null &'
   bash monitor-smart.sh    # telemetria SMART (≤ 15 min entre leituras)
   ```

5. **Conferir a guarda v6** disparar e **sobreviver** a uma tempestade (não pode mais encerrar
   após a `PARADA`) e vigiar se o kernel ainda emite `Device offlined`.
6. **Decisões em aberto com o usuário**: boot no **LTS** · gatilho **2/30 s** · backup do
   mapfile após cada sessão · re-rodar o carve 02 · reescrever `pipeline.sh` (apagado por
   corrompido).

> Proteções persistentes seguem **ativas** (rollback no §6): `kernel.sysrq=1` e
> `RuntimeWatchdogSec=30s`.

### Telemetria (29/09 19:09)
```
/dev/sdh  resets=0  Raw_Read_Error_Rate=160284  Reallocated=0
          Load_Cycle=17568  Temp=51°C  Current_Pending_Sector=2342
```
Os **2342 setores pendentes** (~1,2 MB instáveis) são a métrica a vigiar: se crescer,
o disco está degradando mais rápido e a operação deve ser encurtada.

### Perdas aceitas
- 576–599 GB (atoleiro) e onde o ddrescue não passar. **Não reiniciar trabalho.**

## 9. Referências

- Tracking operacional: `/mnt/HDD_SATA/recuperacao-elements/RECUPERACAO_TRACKING_2026.md`
- Handoff original: `/home/edu/Downloads/HANDOFF_COMPLETO.md`
- Imagem: `/mnt/HDD_SATA/recuperacao-elements/moribundo.img` (scratch, apagar no fim)
- [`mnemocine/recovery/disaster-recovery.md`](disaster-recovery.md)
- [`mnemocine/backups/strategy.md`](../backups/strategy.md)
