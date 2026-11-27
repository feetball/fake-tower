extends RefCounted
## An AI pilot that flies by the text radio: it follows clearances addressed to its
## callsign (from any controller, or only those in `obey`), reads back WILCO or
## UNABLE, checks in, calls minimum fuel, and configures for the ILS itself once
## cleared (flaps 2 on the localizer, gear and flaps 3 on the glideslope). A careful
## pilot refuses what a sharp human would: an altitude below the MSA before it is
## established, a QNH that is not the ATIS one, a heading into terrain.
## Flies through the same autopilot commands a human uses (SimAircraft.apply).

const Datalink := preload("res://core/net/datalink.gd")
const Geo := preload("res://core/sim/geo.gd")
const SimAircraft := preload("res://core/sim/aircraft.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")

const REPLY_DELAY_S := 1.5
const RETRY_S := 1.5
const QUIET_REQUEST_S := 150.0
const MIN_FUEL_MIN := 8.0
const MAYDAY_FUEL_MIN := 4.0
const TRANSITION_ALT := 6000
const TERRAIN_LOOK_NM := 12.0
const TERRAIN_MARGIN_FT := 300.0
const ORBIT_DEG := 350.0
const LANDING_SPEED_NM := 5.0
const LANDING_SPD := 140

var id := 0
var ac: SimAircraft
var world: SimWorld
var atis_qnh := 1013
## Controllers whose clearances this pilot follows; empty = any controller.
var obey: Array[int] = []
## Read back (WILCO) clearances from controllers not in `obey` too, without flying them.
var ack_others := false
## Refuse unsafe instructions (MSA, QNH, terrain). A gullible pilot does as told.
var careful := true
## Replies, check-in and calls on the frequency (false: a silent test pilot).
var talk := true
## Round seconds before checking in (< 0: never).
var checkin_at := 2.0
## Clearances accepted / refused, oldest first (tests and diagnostics).
var heard: Array[Dictionary] = []
var refused: Array[Dictionary] = []

var _t := 0.0
var _out: Array[Dictionary] = [] ## {at, msg}
var _cleared := false
var _config := 0 ## 0 en route, 1 cleared (flaps 1), 2 on the localizer, 3 on the glideslope
var _orbit_turn := ""
var _orbit_done := 0.0
var _orbit_prev := 0.0
var _orbit_resume := 0
var _missed := 0 ## 1 climbing straight ahead to 3000, 2 turned onto 060 for 6000
var _heard_t := 0.0
var _fuel_called := 0
var _checked_in := false


func _init(pid: int, aircraft: SimAircraft, w: SimWorld, qnh: int) -> void:
	id = pid
	ac = aircraft
	world = w
	atis_qnh = qnh


func is_cleared() -> bool:
	return _cleared


func tick(dt: float, send: Callable) -> void:
	if not ac.is_flying():
		_out.clear()
		return
	_t += dt
	if talk and not _checked_in and checkin_at >= 0.0 and _t >= checkin_at:
		_checked_in = true
		_heard_t = _t
		_say(Datalink.radio_call("checkin"), 0.0)
	_fly()
	if talk:
		_fuel_calls()
		if _checked_in and not _cleared and _t - _heard_t > QUIET_REQUEST_S:
			_heard_t = _t
			_say(Datalink.radio_call("req_vectors"), 0.0)
	_flush(send)


## Every aired message on the frequency (Room.dl_hook via the demo).
func hear(m: Dictionary) -> void:
	if String(m.get("status", "")) != "ok" or not ac.is_flying():
		return
	if String(m.get("kind", "")) != Datalink.KIND_CLR or String(m.get("to", "")) != ac.callsign:
		return
	if String(m.get("role", "")) != "controller":
		return
	if not obey.is_empty() and not obey.has(int(m.get("from", 0))):
		if ack_others and talk and _wants_reply(m):
			_say(Datalink.reply(int(m["id"]), "wilco"), REPLY_DELAY_S)
		return
	_heard_t = _t
	var why := check(m) if careful else ""
	if why != "":
		refused.append(m)
		if talk:
			_say(Datalink.reply(int(m["id"]), "unable", why), REPLY_DELAY_S)
		return
	heard.append(m)
	_apply(m)
	if talk and _wants_reply(m):
		_say(Datalink.reply(int(m["id"]), "wilco"), REPLY_DELAY_S)


## Why a careful pilot refuses this clearance ("msa", "qnh", "terrain"), or "".
func check(m: Dictionary) -> String:
	var established := ac.loc_captured
	var a := Datalink.find_item(m, "alt")
	if not a.is_empty() and not established and float(a["v"]) < Geo.msa_at(world, ac.x, ac.y):
		return "msa"
	var q := Datalink.find_item(m, "qnh")
	if not q.is_empty() and int(q["v"]) != atis_qnh:
		return "qnh"
	var h := Datalink.find_item(m, "hdg")
	if not h.is_empty() and not established:
		var alt_ft := ac.alt
		if not a.is_empty():
			alt_ft = minf(alt_ft, float(a["v"]))
		if heading_hits_terrain(world, ac.x, ac.y, float(h["v"]), alt_ft):
			return "terrain"
	return ""


