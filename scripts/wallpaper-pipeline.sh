#!/usr/bin/env bash
#
# wallpaper-pipeline.sh — acervo de wallpapers do psicopompo (>=4K, EXIF-aware)
#
# Regras do acervo:
#   >=4K (largura>=3840 E altura>=2160) + exibição horizontal/quadrada -> wallpaper-pc/
#   >=4K + exibição vertical                                           -> wallpaper-celular-tablet/
#   <4K                                                                -> menores-4k/  (fila de upscale)
#
# A orientação considerada é sempre a de EXIBIÇÃO (tag EXIF 0x0112), nunca a
# dimensão crua do arquivo: JPEGs com orientation 6/8 (RightTop/LeftBottom) têm
# os pixels armazenados girados 90° e só aparecem corretos porque o visualizador
# aplica a tag. Classificar por dimensão crua joga paisagem na pasta de celular.
#
# Uso:
#   wallpaper-pipeline.sh report    [BASE]           contagem por classe (não altera nada)
#   wallpaper-pipeline.sh normalize [BASE] [--apply] grava a rotação no pixel (remove dependência de EXIF)
#   wallpaper-pipeline.sh organize  [BASE] [--apply] move para as 3 pastas (varre raiz + subpastas)
#   wallpaper-pipeline.sh upscale   [BASE]           menores-4k/ -> .upscale-work/out/
#
# O upscale usa SEMPRE a escala nativa do modelo (-s 4). NÃO use -s 2 com modelo
# x4: isso quebra o alinhamento dos tiles e destrói a imagem (armadilha 1 do guia).
#
# Imagens chapadas (< 0.02 bytes/pixel) vão por Lanczos em vez de IA — nesses casos
# os modelos inventam textura (46-102 MB por arquivo) e o Lanczos reproduz fiel em
# ~2 MB. Ver guides/wallpaper-library.md.
#
# BASE padrão: ~/Pictures/PAREDEDEPAPEL
# Dependências: imagemagick (identify/magick); realesrgan-ncnn-vulkan (apenas no upscale)
#
set -euo pipefail

BASE_DEFAULT="${HOME}/Pictures/PAREDEDEPAPEL"
EXTS=(jpg jpeg png webp gif bmp tif tiff avif)
EXT_ARGS=()
for e in "${EXTS[@]}"; do EXT_ARGS+=(-e "$e"); done
WORK_DIRNAME=".upscale-work"

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | head -n -1; }

# Lista imagens do acervo: raiz + subpastas visíveis (wallpaper-pc, celular,
# menores-4k) + saída do upscale. Diretórios ocultos (equivalem a internos)
# são ignorados pelo fd, exceto .upscale-work/out que é incluído à parte.
list_images() {
  local base="$1" up="${1}/${WORK_DIRNAME}/out"
  fd --type f --absolute-path "${EXT_ARGS[@]}" . "$base" -0
  if [[ -d "$up" ]]; then
    fd --type f --absolute-path --max-depth 1 "${EXT_ARGS[@]}" . "$up" -0
  fi
}

# Dimensões de EXIBIÇÃO: "LARGURA ALTURA" (aplica a rotação da tag EXIF).
display_dims() {
  local f="$1" w h o
  w="$(identify -format '%w' "$f")"
  h="$(identify -format '%h' "$f")"
  o="$(identify -format '%[orientation]' "$f")"
  case "$o" in
    RightTop|LeftBottom) printf '%s %s\n' "$h" "$w" ;;  # 6/8 => girado 90°
    *)                   printf '%s %s\n' "$w" "$h" ;;
  esac
}

is_4k() { (( $1 >= 3840 && $2 >= 2160 )); }

need_rotation() {
  local o
  o="$(identify -format '%[orientation]' "$1")"
  [[ "$o" != "TopLeft" && "$o" != "Undefined" && "$o" != "" ]]
}

