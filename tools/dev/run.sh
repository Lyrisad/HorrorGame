#!/bin/sh
# run.sh <dossier> <nom> <timeout_s> [args jeu...] : lance le jeu fenêtré en mode test et range les captures
# dans tools/dev/out/<dossier>/<nom>_N.png (avec --shots=3,8). Toujours --nomic : le jeu n'écoute pas le vrai micro.
# Exemple : sh tools/dev/run.sh egouts grille 40 --level=sewer --torch --warp=26.6,26.6 --shots=4,8
ROOT="$(cd "$(dirname "$0")/../.." && (pwd -W 2>/dev/null || pwd))"
OUT="${DEV_OUT:-$ROOT/tools/dev/out}"
dir="$OUT/$1"; name="$2"; to="$3"; shift 3
mkdir -p "$dir"
cd "$ROOT" || exit 1
timeout $((to + 60)) tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -- --nomic --windowed --quit --timeout=$to --shot="$dir/$name" "$@" 2>&1 | grep -v -E "^\s*$|WARNING: Material|glTF: File uses|at: _|Vulkan|Godot Engine|^   at|CAPTURE" | head -400
