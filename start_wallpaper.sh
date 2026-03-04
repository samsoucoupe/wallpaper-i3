#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/wallpaper"
SCRIPT="$BASE_DIR/set_random_bg.sh"
LOG_FILE="/tmp/set_random_bg.log"

if [ ! -x "$SCRIPT" ]; then
    chmod +x "$SCRIPT"
fi

nohup "$SCRIPT" >> "$LOG_FILE" 2>&1 &
disown

echo "Wallpaper lancé. Log: $LOG_FILE"