cmd_report() {
  local base="$1" n=0 pc=0 cel=0 small=0 rot=0 f w h
  while IFS= read -r -d '' f; do
    read -r w h < <(display_dims "$f")
    n=$((n + 1))
    need_rotation "$f" && rot=$((rot + 1))
    if ! is_4k "$w" "$h"; then small=$((small + 1))
    elif (( w >= h ));      then pc=$((pc + 1))
    else                          cel=$((cel + 1)); fi
  done < <(list_images "$base")
  printf 'total=%-5d  wallpaper-pc=%-5d  wallpaper-celular-tablet=%-5d  menores-4k=%-5d  com-EXIF-rotacionado=%d\n' \
         "$n" "$pc" "$cel" "$small" "$rot"
}

cmd_normalize() {
  local base="$1" apply="$2" f n=0 tmp
  while IFS= read -r -d '' f; do
    need_rotation "$f" || continue
    n=$((n + 1))
    printf '  %-60s %sx%s (%s)\n' "$(basename "$f")" \
      "$(identify -format '%w' "$f")" "$(identify -format '%h' "$f")" \
      "$(identify -format '%[orientation]' "$f")"
    if (( apply )); then
      tmp="${f}.__norm.${f##*.}"
      magick "$f" -auto-orient -quality 95 "$tmp"
      mv -f "$tmp" "$f"
    fi
  done < <(list_images "$base")
  (( apply )) || echo "(dry-run — use --apply para gravar no pixel)"
  echo "imagens rotacionadas: $n"
}

cmd_organize() {
  local base="$1" apply="$2" f w h dest n=0
  while IFS= read -r -d '' f; do
    read -r w h < <(display_dims "$f")
    if ! is_4k "$w" "$h"; then dest="menores-4k"
    elif (( w >= h ));      then dest="wallpaper-pc"
    else                          dest="wallpaper-celular-tablet"; fi
    [[ "$(dirname "$f")" == "${base}/${dest}" ]] && continue
    if [[ -e "${base}/${dest}/$(basename "$f")" ]]; then
      echo "COLISÃO, pulando: ${dest}/$(basename "$f")" >&2; continue
    fi
    if (( apply )); then
      mkdir -p "${base}/${dest}"
      mv -n "$f" "${base}/${dest}/"
    fi
    n=$((n + 1))
  done < <(list_images "$base")
  (( apply )) || echo "(dry-run — use --apply para mover)"
  echo "imagens a mover: $n"
  # limpa a fazenda de upscale se esvaziou
  local work="${base}/${WORK_DIRNAME}"
  if (( apply )) && [[ -d "$work" ]] && ! fd --type f . "${work}/out" | rg -q .; then
    rm -rf "$work"; echo "removido ${WORK_DIRNAME}/ (vazio)"
  fi
}

run_batch() {
  local work="$1" ext="$2"
  local extra=()
  [[ "$ext" == "jpg" || "$ext" == "jpeg" ]] && extra=(-f jpg)
  # Sem -f o default (ext/png) converte TODO jpg em png (~12 MB por 4K).
  # -s 4 = escala NATIVA do realesrgan-x4plus. -t nunca acima de 512 (segfault).
  realesrgan-ncnn-vulkan -i "${work}/in-${ext}/" -o "${work}/out/" \
    -s 4 -n realesrgan-x4plus "${extra[@]}" >"${work}/${ext}.log" 2>&1
}

# Teto de 8192 no lado maior. NÃO é opcional: sem ele saem arquivos de até
# 14000x24000 (336 MP, ~84 MB) que vários visualizadores não abrem.
aplicar_teto() {
  local work="$1" f w h tw th tmp
  while IFS= read -r -d '' f; do
    w="$(identify -format '%w' "$f")"; h="$(identify -format '%h' "$f")"
    (( w > 8192 || h > 8192 )) || continue
    if (( w >= h )); then tw=8192; th=$(( h * 8192 / w )); else th=8192; tw=$(( w * 8192 / h )); fi
    tmp="${f}.__cap.${f##*.}"
    magick "$f" -filter Lanczos -resize "${tw}x${th}!" "$tmp" && mv -f "$tmp" "$f"
    echo "   teto: ${w}x${h} -> ${tw}x${th}  $(basename "$f")"
  done < <(fd --type f --absolute-path --max-depth 1 . "${work}/out" -0)
}