## Does a straight line from (x, y) on `hdg` meet an obstacle within ~300 ft of `alt_ft`?
static func heading_hits_terrain(w: SimWorld, x: float, y: float, hdg: float, alt_ft: float) -> bool:
	var dx := Geo.heading_dx(hdg)
	var dy := Geo.heading_dy(hdg)
	var d := 0.5
	while d <= TERRAIN_LOOK_NM:
		if Geo.obstacle_elev_at(w, x + dx * d, y + dy * d) > alt_ft - TERRAIN_MARGIN_FT:
			return true
		d += 0.5
	return false


static func _wants_reply(m: Dictionary) -> bool:
	for it: Dictionary in m.get("items", []):
		if not ["roger", "contact"].has(String(it["t"])):
			return true
	return false


func _apply(m: Dictionary) -> void:
	for it: Dictionary in m.get("items", []):
		match String(it["t"]):
			"hdg":
				_orbit_turn = ""
				_missed = 0
				ac.apply({"hdg": int(it["v"])})
			"orbit":
				_orbit_turn = String(it["turn"])
				_orbit_done = 0.0
				_orbit_prev = ac.hdg
				_orbit_resume = ac.sel_hdg
			"alt":
				ac.apply({"alt": int(it["v"])})
				if int(it["v"]) < TRANSITION_ALT and ac.alt_setting == 1013 and not Datalink.has_item(m, "qnh"):
					ac.apply({"alt_setting": atis_qnh})
			"spd":
				_set_speed(int(it["v"]))
			"qnh":
				ac.apply({"alt_setting": int(it["v"])})
			"app":
				_cleared = true
				_missed = 0
				ac.apply({"app": true})
				_configure(1)
			"cancel":
				_cleared = false
				_config = 0
				ac.apply({"app": false})
			"land":
				if ac.loc_captured:
					_configure(3)
			"ga":
				_go_around()


func _set_speed(v: int) -> void:
	var f := ac.flaps
	while f < 3 and SimAircraft.MIN_SPD[f] > v:
		f += 1
	ac.apply({"flaps": f, "spd": v})


func _configure(stage: int) -> void:
	if stage <= _config:
		return
	_config = stage
	match stage:
		1:
			ac.apply({"flaps": maxi(ac.flaps, 1), "spd": mini(ac.sel_spd, 180)})
		2:
			ac.apply({"flaps": maxi(ac.flaps, 2), "spd": mini(ac.sel_spd, 160)})
		3:
			ac.apply({"gear": true, "flaps": 3, "spd": 140})


func _go_around() -> void:
	_cleared = false
	_config = 0
	_orbit_turn = ""
	ac.apply({"app": false, "gear": false, "flaps": 1, "spd": 200})
	if ac.indicated_alt(atis_qnh) < 2900.0:
		ac.apply({"hdg": int(world.runway_heading), "alt": 3000})
		_missed = 1
	else:
		ac.apply({"hdg": 60, "alt": 6000})
		_missed = 2


func _fly() -> void:
	if _orbit_turn != "":
		_orbit_done += absf(Geo.angle_diff(_orbit_prev, ac.hdg))
		_orbit_prev = ac.hdg
		if _orbit_done >= ORBIT_DEG:
			_orbit_turn = ""
			ac.apply({"hdg": _orbit_resume})
		else:
			ac.apply({"hdg": ac.hdg + (-60.0 if _orbit_turn == "L" else 60.0)})
	if _missed == 1 and ac.indicated_alt(atis_qnh) >= 2900.0:
		_missed = 2
		ac.apply({"hdg": 60, "alt": 6000})
	if _cleared:
		if ac.gs_captured:
			_configure(3)
		elif ac.loc_captured:
			_configure(2)
		# Whatever speed was assigned, landing speed by 5 nm (the threshold limit is 155 kt).
		if ac.loc_captured and Geo.hypot(ac.x, ac.y) < LANDING_SPEED_NM and ac.sel_spd > LANDING_SPD:
			_configure(3)
			ac.apply({"spd": LANDING_SPD})


func _fuel_calls() -> void:
	if ac.fuel_min < MAYDAY_FUEL_MIN and _fuel_called < 2:
		_fuel_called = 2
		_say(Datalink.radio_call("mayday_fuel"), 0.0)
	elif ac.fuel_min < MIN_FUEL_MIN and _fuel_called < 1:
		_fuel_called = 1
		_say(Datalink.radio_call("min_fuel"), 0.0)


func _say(msg: Dictionary, delay: float) -> void:
	_out.append({"at": _t + delay, "msg": msg})


func _flush(send: Callable) -> void:
	if _out.is_empty() or not send.is_valid():
		return
	var keep: Array[Dictionary] = []
	for o in _out:
		if float(o["at"]) > _t:
			keep.append(o)
			continue
		var err: Variant = send.call(id, o["msg"])
		if err is String and String(err).begins_with("Frequency busy"):
			o["at"] = _t + RETRY_S
			keep.append(o)
	_out = keep
