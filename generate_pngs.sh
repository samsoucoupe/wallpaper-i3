#!/bin/bash
# -----------------------------
# Convertit les nouveaux médias (GIF/MP4) en sets d'images
# Compatible ImageMagick 6 (utilise convert)
# -----------------------------

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
GIFSRC="$BASE/gifs_source"
SETS="$BASE/sets"
IM_TMP="$BASE/.im_cache"
MAX_FRAMES="${MAX_FRAMES:-300}"
CONVERT_TIMEOUT="${CONVERT_TIMEOUT:-180}"
IM_MEMORY_LIMIT="${IM_MEMORY_LIMIT:-1GiB}"
IM_MAP_LIMIT="${IM_MAP_LIMIT:-2GiB}"
IM_DISK_LIMIT="${IM_DISK_LIMIT:-16GiB}"

mkdir -p "$GIFSRC" "$SETS" "$IM_TMP"

# Détection de la résolution écran (xrandr), avec fallback 1920x1080
detect_screen_size () {
    local screen
    screen=$(xrandr --query 2>/dev/null | awk '/ connected primary / {print $4; exit}')

    if [ -z "$screen" ]; then
        screen=$(xrandr --query 2>/dev/null | awk '/ connected / {print $3; exit}')
    fi

    if [ -n "$screen" ]; then
        screen="${screen%%+*}"
        SCREEN_W="${screen%x*}"
        SCREEN_H="${screen#*x}"
    fi

    if [ -z "$SCREEN_W" ] || [ -z "$SCREEN_H" ]; then
        SCREEN_W=1920
        SCREEN_H=1080
    fi

    # Force le rendu final en 16:9
    TARGET_H="$SCREEN_H"
    TARGET_W=$(( TARGET_H * 16 / 9 ))

    if [ "$TARGET_W" -gt "$SCREEN_W" ]; then
        TARGET_W="$SCREEN_W"
        TARGET_H=$(( TARGET_W * 9 / 16 ))
    fi
}

detect_screen_size
echo "Résolution détectée: ${SCREEN_W}x${SCREEN_H} | Cible 16:9: ${TARGET_W}x${TARGET_H}"

if command -v magick >/dev/null 2>&1; then
    IM_CMD=(magick)
elif command -v convert >/dev/null 2>&1; then
    IM_CMD=(convert)
else
    echo "ImageMagick introuvable (magick/convert)."
    exit 1
fi

# Limites ImageMagick pour éviter les erreurs "cache resources exhausted"
IM_LIMIT_ARGS=(
    -limit memory "$IM_MEMORY_LIMIT"
    -limit map "$IM_MAP_LIMIT"
    -limit disk "$IM_DISK_LIMIT"
)

has_timeout() {
    command -v timeout >/dev/null 2>&1
}

run_convert() {
    local input_gif="$1"
    local output_pattern="$2"

    if has_timeout; then
        timeout "$CONVERT_TIMEOUT" env MAGICK_TMPDIR="$IM_TMP" TMPDIR="$IM_TMP" "${IM_CMD[@]}" \
            "${IM_LIMIT_ARGS[@]}" \
            -define registry:temporary-path="$IM_TMP" \
            "$input_gif" -coalesce \
            -resize "${TARGET_W}x${TARGET_H}^" \
            -gravity center \
            -extent "${TARGET_W}x${TARGET_H}" \
            "$output_pattern"
    else
        MAGICK_TMPDIR="$IM_TMP" TMPDIR="$IM_TMP" "${IM_CMD[@]}" \
            "${IM_LIMIT_ARGS[@]}" \
            -define registry:temporary-path="$IM_TMP" \
            "$input_gif" -coalesce \
            -resize "${TARGET_W}x${TARGET_H}^" \
            -gravity center \
            -extent "${TARGET_W}x${TARGET_H}" \
            "$output_pattern"
    fi
}

run_ffmpeg_convert() {
    local gif="$1"
    local output_pattern="$2"
    local step="$3"

    if ! command -v ffmpeg >/dev/null 2>&1; then
        return 1
    fi

    ffmpeg -v error -y -i "$gif" \
        -vf "select='not(mod(n\\,${step}))',scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=increase,crop=${TARGET_W}:${TARGET_H}" \
        -vsync vfr \
        "$output_pattern"
}

