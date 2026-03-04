#!/bin/bash
# -----------------------------
# Applique un set d'images aléatoire en fond avec feh
# Change de set toutes les CHANGE_INTERVAL secondes
# Détecte automatiquement les nouveaux sets
# Tue toute instance précédente du script
# -----------------------------

set -u
shopt -s nullglob

BASE="$HOME/wallpaper"
SETS="$BASE/sets"
INTERVAL=0.01        # secondes entre les frames
CHANGE_INTERVAL=300   # secondes entre changement de set

PIDFILE="/tmp/set_random_bg.pid"
CURRENT_SET_FILE="/tmp/set_random_bg.current"
FORCE_NEXT_SET=0

# Si le fichier existe et le PID correspond à un process vivant, on le tue
if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    kill $(cat "$PIDFILE")
fi

# Écrit le PID actuel
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
trap 'FORCE_NEXT_SET=1' USR1


# Fonction pour récupérer tous les sets disponibles
get_sets() {
    find "$SETS" -mindepth 1 -maxdepth 1 -type d \
        ! -name '*.tmp.*' \
        ! -name '.*' \
        -print 2>/dev/null
}

# Récupère les images valides d'un set
get_images() {
    local set_dir="$1"
    find "$set_dir" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
        -print 2>/dev/null | sort
}

pick_new_set() {
    local current_set="$1"

    if [ ${#sets[@]} -le 1 ]; then
        echo "$current_set"
        return
    fi

    while true; do
        local candidate="${sets[RANDOM % ${#sets[@]}]}"
        [ "$candidate" != "$current_set" ] && echo "$candidate" && return
    done
}

# Initialisation
start_time=$(date +%s)
mapfile -t sets < <(get_sets)
if [ ${#sets[@]} -eq 0 ]; then
    echo "Aucun set trouvé dans $SETS"
    exit 1
fi

RANDOM_SET="${sets[RANDOM % ${#sets[@]}]}"
echo "$(basename "$RANDOM_SET")" > "$CURRENT_SET_FILE"

while true; do
    # Rafraîchir la liste des sets à chaque boucle
    mapfile -t sets < <(get_sets)
    if [ ${#sets[@]} -eq 0 ]; then
        echo "Aucun set trouvé dans $SETS"
        exit 1
    fi

    # Si le set courant disparaît, en choisir un autre
    if [ ! -d "$RANDOM_SET" ]; then
        RANDOM_SET="${sets[RANDOM % ${#sets[@]}]}"
    fi

    mapfile -t images < <(get_images "$RANDOM_SET")

    # Ignore les sets vides/incomplets
    if [ ${#images[@]} -eq 0 ]; then
        RANDOM_SET="${sets[RANDOM % ${#sets[@]}]}"
        sleep 1
        continue
    fi

    # Parcours toutes les images du set actuel
    for image in "${images[@]}"; do
        if [ -f "$image" ]; then
            feh --bg-center "$image" >/dev/null 2>&1 || true
        fi
        sleep "$INTERVAL"

        if [ "$FORCE_NEXT_SET" -eq 1 ]; then
            RANDOM_SET="$(pick_new_set "$RANDOM_SET")"
            FORCE_NEXT_SET=0
            start_time=$(date +%s)
            echo "$(basename "$RANDOM_SET")" > "$CURRENT_SET_FILE"
            break
        fi

        # Vérifie si on doit changer de set
        now=$(date +%s)
        elapsed=$(( now - start_time ))
        if [ $elapsed -ge $CHANGE_INTERVAL ]; then
            RANDOM_SET="$(pick_new_set "$RANDOM_SET")"
            start_time=$now
            echo "$(basename "$RANDOM_SET")" > "$CURRENT_SET_FILE"
            break  # sort de la boucle for pour commencer le nouveau set
        fi
    done
done
