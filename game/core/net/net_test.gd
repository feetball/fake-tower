extends Node
## Test mode for tests/net_test.sh and tests/ws_net_test.sh (user arg --net-test).
## Prints machine-readable NETTEST lines, then the instance quits. Not used otherwise.
##
## Short mode (net_test.sh): pilots send one autopilot command and check it comes back
## in their own state; every instance quits a few seconds into the round.
## Full mode (--full-round, ws_net_test.sh): additionally
##   lobby: once everyone is in, every client sends a few voice packets (open mic);
##          the leader starts the round (unless the server autostarts, --server-starts);
##   round: the lowest-id pilot keys the radio and talks, the lowest-id controller talks
##          without keying (must not be relayed); everyone reports what it heard;
##   end:   the round runs to its natural end (the server runs with --time-scale), every
##          client reports the result, the leader (or the server) returns to the lobby,
##          clients report being back in the lobby and quit.
## A dedicated server reports with "NETTEST server ..." lines and quits once the clients left.

const AP_ALT := 12300
const AP_HDG := 123
const REPORT_AFTER_SEC := 3.0 ## radar sweeps at t = 0 and 2 s
const HOST_QUIT_SEC := 10.0
const CLIENT_QUIT_SEC := 6.0
const TIMEOUT_SEC := 60.0
const FULL_TIMEOUT_SEC := 180.0
const VOICE_PACKETS := 10
const LEADER_START_DELAY_SEC := 2.0

var _got_radar := false
var _ap_sent := false
var _ap_ok := false
var _full := false
var _server_starts := false
var _lobby_voice_sent := false
var _seen_end := false
var _round_rx: Dictionary = {} # Voice rx counts at round start
@onready var _s: Node = get_parent()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_full = args.has("--full-round")
	_server_starts = args.has("--server-starts")
	_s.radar_swept.connect(func(_t: Array) -> void: _got_radar = true)
	_s.round_began.connect(_on_round_began)
	_s.own_updated.connect(_on_own)
	_s.round_ended.connect(_on_round_ended)
	_s.lobby_changed.connect(_on_lobby_changed)
	_s.phase_changed.connect(_on_phase_changed)
	_s.connection_lost.connect(func() -> void: print("NETTEST connection_lost"))
	_s.error.connect(func(m: String) -> void: print("NETTEST error=%s" % m.replace(" ", "_")))
	var limit := FULL_TIMEOUT_SEC if _full else TIMEOUT_SEC
	# Real seconds, whatever the time scale.
	get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
		print("NETTEST timeout")
		get_tree().quit(2))


func _voice() -> Node:
	return get_node_or_null(^"/root/Voice")


func _rx_counts() -> Dictionary:
	var v := _voice()
	return v.rx_counts.duplicate() if v != null else {}


func _real_wait(sec: float) -> Signal:
	return get_tree().create_timer(sec, true, false, true).timeout


# ---------------------------------------------------------------- lobby

func _on_lobby_changed() -> void:
	if not _full or _s.is_dedicated or _lobby_voice_sent or _s.phase != "lobby":
		return
	var connected: int = _s.players.filter(func(q: Dictionary) -> bool: return q["connected"]).size()
	if connected < _s.min_players:
		return
	_lobby_voice_sent = true
	await _real_wait(0.5)
	_voice().debug_send_tone(VOICE_PACKETS)
	if _s.is_leader and not _server_starts:
		await _real_wait(LEADER_START_DELAY_SEC)
		print("NETTEST leader_start id=%d" % _s.my_id)
		_s.start_round()


func _on_phase_changed(p: String) -> void:
	if p != "lobby" or not _seen_end:
		return
	if _s.is_dedicated:
		print("NETTEST server back_in_lobby")
		return
	print("NETTEST lobby id=%d leader=%s" % [_s.my_id, _s.is_leader])
	await _real_wait(1.0)
	print("NETTEST done id=%d" % _s.my_id)
	get_tree().quit(0)


