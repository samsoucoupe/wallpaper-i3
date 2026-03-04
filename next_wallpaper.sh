#!/bin/bash
set -u

PIDFILE="/tmp/set_random_bg.pid"

if [ ! -f "$PIDFILE" ]; then
    notify-send "Wallpaper" "Script non démarré (pas de PID)."
    exit 1
fi

pid=$(cat "$PIDFILE" 2>/dev/null || true)
if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    notify-send "Wallpaper" "Process wallpaper introuvable."
    exit 1
fi

kill -USR1 "$pid"
