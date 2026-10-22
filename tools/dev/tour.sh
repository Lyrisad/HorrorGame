#!/bin/sh
# tour.sh <dossier> <début> <fin> [args...] : tour automatique des égouts, une capture par point de vue
# (points <début> à <fin> parmi les 256 de --tour). Planche : python tools/dev/toursheet.py <dossier> <sortie.png>
ROOT="$(cd "$(dirname "$0")/../.." && (pwd -W 2>/dev/null || pwd))"
OUT="${DEV_OUT:-$ROOT/tools/dev/out}"
dir="$1"; a="$2"; b="$3"; shift 3
n=$((b - a + 1))
shots=$(awk -v n=$n 'BEGIN{for(i=0;i<n;i++){printf (i?",":"") "%.2f", 1.0+i*1.5+1.25}}')
to=$(awk -v n=$n 'BEGIN{printf "%d", 1.0+n*1.5+70}')
mkdir -p "$OUT/$dir"
cd "$ROOT" || exit 1
timeout $((to + 90)) tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -- --nomic --windowed --quit --timeout=$to --shot="$OUT/$dir/v$a" --level=sewer --torch --tour=$a,$b --shots=$shots "$@" 2>&1 | grep -i "error\|script" | grep -v "WARNING" | head -20