get_frame_count() {
    local gif="$1"
    local identify_cmd=()

    if command -v identify >/dev/null 2>&1; then
        identify_cmd=(identify -ping -format '%n\n' "$gif")
    elif [ "${IM_CMD[0]}" = "magick" ]; then
        identify_cmd=(magick identify -ping -format '%n\n' "$gif")
    else
        echo 0
        return 0
    fi

    if has_timeout; then
        timeout 20 "${identify_cmd[@]}" 2>/dev/null | head -n1 || true
    else
        "${identify_cmd[@]}" 2>/dev/null | head -n1 || true
    fi

    return 0
}

# Fonction pour convertir un média (GIF/MP4) si le set n'existe pas
convert_media () {
    local media="$1"
    local name
    name=$(basename "$media")
    name="${name%.*}"
    local outdir="$SETS/$name"
    local ext
    ext="${media##*.}"
    ext="${ext,,}"

    echo "Traitement : $name"

    if [ -d "$outdir" ]; then
        return
    fi

    local tmpdir="${outdir}.tmp.$$"
    rm -rf "$tmpdir"
    mkdir -p "$tmpdir"

    local frame_count_in
    if [ "$ext" = "gif" ]; then
        frame_count_in=$(get_frame_count "$media")
    else
        frame_count_in=0
        if command -v ffprobe >/dev/null 2>&1; then
            frame_count_in=$(ffprobe -v error -count_frames -select_streams v:0 \
                -show_entries stream=nb_read_frames -of default=nw=1:nk=1 "$media" 2>/dev/null | head -n1 || true)

            if ! [[ "$frame_count_in" =~ ^[0-9]+$ ]] || [ "$frame_count_in" -eq 0 ]; then
                frame_count_in=$(ffprobe -v error -select_streams v:0 \
                    -show_entries stream=nb_frames -of default=nw=1:nk=1 "$media" 2>/dev/null | head -n1 || true)
            fi
        fi
    fi

    if ! [[ "$frame_count_in" =~ ^[0-9]+$ ]]; then
        frame_count_in=0
    fi

    local input_spec="$media"
    local step=1
    if [ "$frame_count_in" -gt "$MAX_FRAMES" ]; then
        step=$(( (frame_count_in + MAX_FRAMES - 1) / MAX_FRAMES ))
        if [ "$ext" = "gif" ]; then
            input_spec="${media}[0--1x${step}]"
        fi
        echo "Média lourd détecté ($frame_count_in frames) : échantillonnage 1/${step}"
    fi

    # Conversion dans un dossier temporaire, puis publication atomique
    if [ "$ext" = "gif" ] && run_convert "$input_spec" "$tmpdir/${name}_%03d.png"; then

        local frame_count
        frame_count=$(find "$tmpdir" -maxdepth 1 -type f -name '*.png' | wc -l)

        if [ "$frame_count" -eq 0 ]; then
            echo "Conversion vide ignorée : $gif"
            rm -rf "$tmpdir"
            return
        fi

        mv "$tmpdir" "$outdir"
        echo "Média converti : $media → $outdir ($frame_count frames)"
    else
        if [ "$ext" != "gif" ]; then
            echo "Conversion ffmpeg : $media"
        else
            echo "Échec conversion ImageMagick, tentative ffmpeg : $media"
        fi
        rm -rf "$tmpdir"
        mkdir -p "$tmpdir"

        if run_ffmpeg_convert "$media" "$tmpdir/${name}_%03d.png" "$step"; then
            local ffmpeg_frames
            ffmpeg_frames=$(find "$tmpdir" -maxdepth 1 -type f -name '*.png' | wc -l)

            if [ "$ffmpeg_frames" -gt 0 ]; then
                mv "$tmpdir" "$outdir"
                echo "Média converti via ffmpeg : $media → $outdir ($ffmpeg_frames frames)"
            else
                echo "Échec conversion : aucune frame générée pour $media"
                rm -rf "$tmpdir"
            fi
        else
            echo "Échec conversion (ressources insuffisantes ou média invalide) : $media"
            rm -rf "$tmpdir"
        fi
    fi
}

# Parcours et conversion de tous les GIF/MP4 du dossier source
for g in "$GIFSRC"/*.{gif,mp4}; do
    echo "Vérification : $g"
    [ -f "$g" ] && convert_media "$g"
done