# Imagens chapadas: bytes/pixel < 0.02. IA inventa textura nessas.
e_chapada() {
  local f="$1" w h
  w="$(identify -format '%w' "$f")"; h="$(identify -format '%h' "$f")"
  awk -v b="$(stat -c %s "$f")" -v p="$(( w * h ))" 'BEGIN { exit !(b / p < 0.02) }'
}

cmd_upscale() {
  local base="$1"
  local src="${base}/menores-4k" work="${base}/${WORK_DIRNAME}"
  [[ -d "$src" ]] || { echo "sem ${src}" >&2; exit 1; }
  command -v realesrgan-ncnn-vulkan >/dev/null || { echo "instale realesrgan-ncnn-vulkan (AUR)" >&2; exit 1; }
  rm -rf "$work"; mkdir -p "${work}/out"

  # 1) set chapado -> Lanczos 400% direto para a saída
  local f n_lanc=0
  while IFS= read -r -d '' f; do
    e_chapada "$f" || continue
    magick "$f" -filter Lanczos -resize 400% "${work}/out/$(basename "$f")" && n_lanc=$((n_lanc + 1))
  done < <(fd --type f --absolute-path --max-depth 1 "${EXT_ARGS[@]}" . "$src" -0)
  echo "chapadas por Lanczos: ${n_lanc}"

  # 2) o resto -> hardlinks por extensão + IA x4 nativo
  local exts=() e
  for e in "${EXTS[@]}"; do
    if fd --type f --max-depth 1 -e "$e" . "$src" | rg -q .; then exts+=("$e"); fi
  done
  if (( ${#exts[@]} > 0 )); then
    for e in "${exts[@]}"; do
      mkdir -p "${work}/in-${e}"
      while IFS= read -r -d '' f; do
        e_chapada "$f" && continue
        ln -f "$f" "${work}/in-${e}/$(basename "$f")"
      done < <(fd --type f --absolute-path --max-depth 1 -e "$e" . "$src" -0)
    done
    echo "lotes IA: ${exts[*]}  |  -s 4 (nativo)  |  modelo realesrgan-x4plus"
    echo "limite: 2 workers simultâneos (3 estouram os 8 GB da RTX 5050)"
    # ATENÇÃO: o upscaler descarta a tag EXIF — rode 'normalize' ANTES.
    if (( ${#exts[@]} >= 2 )); then
      run_batch "$work" "${exts[0]}" & local p1=$!
      run_batch "$work" "${exts[1]}" & local p2=$!
      wait "$p1" "$p2"
      for e in "${exts[@]:2}"; do run_batch "$work" "$e"; done
    else
      run_batch "$work" "${exts[0]}"
    fi
  fi

  # 3) teto
  echo "aplicando teto de 8192:"
  aplicar_teto "$work"

  echo "saída em ${work}/out"
  echo "próximo passo: wallpaper-pipeline.sh organize ${base} --apply"
}

main() {
  local cmd="${1:-}"; shift || true
  local apply=0 args=()
  for a in "$@"; do
    case "$a" in
      --apply) apply=1 ;;
      *)       args+=("$a") ;;
    esac
  done
  local base="${args[0]:-$BASE_DEFAULT}"
  [[ -d "$base" ]] || { echo "BASE inválido: $base" >&2; exit 1; }

  case "$cmd" in
    report)    cmd_report "$base" ;;
    normalize) cmd_normalize "$base" "$apply" ;;
    organize)  cmd_organize "$base" "$apply" ;;
    upscale)   cmd_upscale "$base" ;;
    *)         usage; exit 1 ;;
  esac
}

main "$@"
