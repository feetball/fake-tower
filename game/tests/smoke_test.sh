#!/bin/bash
# Smoke test: launch the real main scene headless for a bounded number of frames in each
# mode and fail on script errors / load errors (tools/ci_check_log.sh) or a bad exit code.
# Usage: game/tests/smoke_test.sh [mode...]   modes: menu pilot pilot_far controller
#        solo solo_impostor solo_controller (text-radio rounds with AI players: run 3x the
#        frames so the first AI transmissions reach the views)
#        env GODOT overrides the binary, FRAMES the frame budget (default 240),
#        TIMEOUT the wall-clock limit per mode in seconds (default 120),
#        SMOKE_ALLOW_MISSING_VIEW=1 to not fail when a view scene file is absent.
# Requires the import cache (godot --headless --path game --import) to exist.
set -u
GODOT="${GODOT:-/home/user/tools/godot/godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES="${FRAMES:-240}"
TIMEOUT="${TIMEOUT:-120}"
LOGS="$(mktemp -d)"
MODES=("$@")
[ ${#MODES[@]} -gt 0 ] || MODES=(menu pilot pilot_far controller solo solo_impostor solo_controller)

fail=0
for mode in "${MODES[@]}"; do
  frames="$FRAMES"
  case "$mode" in
    menu) args=(); view="" ;;
    pilot | pilot_far) args=(-- "--demo=$mode"); view="scenes/pilot/pilot_view.tscn" ;;
    controller) args=(-- "--demo=$mode"); view="scenes/controller/controller_view.tscn" ;;
    solo | solo_impostor) args=(-- "--demo=$mode"); view="scenes/pilot/pilot_view.tscn"; frames=$((FRAMES * 3)) ;;
    solo_controller) args=(-- "--demo=$mode"); view="scenes/controller/controller_view.tscn"; frames=$((FRAMES * 3)) ;;
    *) echo "unknown mode: $mode" >&2; exit 2 ;;
  esac
  log="$LOGS/$mode.log"
  start=$SECONDS
  timeout "$TIMEOUT" "$GODOT" --headless --path "$DIR" --quit-after "$frames" "${args[@]}" >"$log" 2>&1
  rc=$?
  reason=""
  # main.gd silently falls back to a placeholder when a view scene is missing, so a
  # demo run alone would pass without exercising the view: require the scene to exist.
  if [ -n "$view" ] && [ ! -f "$DIR/$view" ] && [ -z "${SMOKE_ALLOW_MISSING_VIEW:-}" ]; then
    reason="view scene $view does not exist (SMOKE_ALLOW_MISSING_VIEW=1 to ignore)"
  fi
  if [ $rc -eq 124 ]; then reason="${reason:+$reason; }timed out after ${TIMEOUT}s"
  elif [ $rc -ne 0 ]; then reason="${reason:+$reason; }exit code $rc"; fi
  if ! "$DIR/tools/ci_check_log.sh" "$log" >"$LOGS/$mode.check" 2>&1; then
    reason="${reason:+$reason; }script/load errors in log"
  fi
  if [ -z "$reason" ]; then
    echo "PASS smoke[$mode] ($((SECONDS - start))s, $frames frames)"
  else
    echo "FAIL smoke[$mode]: $reason"
    sed 's/^/    /' "$LOGS/$mode.check"
    tail -n 15 "$log" | sed 's/^/    log> /'
    fail=1
  fi
done
echo "SMOKE SUMMARY: $([ $fail -eq 0 ] && echo 'all modes passed' || echo "failures (logs in $LOGS)")"
[ $fail -eq 0 ] && rm -rf "$LOGS"
exit $fail
