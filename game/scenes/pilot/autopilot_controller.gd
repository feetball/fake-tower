class_name PilotAutopilot
extends Node
## The pilot's side of the autopilot: turns keyboard and cockpit-control input
## into `ap` commands for Session.send_ap (only the changed fields, coalesced
## to at most one message per SEND_INTERVAL), and keeps the commanded values
## the panel shows. A commanded value is displayed immediately and then
## reconciled with the server's value after RECONCILE_S, so server-side
## clamping (e.g. selected speed below the flap minimum) becomes visible.

signal commanded(kind: String) ## a knob/switch was operated (for click sounds)

const RECONCILE_S := 1.5
const SEND_INTERVAL := 0.1
## knob -> [min, max, step, big step]
const LIMITS := {
	"hdg": [0, 359, 1, 10],
	"alt": [0, 20000, 100, 1000],
	"spd": [140, 250, 1, 10],
	"baro": [950, 1050, 1, 5],
}
const SERVER_KEY := {"hdg": "sel_hdg", "alt": "sel_alt", "spd": "sel_spd", "baro": "alt_setting"}
const AP_KEY := {"hdg": "hdg", "alt": "alt", "spd": "spd", "baro": "alt_setting"}

var own: Dictionary = {}
## Keyboard input is ignored while true (e.g. the EFB is open and wants keys).
var input_blocked := false

var _pending: Dictionary = {} ## knob -> [value, until_s]
var _outbox: Dictionary = {}
var _since_send := 0.0
var _last_qnh := -1
var _now := 0.0


func _ready() -> void:
	Session.own_updated.connect(func(o: Dictionary) -> void: own = o)
	own = Session.own


func _process(delta: float) -> void:
	_now += delta
	_since_send += delta
	if not _outbox.is_empty() and _since_send >= SEND_INTERVAL:
		_flush()


## The value the panel shows for a knob: the pending command or the server's.
func display_value(k: String) -> int:
	if _pending.has(k):
		var p: Array = _pending[k]
		if _now < float(p[1]):
			return int(p[0])
		_pending.erase(k)
	var v: Variant = own.get(SERVER_KEY[k], null)
	if v == null:
		return int(LIMITS[k][0]) if k != "baro" else 1013
	return int(v)


## True while a commanded value is still waiting for the server (for a subtle cue).
func is_pending(k: String) -> bool:
	return _pending.has(k) and _now < float(_pending[k][1])


func nudge(k: String, dir: int, big: bool) -> void:
	var lim: Array = LIMITS[k]
	var step: int = lim[3] if big else lim[2]
	var v := display_value(k) + dir * step
	if k == "alt":
		v = int(round(float(v) / step)) * step
	set_knob(k, v)


func set_knob(k: String, raw: int) -> void:
	var lim: Array = LIMITS[k]
	var v := raw
	if k == "hdg":
		v = posmod(v, 360)
	elif k == "alt":
		v = clampi(int(round(v / 100.0)) * 100, lim[0], lim[1])
	else:
		v = clampi(v, lim[0], lim[1])
	_pending[k] = [v, _now + RECONCILE_S]
	_queue({AP_KEY[k]: v})
	commanded.emit(k)


func toggle_std() -> void:
	var cur := display_value("baro")
	if cur == 1013:
		if _last_qnh > 0 and _last_qnh != 1013:
			set_knob("baro", _last_qnh)
	else:
		_last_qnh = cur
		set_knob("baro", 1013)


func toggle_app() -> void:
	if own.is_empty():
		return
	_queue({"app": not bool(own.get("app_armed", false))}, true)
	commanded.emit("app")


func set_gear(down: bool) -> void:
	_queue({"gear": down}, true)
	commanded.emit("gear")


func toggle_gear() -> void:
	if not own.is_empty():
		set_gear(not bool(own.get("gear_down", false)))


func set_flaps(f: int) -> void:
	f = clampi(f, 0, 3)
	if own.is_empty() or f == int(own.get("flaps", 0)):
		return
	_queue({"flaps": f}, true)
	commanded.emit("flaps")


func _queue(changes: Dictionary, immediate: bool = false) -> void:
	_outbox.merge(changes, true)
	if immediate or _since_send >= SEND_INTERVAL:
		_flush()


func _flush() -> void:
	if _outbox.is_empty():
		return
	Session.send_ap(_outbox.duplicate())
	_outbox.clear()
	_since_send = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if input_blocked or not event.is_pressed():
		return
	var shift := (event as InputEventKey).shift_pressed
	var handled := true
	if event.is_action("hdg_left"):
		nudge("hdg", -1, shift)
	elif event.is_action("hdg_right"):
		nudge("hdg", 1, shift)
	elif event.is_action("alt_up"):
		nudge("alt", 1, shift)
	elif event.is_action("alt_down"):
		nudge("alt", -1, shift)
	elif event.is_action("spd_up"):
		nudge("spd", 1, shift)
	elif event.is_action("spd_down"):
		nudge("spd", -1, shift)
	elif event.is_action("baro_down"):
		nudge("baro", -1, shift)
	elif event.is_action("baro_up"):
		nudge("baro", 1, shift)
	elif event.is_echo():
		handled = false # switches do not auto-repeat
	elif event.is_action("baro_std"):
		toggle_std()
	elif event.is_action("toggle_app"):
		toggle_app()
	elif event.is_action("toggle_gear"):
		toggle_gear()
	elif event.is_action("flaps_up"):
		set_flaps(int(own.get("flaps", 0)) - 1)
	elif event.is_action("flaps_down", true):
		set_flaps(int(own.get("flaps", 0)) + 1)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
