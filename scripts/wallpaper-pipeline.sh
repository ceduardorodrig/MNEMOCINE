#!/usr/bin/env bash
#
# wallpaper-pipeline.sh — acervo de wallpapers do psicopompo (>=4K, EXIF-aware)
#
# Regras do acervo:
#   >=4K (width>=3840 AND height>=2160) + horizontal/square display -> wallpaper-pc/
#   >=4K + vertical display                                           -> wallpaper-celular-tablet/
#   <4K                                                                -> menores-4k/  (fila de upscale)
#
# The orientation considered is always the DISPLAY one (EXIF tag 0x0112), never the
# raw dimension of the file: JPEGs with orientation 6/8 (RightTop/LeftBottom) have
# their stored pixels rotated 90° and only look correct because the viewer
# applies the tag. Classifying by raw dimension sends landscape images to the phone folder.
#
# Uso:
#   wallpaper-pipeline.sh report    [BASE]           count per class (changes nothing)
#   wallpaper-pipeline.sh normalize [BASE] [--apply] writes the rotation into the pixels (removes the EXIF dependency)
#   wallpaper-pipeline.sh organize  [BASE] [--apply] move para as 3 pastas (varre raiz + subpastas)
#   wallpaper-pipeline.sh upscale   [BASE]           menores-4k/ -> .upscale-work/out/
#
# The upscale ALWAYS uses the model's native scale (-s 4). Do NOT use -s 2 with an
# x4 model: it breaks the tile alignment and destroys the image (trap 1 of the guide).
#
# Flat images (< 0.02 bytes/pixel) go through Lanczos instead of AI — in those cases
# os modelos inventam textura (46-102 MB por arquivo) e o Lanczos reproduz fiel em
# ~2 MB. Ver guides/wallpaper-library.md.
#
# Default BASE: ~/Pictures/PAREDEDEPAPEL
# Dependencies: imagemagick (identify/magick); realesrgan-ncnn-vulkan (upscale only)
#
set -euo pipefail

BASE_DEFAULT="${HOME}/Pictures/PAREDEDEPAPEL"
EXTS=(jpg jpeg png webp gif bmp tif tiff avif)
EXT_ARGS=()
for e in "${EXTS[@]}"; do EXT_ARGS+=(-e "$e"); done
WORK_DIRNAME=".upscale-work"

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | head -n -1; }

# Lists images of the collection: root + visible subfolders (wallpaper-pc, phone,
# smaller-than-4k) + upscale output. Hidden directories (they count as internal)
# are ignored by fd, except .upscale-work/out which is included separately.
list_images() {
  local base="$1" up="${1}/${WORK_DIRNAME}/out"
  fd --type f --absolute-path "${EXT_ARGS[@]}" . "$base" -0
  if [[ -d "$up" ]]; then
    fd --type f --absolute-path --max-depth 1 "${EXT_ARGS[@]}" . "$up" -0
  fi
}

# DISPLAY dimensions: "WIDTH HEIGHT" (applies the rotation of the EXIF tag).
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

# Cap of 8192 on the longer side. NOT optional: without it files of up to
# 14000x24000 (336 MP, ~84 MB) come out, which many viewers cannot open.
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

  # 1) flat set -> Lanczos 400% straight to the output
  local f n_lanc=0
  while IFS= read -r -d '' f; do
    e_chapada "$f" || continue
    magick "$f" -filter Lanczos -resize 400% "${work}/out/$(basename "$f")" && n_lanc=$((n_lanc + 1))
  done < <(fd --type f --absolute-path --max-depth 1 "${EXT_ARGS[@]}" . "$src" -0)
  echo "chapadas por Lanczos: ${n_lanc}"

  # 2) the rest -> hardlinks per extension + native x4 AI
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
    # WARNING: the upscaler drops the EXIF tag — run 'normalize' FIRST.
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
