#!/bin/bash
# Network integration test: one headless host + 3 headless clients on localhost.
# Usage: game/tests/net_test.sh   (env GODOT overrides the binary, PORT the port,
#        MIXED=1 makes client 3 join the same player-host over WebSocket, port PORT+1)
# Each instance runs with --net-test (core/net/net_test.gd) and prints NETTEST lines.
set -u
GODOT="${GODOT:-/home/user/tools/godot/godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-$((27300 + RANDOM % 500))}"
LOGS="$(mktemp -d)"
SCENE="res://tests/blank.tscn"
run() { # name, args...
  local n="$1"; shift
  timeout 90 "$GODOT" --headless --path "$DIR" "$SCENE" -- --net-test --port="$PORT" "$@" >"$LOGS/$n.log" 2>&1 &
}
run host --host --autostart --name=Host
sleep 1.5
for i in 1 2 3; do
  join=127.0.0.1
  [ "$i" = 3 ] && [ -n "${MIXED:-}" ] && join="ws://127.0.0.1:$((PORT + 1))"
  run "c$i" --join="$join" --name="Client$i"; sleep 0.3
done
wait
cat "$LOGS"/*.log | grep -E "NETTEST|SCRIPT ERROR" | sed 's/^/  /'

fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
lines="$(cat "$LOGS"/*.log | grep '^NETTEST id=')"
n() { printf '%s\n' "$lines" | grep -c -- "$1"; }
check "4 instances reported" "[ $(printf '%s\n' "$lines" | grep -c .) -eq 4 ]"
check "exactly 2 controllers" "[ $(n 'role=controller') -eq 2 ]"
check "exactly 2 pilots" "[ $(n 'role=pilot') -eq 2 ]"
check "exactly one impostor=true" "[ $(n 'impostor=true') -eq 1 ]"
check "the impostor is a controller" "[ $(n 'role=controller impostor=true') -eq 1 ]"
check "no pilot got radar" "[ $(n 'role=pilot impostor=false got_radar=true') -eq 0 ]"
check "both controllers got radar" "[ $(n 'role=controller impostor=[a-z]* got_radar=true') -eq 2 ]"
check "ap command reflected for both pilots" "[ $(cat "$LOGS"/*.log | grep -c 'NETTEST ap_ok=true') -eq 2 ]"
check "text-radio clearance heard by all 4" "[ $(cat "$LOGS"/*.log | grep -c 'NETTEST dl_heard') -eq 4 ]"
check "the addressed pilot got it" "[ $(cat "$LOGS"/*.log | grep -c 'NETTEST dl_clr') -eq 1 ]"
check "the controller got the WILCO" "[ $(cat "$LOGS"/*.log | grep -c 'NETTEST dl_readback id=[0-9]* text=Wilco') -eq 1 ]"
check "no script errors" "! cat \"$LOGS\"/*.log | grep -q 'SCRIPT ERROR'"
check "no timeouts" "! cat \"$LOGS\"/*.log | grep -q 'NETTEST timeout'"
echo "NET SUMMARY: $([ $fail -eq 0 ] && echo 'all checks passed' || echo "failures (logs in $LOGS)")"
[ $fail -eq 0 ] && rm -rf "$LOGS"
exit $fail
