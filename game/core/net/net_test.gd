extends Node
## Test mode for tests/net_test.sh (user arg --net-test). Prints machine-readable
## NETTEST lines; pilots send one autopilot command and check it comes back in
## their own state; then the instance quits. Not used otherwise.

const AP_ALT := 12300
const AP_HDG := 123
const REPORT_AFTER_SEC := 3.0 ## radar sweeps at t = 0 and 2 s
const HOST_QUIT_SEC := 10.0
const CLIENT_QUIT_SEC := 6.0
const TIMEOUT_SEC := 60.0

var _got_radar := false
var _ap_sent := false
var _ap_ok := false
@onready var _s: Node = get_parent()


func _ready() -> void:
	_s.radar_swept.connect(func(_t: Array) -> void: _got_radar = true)
	_s.round_began.connect(_on_round_began)
	_s.own_updated.connect(_on_own)
	_s.connection_lost.connect(func() -> void: print("NETTEST connection_lost"))
	_s.error.connect(func(m: String) -> void: print("NETTEST error=%s" % m.replace(" ", "_")))
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		print("NETTEST timeout")
		get_tree().quit(2))


func _on_round_began() -> void:
	await get_tree().create_timer(REPORT_AFTER_SEC).timeout
	print("NETTEST id=%d host=%s role=%s impostor=%s got_radar=%s callsign=%s" % [
		_s.my_id, _s.is_host, _s.my_role, _s.i_am_impostor, _got_radar, _s.my_callsign])
	if _s.my_role == "pilot":
		_ap_sent = true
		_s.send_ap({"alt": AP_ALT, "hdg": AP_HDG})
	await get_tree().create_timer(HOST_QUIT_SEC if _s.is_host else CLIENT_QUIT_SEC).timeout
	if _ap_sent and not _ap_ok:
		print("NETTEST ap_ok=false")
	print("NETTEST done id=%d" % _s.my_id)
	get_tree().quit(0)


func _on_own(ac: Dictionary) -> void:
	if _ap_sent and not _ap_ok and int(ac.get("sel_alt", 0)) == AP_ALT and int(ac.get("sel_hdg", 0)) == AP_HDG:
		_ap_ok = true
		print("NETTEST ap_ok=true id=%d sel_alt=%d sel_hdg=%d" % [_s.my_id, AP_ALT, AP_HDG])
