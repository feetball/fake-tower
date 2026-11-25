#!/bin/bash
# Run the game (or one scene) off-screen with software Vulkan and save a screenshot.
# Usage: tools/shot.sh <out.png> [seconds] [godot args... e.g. res://scenes/pilot/pilot_view.tscn -- --demo]
# The scene being run must honour the user args "--shot=<path>" and "--shot-after=<sec>"
# (handled by core/shot_helper.gd, which any scene can add as a child).
set -e
OUT="$1"; SEC="${2:-4}"; shift; shift || true
GODOT="${GODOT:-/home/user/tools/godot/godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$DIR" --rendering-driver vulkan --resolution 1920x1080 "$@" --shot="$OUT" --shot-after="$SEC" 2>&1 | grep -vE "ALSA|audio drivers|^$" || true
ls -la "$OUT"
