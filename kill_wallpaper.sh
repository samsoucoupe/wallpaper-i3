#!/bin/bash
set -u

BASE_DIR="${HOME}/wallpaper"
PIDFILE="/tmp/set_random_bg.pid"
CURRENT_SET_FILE="/tmp/set_random_bg.current"
LOG_FILE="/tmp/set_random_bg.log"

# Tue tous les processus
pkill -f "${BASE_DIR}/set_random_bg.sh" || true
pkill -f 'set_random_bg.sh' || true
pgrep -af 'set_random_bg.sh|set_random_bg' || true

# Nettoie les fichiers temporaires
rm -f "$PIDFILE"
rm -f "$CURRENT_SET_FILE"
rm -f "$LOG_FILE"

notify-send "Wallpaper" "Process wallpaper arrêté."
