#!/bin/bash
# WebSocket / dedicated-server integration test: one headless dedicated server (--server,
# not a player) + 4 headless clients play a full round to its natural end and return to
# the lobby. The server runs its simulation sped up (--time-scale) so a round takes ~30 s.
#   leader     4 WebSocket clients; the first to join is the lobby leader and starts the
#              round and returns to the lobby. Also checks open-mic voice relay in the
#              lobby and PTT relay rules in the round, through the non-player host.
#   autostart  --autostart-at=4: the server starts by itself and returns to the lobby by
#              itself; 3 WebSocket clients + 1 ENet client on the same server (mixed).
# Usage: game/tests/ws_net_test.sh [leader] [autostart]   (default: both)
#        env GODOT overrides the binary, PORT the ENet port (WebSocket = PORT + 1),
#        TIME_SCALE the server's simulation speed-up (default 40).
# Each instance runs with --net-test --full-round (core/net/net_test.gd).
set -u
GODOT="${GODOT:-/home/user/tools/godot/godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCALE="${TIME_SCALE:-40}"
MODES=("$@")
[ ${#MODES[@]} -gt 0 ] || MODES=(leader autostart)
SCENE="res://tests/blank.tscn"
fail=0
keep=0

check() { if eval "$2"; then echo "PASS [$mode] $1"; else echo "FAIL [$mode] $1"; fail=1; keep=1; fi; }

for mode in "${MODES[@]}"; do
  LOGS="$(mktemp -d)"
  P="${PORT:-$((27800 + RANDOM % 500 * 2))}"
  WS=$((P + 1))
  extra=()
  [ "$mode" = autostart ] && extra=(--server-starts)
  # Launched as SERVER.md says: --headless, the server scene, --server.
  case "$mode" in
    leader) srv=(--server) ;;
    autostart) srv=(--server --autostart-at=4 --lobby-after=3) ;;
    *) echo "unknown mode: $mode" >&2; exit 2 ;;
  esac
  timeout 200 "$GODOT" --headless --path "$DIR" res://core/net/server.tscn -- "${srv[@]}" --net-test --full-round \
    --port="$P" --ws-port="$WS" --time-scale="$SCALE" "${extra[@]}" >"$LOGS/server.log" 2>&1 &
  sleep 2
  joins=("ws://127.0.0.1:$WS" "ws://localhost:$WS/" "ws://127.0.0.1:$WS" "ws://localhost:$WS")
  [ "$mode" = autostart ] && joins[3]="127.0.0.1:$P" # ENet, mixed with WebSocket
  for i in 1 2 3 4; do
    timeout 200 "$GODOT" --headless --path "$DIR" "$SCENE" -- --net-test --full-round \
      --join="${joins[$((i - 1))]}" --name="Client$i" "${extra[@]}" >"$LOGS/c$i.log" 2>&1 &
    sleep 0.4
  done
  wait
  cat "$LOGS"/*.log | grep -E "NETTEST|SCRIPT ERROR|\[server\]" | sed 's/^/  /'

  all="$(cat "$LOGS"/c*.log)"
  srvlog="$(cat "$LOGS/server.log")"
  roles="$(printf '%s\n' "$all" | grep '^NETTEST id=')"
  n() { printf '%s\n' "$roles" | grep -c -- "$1"; }
  c() { printf '%s\n' "$all" | grep -c -- "$1"; }
  field() { sed -n "s/.*$1=\([^ ]*\).*/\1/p"; }
  check "4 clients reported a role" "[ $(printf '%s\n' "$roles" | grep -c .) -eq 4 ]"
  check "exactly 2 controllers" "[ $(n 'role=controller') -eq 2 ]"
  check "exactly 2 pilots" "[ $(n 'role=pilot') -eq 2 ]"
  check "exactly one impostor, a controller" "[ $(n 'role=controller impostor=true') -eq 1 ] && [ $(n 'impostor=true') -eq 1 ]"
  check "no pilot got radar" "[ $(n 'role=pilot impostor=false got_radar=true') -eq 0 ]"
  check "both controllers got radar" "[ $(n 'role=controller impostor=[a-z]* got_radar=true') -eq 2 ]"
  check "ap command reflected for both pilots" "[ $(c 'NETTEST ap_ok=true') -eq 2 ]"
  check "server is not a player (no role, no host=true client)" \
    "! printf '%s\n' \"\$srvlog\" | grep -q '^NETTEST id=' && [ $(n 'host=true') -eq 0 ]"
  check "server started a round of 4 players" "printf '%s\n' \"\$srvlog\" | grep -q 'NETTEST server round_began players=4'"
  real="$(printf '%s\n' "$roles" | grep 'role=controller impostor=false' | field id)"
  imp="$(printf '%s\n' "$roles" | grep 'impostor=true' | field id)"
  sres="$(printf '%s\n' "$srvlog" | grep 'NETTEST server result' | sed 's/.*result //')"
  check "server computed a result" "[ -n \"\$sres\" ]"
  check "4 clients got the result" "[ $(c 'NETTEST result id=') -eq 4 ]"
  check "every client's result matches the server's" \
    "[ $(printf '%s\n' "$all" | grep 'NETTEST result id=' | sed 's/.*id=[0-9]* //' | grep -cxF -- "$sres") -eq 4 ]"
  check "result names the real controller and the impostor" \
    "printf '%s\n' \"\$sres\" | grep -q \"real=$real impostor=$imp outcomes=2\""
  check "round ran to its natural end (duration > 60 s)" "[ \"\$(printf '%s\n' \"\$sres\" | field duration)\" -gt 60 ]"
  check "4 clients back in the lobby" "[ $(c 'NETTEST lobby id=') -eq 4 ]"
  check "exactly one lobby leader" "[ $(c 'NETTEST lobby id=[0-9]* leader=true') -eq 1 ]"
  check "server back in the lobby and done" \
    "printf '%s\n' \"\$srvlog\" | grep -q 'NETTEST server back_in_lobby' && printf '%s\n' \"\$srvlog\" | grep -q 'NETTEST server done'"
  check "radio: 4 reports" "[ $(c 'NETTEST radio id=') -eq 4 ]"
  check "radio: the 3 others heard the keyed pilot (>= 8 of 10 packets)" \
    "[ $(printf '%s\n' "$all" | grep 'NETTEST radio .*keyer=false' | field got_keyed | awk '$1 >= 8' | wc -l) -eq 3 ]"
  check "radio: nobody heard the unkeyed controller" \
    "[ $(printf '%s\n' "$all" | grep 'NETTEST radio ' | grep -vc 'got_unkeyed=0') -eq 0 ]"
  if [ "$mode" = leader ]; then
    lead="$(grep -h 'NETTEST leader_start' "$LOGS/c1.log" | field id)"
    check "the first-joined client led and started the round" "[ -n \"\$lead\" ] && [ $(c 'NETTEST leader_start') -eq 1 ]"
    check "the leader is the one leader in the lobby" "[ $(c "NETTEST lobby id=$lead leader=true") -eq 1 ]"
    check "lobby open mic: every client heard the 3 others" "[ $(c 'NETTEST lobby_voice id=[0-9]* heard_from=3') -eq 4 ]"
  else
    check "no client started the round (server autostart)" "[ $(c 'NETTEST leader_start') -eq 0 ]"
    check "ENet client in the same game as the WebSocket clients" "grep -q 'NETTEST result id=' \"$LOGS/c4.log\""
  fi
  check "no script errors" "! cat \"$LOGS\"/*.log | grep -q 'SCRIPT ERROR'"
  check "no timeouts" "! cat \"$LOGS\"/*.log | grep -q 'NETTEST timeout'"
  check "no connection errors" "! cat \"$LOGS\"/c*.log | grep -qE 'NETTEST (connection_lost|error=)'"
  check "logs clean (tools/ci_check_log.sh)" "\"$DIR/tools/ci_check_log.sh\" \"$LOGS\"/*.log >/dev/null 2>&1"
  if [ $keep -eq 0 ]; then rm -rf "$LOGS"; else echo "  (logs in $LOGS)"; keep=0; fi
done
echo "WS NET SUMMARY: $([ $fail -eq 0 ] && echo 'all checks passed' || echo 'failures')"
exit $fail
