#!/bin/bash
# Screenshot every screen under each renderer: shots/plat_<renderer>_<scene>.png,
# with the Godot log next to it in $LOGDIR (default: a temp dir, printed at the end).
# Usage: tools/platform_shots.sh [renderer...] [-- scene...]
#   renderers: forward_plus mobile gl_compatibility (default: all three)
#   scenes:    menu pilot_panel pilot_outside controller controller_room hud end (default: all)
#   env PREFIX  file name prefix (default plat), SEC seconds before the shot (default 6)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$HERE/.." && pwd)"
PREFIX="${PREFIX:-plat}"
SEC="${SEC:-6}"
LOGDIR="${LOGDIR:-$(mktemp -d)}"
RENDERERS=()
SCENES=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; SCENES=("$@"); break; fi
  RENDERERS+=("$1"); shift
done
[ ${#RENDERERS[@]} -gt 0 ] || RENDERERS=(forward_plus mobile gl_compatibility)
[ ${#SCENES[@]} -gt 0 ] || SCENES=(menu pilot_panel pilot_outside controller controller_room hud end)
mkdir -p "$GAME/shots" "$LOGDIR"
for r in "${RENDERERS[@]}"; do
  for s in "${SCENES[@]}"; do
    case "$s" in
      menu) args=() ;;
      pilot_panel) args=(res://scenes/pilot/pilot_view.tscn -- --demo=pilot --pilot-view=panel) ;;
      pilot_outside) args=(res://scenes/pilot/pilot_view.tscn -- --demo=pilot --pilot-view=outside --pilot-debug-pos=1.2,400) ;;
      controller) args=(-- --demo=controller) ;;
      controller_room) args=(res://scenes/controller/controller_view.tscn -- --demo=controller --ctrl-debug-targets --ctrl-framing=room) ;;
      hud) args=(-- --ui-demo=hud_pilot) ;;
      end) args=(-- --ui-demo=end) ;;
      *) echo "unknown scene $s" >&2; exit 2 ;;
    esac
    out="$GAME/shots/${PREFIX}_${r}_${s}.png"
    rm -f "$out"
    RENDERER="$r" "$HERE/shot.sh" "$out" "$SEC" "${args[@]}" >"$LOGDIR/${r}_${s}.log" 2>&1
    errs="$(grep -cE '^(ERROR|SCRIPT ERROR|WARNING)' "$LOGDIR/${r}_${s}.log")"
    echo "$r $s: $([ -f "$out" ] && echo ok || echo NO-SHOT) ($errs error/warning lines)"
  done
done
echo "logs: $LOGDIR"
