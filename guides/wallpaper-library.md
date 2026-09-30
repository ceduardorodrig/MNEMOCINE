---
tags: [homelab, tutorial, psicopompo, wallpaper, gpu, nvidia]
created: 2026-09-27
updated: 2026-09-27
---

# Acervo de Wallpapers — Organização e Upscale (psicopompo)

Playbook do acervo de wallpapers do `psicopompo`: como classificar por resolução e
orientação, como upscalar os que não chegam a 4K, e — principalmente — as
**armadilhas** que custaram tempo nas duas primeiras execuções (27/09/2026).

**Local:** `/home/edu/Pictures/PAREDEDEPAPEL/`
**Script do vault:** [`scripts/wallpaper-pipeline.sh`](../scripts/wallpaper-pipeline.sh)
**Ferramentas arquivadas:** [`scripts/archive/wallpaper-postprocess.py`](../../scripts/archive/wallpaper-postprocess.py),
[`scripts/archive/wallpaper-flat-lanczos.py`](../../scripts/archive/wallpaper-flat-lanczos.py)

> ℹ️ **Backup:** o acervo **está** coberto pela rotina canônica (`config-backup` → NAS,
> + snapper + restic + Google Drive). Ver [Backup do acervo](#backup-do-acervo).

> ⚠️ **A regra que mais importa:** use o modelo na **escala nativa** (`-s 4` para
> `realesrgan-x4plus`). `-s 2` com modelo x4 destrói a imagem — ver armadilha 1.

---

## Estrutura canônica

```
PAREDEDEPAPEL/
├── wallpaper-pc/               # >=4K exibindo horizontal ou quadrado  (monitor)
├── wallpaper-celular-tablet/   # >=4K exibindo vertical                (phone/tablet)
└── menores-4k/                 # <4K — fila de upscale (temporária)
```

Regra de ouro: **duas pastas de consumo + uma fila**. A raiz nunca guarda imagem solta.

## Regras de classificação

**Critério 4K** (decidido com o dono): `largura >= 3840 E altura >= 2160` (UHD).
Uma imagem `5120x2880` conta como 4K; uma `3840x1920` **não** (altura < 2160).

**Orientação:** pela dimensão **de exibição**, nunca pela crua (ver armadilha 2).
`largura >= altura` → PC (quadradas ficam no PC: servem bem em monitor).
`altura > largura` → celular/tablet.

---

## ⚠️ Armadilhas (todas confirmadas em produção)

Ordenadas por gravidade. A **1** é a que estragou um lote inteiro de 168 imagens.

### 1. `-s 2` com modelo x4 — o upscaler CORROMPE a imagem 🔴

**O bug mais grave.** `realesrgan-x4plus` é um modelo **x4**. Passar `-s 2` faz o
programa rodar o modelo em x4 e **reduzir internamente** para x2 — e o alinhamento
dos tiles com a grade de downscale quebra.

Sintoma visual: a imagem parece **cortada em quadrados e recolada em ordem levemente
aleatória**, como se estivesse atrás de um vidro texturizado.

Diagnóstico objetivo (autocorrelação do perfil de gradiente na horizontal):

```
-t 200 (default): pico em 400px = +0.809    ← assinatura do tile 200 x escala 2
                  pico em 800px = +0.665    ← e seus harmônicos
```

É uma série **positiva e monotonicamente decrescente** nos múltiplos do tile. Isso é
a impressão digital do defeito.

**Correção:** usar a escala nativa do modelo e reduzir depois, se necessário.

```bash
# CERTO — escala nativa, sem downscale interno
realesrgan-ncnn-vulkan -i in/ -o out/ -s 4 -n realesrgan-x4plus -f jpg

# ERRADO — quebra o alinhamento dos tiles
realesrgan-ncnn-vulkan -i in/ -o out/ -s 2 -n realesrgan-x4plus -f jpg
```

Medição no x4 nativo: **sem** pico em 800px. O defeito desaparece.

> **Lição de validação (custou um quase-descarte):** o pico em múltiplo do tile
> **nem sempre** é defeito — pode ser **conteúdo da própria imagem**. O
> `tanguy-sauvin` tem conteúdo periódico em 200px (+0.533), que em x4 aparece em
> 800px. Duas formas de separar:
> 1. Comparar com o pico do original na escala correspondente (conteúdo acompanha).
> 2. **Teste decisivo:** reprocessar com outro `-t`. Se o pico **muda de lugar**
>    (800 → 2048 com `-t 512`), é artefato. Se fica parado, é conteúdo.

### 2. EXIF orientation — a dimensão crua mente

PIL, `identify` e navegadores reportam as dimensões **cruas** do arquivo. Mas JPEGs
podem ter a tag EXIF `0x0112` dizendo "gire 90° para exibir".

Na primeira passada, 26 imagens foram classificadas pelo cru: 16 foram para a fila de
upscale e 10 para a pasta de celular — **todas eram paisagem**.

| Tag | Nome ImageMagick | Significado |
|---|---|---|
| 1 | `TopLeft` | normal |
| 3 | `BottomRight` | girar 180° |
| 6 | `RightTop` | girar 90° horário (troca L×A) |
| 8 | `LeftBottom` | girar 90° anti-horário (troca L×A) |

```bash
o=$(identify -format '%[orientation]' "$f")
case "$o" in RightTop|LeftBottom) read w h < <(echo "$h $w");; esac
```

Efeito colateral: 12 imagens foram parar na fila de upscale sem precisar — a
dimensão **de exibição** delas já era ≥4K. O x4 nelas daria `18720x8640`.

### 3. O upscaler descarta o EXIF

`realesrgan-ncnn-vulkan` processa pixels crus e **não copia metadados**:

```
IN : 2160x4680  orient=6   (exibe 4680x2160 paisagem)
OUT: 4320x9360  orient=1   (sem EXIF -> exibe 4320x9360 RETRATO)
```

Solução: `normalize --apply` **antes** do upscale (grava a rotação no pixel e zera a
tag), ou na saída depois. `normalize` é **idempotente** (`magick -auto-orient` zera a
tag, então rodar duas vezes não gira de novo).

> ⚠️ **Se rotacionar o pixel na mão, zere a tag na mesma operação.** Salvar os pixels
> girados mantendo `orientation=3/6/8` faz o visualizador girar de novo. Dimensão
> **não** detecta isso quando a rotação é de 180° (L×A não muda) — conferir a tag
> explicitamente. Formas seguras: `magick -auto-orient`, ou rotacionar + 
> `exiv2 -M"set Exif.Image.Orientation 1"`.

**Nunca confie na direção sem conferir.** Verificação barata: comparar a dimensão do
arquivo rotacionado com `ImageOps.exif_transpose` da entrada × fator de escala.

### 4. Imagens chapadas — a IA inventa textura 🟠

Em desenho liso (logo, arte vetorial, wallpaper retrô), **os dois modelos de IA
inventam textura que não existe**. Medido nas `Windows 3 (n).png`:

| Modelo | Tamanho | PSNR vs original |
|---|---|---|
| `realesrgan-x4plus` (foto) | **102 MB** | 18,3 dB |
| `realesrgan-x4plus-anime` | **90 MB** | 14,5 dB |
| **Lanczos 400%** | **3,3 MB** | **32,3 dB** |

E no `Windows 98.png` (1920x1080 que pesa 0,4 KB — quase chapado) o modelo de foto
ainda produz **artefato de tile confirmado**; o anime resolve, e o Lanczos reproduz
perfeito (PSNR 99, ~0 MB).

**Critério objetivo para separar (não é julgamento de conteúdo):**
`bytes do arquivo / pixels totais < 0.02`. Nas 156 da fila a **mediana era 0,19 B/px**;
o set chapado ficava abaixo de 0,02.

Para esse set, usar **Lanczos**, não IA:

```bash
magick original.png -filter Lanczos -resize 400% saida.png
```

Resultado: **0,62 GB → 22 MB** nas 14 imagens, com fidelidade **muito maior**.
Se o Lanczos precisar de teto, aplicar a mesma regra de 8192.

> **Suspeita da causa raiz:** esses wallpapers retrô usam **dithering** (padrão xadrez
> de 1px para simular cor). A IA lê o xadrez como textura real e "amplia" —
> produzindo dezenas de MB de ruído onde havia um padrão regular.

### 5. `-t` acima de 512 dá SEGFAULT 🔴

```
-t 1024  → Segmentation fault (core dumped)
-t 2048  → Segmentation fault (core dumped)
-t 3840  → Segmentation fault (core dumped)
```

Só o default (200) e `512` funcionam. **Aumentar o tile não é caminho** para reduzir
seam nesta build (0.2.5.0, binário de 2022). Reproduzido em duas imagens diferentes.

### 6. O default do upscaler não preserva a extensão

O default é `-f ext/png`, que na prática **converte todo `.jpg` em `.png`** — um
wallpaper 4K em PNG passa de **12 MB** (contra ~3,8 MB em JPEG). Verificado: JPEG na
saída é escrito com `stbi_write_jpg(..., 100)`, ou seja qualidade 100.

Solução: **um lote por extensão**, com `-f jpg` nos JPEG (o script usa hardlinks por
extensão, custo de espaço ~0).

### 7. ICC não sobrevive à IA

O upscaler descarta o perfil ICC. **~74% dos originais têm perfil embutido**
(298/400 medidos). Sem repor, imagens em Adobe RGB ou Display P3 são interpretadas
como sRGB e **a cor desvia** — e isso passa em qualquer validação de dimensão.

ImageMagick preserva ICC por padrão (verificado: `8bim,exif,icc,xmp` sobrevive a
`-auto-orient` + `-resize` + encode). Em PIL, é preciso passar `icc_profile=`
explicitamente.

### 8. VRAM: 2 workers é o teto (RTX 5050, 8 GB)

Cada instância consome ~2,3–3 GB. Três simultâneas estouram:

```
vkAllocateMemory failed -2      # Vulkan sem memória — um worker derruba os outros
```

Com 2 workers: ~6,2 GB usados, ~1,9 GB livres, GPU 100%, 76–81 °C. Estável.

### 9. `pgrep`/`pkill -f` casam com o próprio shell 🟠

Armadilha de **supervisores**, não do upscaler — mas derrubou o rebalanceamento.

Um shell que rodou um heredoc contendo `in-png/` **ficou vivo**, e o
`while pgrep -f "... -i in-png/"` passou a casar com ele **para sempre** — loop
infinito. O `pkill -f "run.sh"` também se auto-matou, porque o comando do próprio
agente continha a string.

**Regras:**
- Supervisores esperam por **estado observável** (contagem de arquivos), não por
  `pgrep`.
- Para matar, usar **PID** quando possível; se usar padrão, **ancorar** (`^`) e
  escrever o padrão de forma que não case consigo (ex.: `finalize[-]shell`).
- `pgrep`/`pkill` **não** excluem o shell que os invoca quando o padrão aparece na
  linha de comando desse shell.

---

## Ferramenta de upscale

**AUR:** `realesrgan-ncnn-vulkan-bin` (binário oficial da Tencent ARC Lab).
Não existe em `core`/`extra`/`multilib`/`cachyos-*` — só no AUR.

Verificação de segurança feita antes de instalar (27/09/2026):

| Checagem | Resultado |
|---|---|
| `sha256sums` do PKGBUILD vs. release oficial | **bateu** |
| Funções do PKGBUILD | só `package()`, sem `prepare`/`build` |
| Arquivo `.install` / hooks | ausente |
| `eval`/`curl`/`wget`/`bash -c` no PKGBUILD | nenhum |
| ClamAV no zip | limpo |
| Dependências | `vulkan-icd-loader` + `gcc-libs` (já presentes) |

```bash
yay -S realesrgan-ncnn-vulkan-bin
```

O motor é C++/ncnn — **não existe upscaler "em Rust" equivalente**. O `resup`
(crates.io) é Rust mas é wrapper de 1 arquivo por vez, 7 ⭐, parado desde 03/2024.
O `Upscayl` (GUI) é Rust/Tauri por fora e usa este mesmo binário por dentro; travou
no psicopompo.

### Flags que importam

```bash
realesrgan-ncnn-vulkan -i <dir> -o <dir> -s 4 -n realesrgan-x4plus -f jpg
```

- `-s` escala: **use a nativa do modelo** (`4` para `x4plus`/`x4plus-anime`).
  Só o `realesr-animevideov3` tem `-x2` nativo.
- `-n` modelo: `realesrgan-x4plus` (foto/arte com detalhe) ·
  `realesrgan-x4plus-anime` (anime/line art) · `realesrnet-x4plus` (mais suave)
- `-f` formato — **omitir converte tudo para PNG**
- `-t` tile: **2022 default ou 512 no máximo** — acima disso, segfault
- `-j load:proc:save` — default `1:2:2` é seguro

### Benchmarks (RTX 5050, 8 GB, `-s 4 -n realesrgan-x4plus`)

| Entrada | Saída (x4) | Sozinho | Com 2 workers |
|---|---|---|---|
| 1920x1200 (2,3 MP) | 7680x4800 | ~22 s | ~45 s |
| 3110x2074 (6,4 MP) | 12440x8296 | ~40 s | ~80 s |
| 3500x6000 (21 MP) | 14000x24000 | ~1 m 40 s | — |

Lote de 156 em 2 workers: **~1 h 15** (com warm-up de ~4 min na primeira).
O pós-processamento em CPU (rotação + teto + encode): **~8 min** no total.

---

## Validação (o que checar antes de aceitar uma saída)

| # | Checagem | Como |
|---|---|---|
| 1 | Dimensão do x4 == **exatamente 4×** o original cru | comparar `im.size` |
| 2 | Decodificação completa (`im.load()`, não só `verify()`) | pega truncado |
| 3 | ≥4K depois do teto | `w>=3840 and h>=2160` |
| 4 | PSNR da saída reduzida vs original | **≥15 dB**; <15 = preto/truncado. Gap: 20% preto = ~10 dB, saudável = 30–38 dB |
| 5 | Regiões pretas | células com desvio ~0 onde o original tinha textura |
| 6 | Assinatura de tile | série positiva **monotônica** em múltiplos de 800 **e** não explicada pelo conteúdo |
| 7 | ICC | presente quando o original tinha |
| 8 | Escrita atômica | `.tmp` + `os.replace` |

**PSNR não detecta seam** (bloco deslocado 200px dá 21–27 dB, sobrepondo o range
saudável). Para seam, só a autocorrelação serve.

---

## Procedimento replicável

```bash
S=/mnt/NVME_PCI/agentic-ai/mnemocine/scripts/wallpaper-pipeline.sh
B=~/Pictures/PAREDEDEPAPEL

"$S" report "$B"              # 0) inventário — não altera nada
"$S" normalize "$B" --apply   # 1) gravar rotação EXIF no pixel (ANTES do upscale)
"$S" organize "$B" --apply    # 2) mover para as 3 pastas
"$S" upscale "$B"             # 3) x4 nativo na fila menores-4k/ + teto 8192
"$S" organize "$B" --apply    # 4) reclassificar e limpar a área de trabalho
```

`report`, `normalize` e `organize` são **dry-run por padrão** — só mudam algo com
`--apply`.

Para o set chapado, o `upscale` decide sozinho: **< 0,02 B/px → Lanczos**, resto → IA.

---

## Estado do acervo (27/09/2026)

| Etapa | `wallpaper-pc` | `wallpaper-celular-tablet` | `menores-4k` | Total |
|---|---|---|---|---|
| Raiz plana (ponto de partida) | — | — | — | 612 |
| Após triagem por resolução | 425 | 19 | 168 | 612 |
| Após 1ª rodada (bug `-s 2`) | 587 | 25 | 0 | 612 |
| **Após 2ª rodada (x4 nativo)** | **587** | **25** | **0** | **612** |

Tamanho do acervo: **3,8 GB** (era 2,1 GB antes do upscale).

### Números da execução final

| Medida | Valor |
|---|---|
| Imagens reprocessadas | **168** (156 upscale x4 + 12 só rotação) |
| Do set de upscale, com IA | **142** |
| Do set de upscale, com **Lanczos** (chapadas) | **14** |
| Tetadas em 8192 | 121 |
| Rotacionadas (EXIF) | 16 |
| Corrompidas | **0** |
| Abaixo de 4K | **0** |
| Dependência de EXIF ao final | **0** em 612 |
| Economia da troca IA→Lanczos nas chapadas | **0,69 GB** |
| Auditadas byte a byte contra o snapshot | 612 (433 idênticas + 179 alteradas, todas justificadas) |

---

## Backup do acervo

O acervo **está coberto** pela rotina canônica do homelab.

| Camada | Job / horário | Destino |
|---|---|---|
| Espelho no NAS | `config-backup` (05:00) | `/mnt/BACKUP/configs-homelab/psicopompo/PAREDEDEPAPEL/` |
| Anti-deleção | snapper config `backup` | `/mnt/BACKUP/.snapshots` |
| Histórico versionado | `restic-configs-backup` (05:40, 14d/8s/6m) | `/mnt/BACKUP/repos/restic/configs` |
| Off-site | `rclone-gdrive-backup` (06:30) | `gdrive:BACKUP MNEMOCINE` |

O acervo entra no `SRC_DIRS` do `/etc/config-backup.conf` (linha
`/home/edu/Pictures/PAREDEDEPAPEL`) e é **intencionalmente ignorado no git** do
`configs-homelab` — `.gitignore` linha 26 (`psicopompo/PAREDEDEPAPEL/`). Binários não
pertencem ao repositório de configs; o acervo fica coberto pelas outras camadas.

> ⚠️ **Armadilha de diagnóstico:** `fd` e `rg` respeitam `.gitignore` por padrão. Como
> o espelho é git-ignored, uma busca por ele simplesmente "não encontra":
> ```bash
> fd -t d -i PAREDEDEPAPEL /mnt/BACKUP --no-ignore
> ```

### ⚠️ Cuidado com área de trabalho dentro do acervo

O `config-backup` faz `rsync -a` de **tudo** dentro de `PAREDEDEPAPEL`, **incluindo
diretórios ocultos**. Numa execução, a área de trabalho `.fix-work/` (10 GB de
intermediários) foi parar no NAS e o espelho saltou de 3,8 GB para **15 GB**. Sempre
remover a área de trabalho **antes** de rodar `config-backup`, ou pôr a área de
trabalho fora do acervo.

### Reconstrução a partir do snapshot (fallback)

```bash
# o snapshot 2292 (27/09 00:00) guarda o estado original puro: 612 arquivos, 0 subpastas
SNAP=/mnt/BACKUP/.snapshots/2292/snapshot/configs-homelab/psicopompo/PAREDEDEPAPEL
sudo ls "$SNAP" | wc -l
```

Snapshots do NAS são **root-only**. `os.path.exists`/`fd` **sem root** devolvem
"não existe" (não é permissão negada explícita) — sempre checar como root.

---

## Referências

- [backups/strategy.md](../backups/strategy.md) — padrão de backup (NFS, rsync, failsafe)
- [guides/hyprland-noctalia-guide.md](hyprland-noctalia-guide.md) — desktop do psicopompo
- [servers/psicopompo.md](../servers/psicopompo.md) — hardware (RTX 5050, NVMe)
- [scripts/wallpaper-pipeline.sh](../scripts/wallpaper-pipeline.sh) — automação
- Real-ESRGAN ncnn Vulkan: <https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan>
- Issue upstream do defeito de `-s 2`: <https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/issues/73>
