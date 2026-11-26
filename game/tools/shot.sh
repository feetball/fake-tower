#!/bin/bash
# Run the game (or one scene) off-screen with software rendering and save a screenshot.
# Usage: tools/shot.sh <out.png> [seconds] [godot args... e.g. res://scenes/pilot/pilot_view.tscn -- --demo]
#   env RENDERER  forward_plus (default) | mobile | gl_compatibility
#                 (Vulkan via lavapipe for the first two, OpenGL 3 via llvmpipe for Compatibility)
# The scene being run must honour the user args "--shot=<path>" and "--shot-after=<sec>"
# (handled by core/shot_helper.gd, which any scene can add as a child).
set -e
OUT="$1"; SEC="${2:-4}"; shift; shift || true
GODOT="${GODOT:-/home/user/tools/godot/godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
case "${RENDERER:-forward_plus}" in
  forward_plus) RARGS=(--rendering-method forward_plus --rendering-driver vulkan) ;;
  mobile) RARGS=(--rendering-method mobile --rendering-driver vulkan) ;;
  gl_compatibility) RARGS=(--rendering-method gl_compatibility --rendering-driver opengl3) ;;
  *) echo "shot.sh: unknown RENDERER=$RENDERER" >&2; exit 2 ;;
esac
# "--shot" must land in the user args: add a "--" separator unless the caller already did.
SEP=(--)
for a in "$@"; do [ "$a" = "--" ] && SEP=(); done
xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$DIR" "${RARGS[@]}" --resolution 1920x1080 "$@" "${SEP[@]}" --shot="$OUT" --shot-after="$SEC" 2>&1 | grep -vE "ALSA|audio drivers|^$" || true
ls -la "$OUT"