# ---------------------------------------------------------------- round

func _on_round_began() -> void:
	if _s.is_dedicated:
		print("NETTEST server round_began players=%d roles=%s" % [_s.round_players.size(),
			",".join(_s.round_players.map(func(q: Dictionary) -> String: return q["role"]))])
		return
	if _full:
		var lobby_rx := _rx_counts()
		var heard: int = lobby_rx.keys().filter(func(k: int) -> bool: return lobby_rx[k] > 0).size()
		print("NETTEST lobby_voice id=%d heard_from=%d" % [_s.my_id, heard])
		_round_rx = lobby_rx
	await _real_wait(REPORT_AFTER_SEC)
	print("NETTEST id=%d host=%s role=%s impostor=%s got_radar=%s callsign=%s" % [
		_s.my_id, _s.is_host, _s.my_role, _s.i_am_impostor, _got_radar, _s.my_callsign])
	if _s.my_role == "pilot":
		_ap_sent = true
		_s.send_ap({"alt": AP_ALT, "hdg": AP_HDG})
	if _full:
		await _radio_check()
		return
	await get_tree().create_timer(HOST_QUIT_SEC if _s.is_host else CLIENT_QUIT_SEC).timeout
	if _ap_sent and not _ap_ok:
		print("NETTEST ap_ok=false")
	print("NETTEST done id=%d" % _s.my_id)
	get_tree().quit(0)


func _lowest(role: String) -> int:
	var best := 0
	for q: Dictionary in _s.round_players:
		if q["role"] == role and (best == 0 or int(q["id"]) < best):
			best = int(q["id"])
	return best


## The lowest-id pilot keys and talks; the lowest-id controller talks unkeyed.
func _radio_check() -> void:
	var keyer := _lowest("pilot")
	var unkeyed := _lowest("controller")
	if _s.my_id == keyer:
		_s.set_ptt(true)
		await _real_wait(0.5)
		_voice().debug_send_tone(VOICE_PACKETS)
		await _real_wait(0.5)
		_s.set_ptt(false)
	elif _s.my_id == unkeyed:
		await _real_wait(0.5)
		_voice().debug_send_tone(VOICE_PACKETS)
	await _real_wait(2.0)
	var now := _rx_counts()
	var got_keyer: int = now.get(keyer, 0) - _round_rx.get(keyer, 0)
	var got_unkeyed: int = now.get(unkeyed, 0) - _round_rx.get(unkeyed, 0)
	print("NETTEST radio id=%d keyer=%s got_keyed=%d got_unkeyed=%d" % [
		_s.my_id, _s.my_id == keyer, got_keyer, got_unkeyed])


func _on_own(ac: Dictionary) -> void:
	if _ap_sent and not _ap_ok and int(ac.get("sel_alt", 0)) == AP_ALT and int(ac.get("sel_hdg", 0)) == AP_HDG:
		_ap_ok = true
		print("NETTEST ap_ok=true id=%d sel_alt=%d sel_hdg=%d" % [_s.my_id, AP_ALT, AP_HDG])


func _on_round_ended(res: Dictionary) -> void:
	_seen_end = true
	var line := "winner=%s real=%d impostor=%d outcomes=%d duration=%d" % [
		res.get("winner", ""), int(res.get("real_controller_id", 0)), int(res.get("impostor_id", 0)),
		res.get("outcomes", []).size(), int(res.get("duration_sec", 0))]
	if _s.is_dedicated:
		print("NETTEST server result " + line)
		_server_wait_and_quit()
		return
	print("NETTEST result id=%d %s" % [_s.my_id, line])
	if _s.is_leader and not _server_starts:
		await _real_wait(1.0)
		_s.return_to_lobby()


## Dedicated server: quit once every client has disconnected after the round.
func _server_wait_and_quit() -> void:
	while true:
		await _real_wait(0.5)
		if _s.phase == "lobby" and multiplayer.get_peers().is_empty():
			print("NETTEST server done")
			get_tree().quit(0)
			return
