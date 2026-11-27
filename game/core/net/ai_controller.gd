extends RefCounted
## An AI approach controller working the frequency by text (core/net/datalink.gd):
## first contact with the ATIS letter and QNH, vectors via a base point and a gate to
## a 30° localizer intercept at a safe altitude, the approach and landing clearances,
## spacing (a 360 for AI traffic when two would arrive together), low-altitude,
## altimeter and traffic alerts, missed approaches. With `honest` it also watches
## the other controller: an unsafe instruction to one of its aircraft is corrected
## at once ("disregard...") and the other controller called out.
##
## It sees only what a controller sees: the radar picture (SimRound.radar(), the
## same targets a scope gets) and what is said on the frequency (hear()). It flies
## nobody: AI pilots (ai_pilot.gd) and the human act on its messages, or do not.
## ai_impostor.gd extends this with the lies.
##
## Geometry (sim nm, x east / y north of the threshold; final approach course 270):
## side +1 is north of the centreline, -1 south. The intercept heading is 240 from
## the north, 300 from the south. The intercept altitude ("level") is the side's
## MSA rounded up, plus 1000 ft per aircraft already working that side; the
## intercept point is 3 nm beyond where the glideslope passes that level, so the
## glideslope is always captured from below. Gate = 7 nm before that point on the
## intercept course; base = 6 nm out from the gate, away from the centreline.

const Datalink := preload("res://core/net/datalink.gd")
const Geo := preload("res://core/sim/geo.gd")
const SimRound := preload("res://core/sim/round.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")
const AiPilot := preload("res://core/net/ai_pilot.gd")

const THINK_S := 1.0
const GAP_S := 20.0 ## minimum between routine instructions to one aircraft
const REPEAT_S := 45.0 ## an ignored instruction is said again after this long
const FIRST_CONTACT_GAP_S := 4.0
const HDG_ROUND := 5
const HDG_REISSUE_DEG := 15.0
const GATE_LEG_NM := 7.0
const BASE_LEG_NM := 6.0
const GS_MARGIN_NM := 3.0
const D_INT_MIN := 10.0
const D_INT_MAX := 23.0
const LEVEL_MAX := 9000
const WP_RADIUS_NM := 2.0
const WP_PASS_NM := 4.5
const SPACING_NM := 6.0
const ORBIT_S := 125.0
const LAND_CLEAR_NM := 7.0
const MSAW_REPEAT_S := 40.0
const TRAFFIC_LOOK_S := 90.0
const TRAFFIC_NM := 1.5
const TRAFFIC_FT := 700.0
const TRAFFIC_REPEAT_S := 40.0
const ACCUSE_REPEAT_S := 150.0
const ALT_OFF_FT := 100.0


class Plan:
	extends RefCounted
	var cs := ""
	var stage := "new" ## new | vector | cleared | final | missed | done
	var side := 1
	var level := 0
	var d_int := 0.0
	var gate := Vector2.ZERO
	var wps: Array[Vector2] = []
	var wp := 0
	var last_d := INF
	var hdg := -1 ## our last assigned heading / altitude / speed (-1 none)
	var alt := -1
	var spd := -1
	var said_t := -1000.0
	var hdg_t := -1000.0
	var alt_t := -1000.0
	var msaw_t := -1000.0
	var traffic_t := -1000.0
	var alt_off_n := 0
	var orbit_until := -1.0
	var avoid_until := -1.0
	var repeats := 0 ## instructions said again in a row (backs the repeats off)
	var land_cleared := false
	var priority := false
	var pending := 0 ## our messages to it not yet aired
	var retry: Dictionary = {} ## a message of ours that was blocked: say it again
	var sent: Dictionary = {} ## message id -> our clearance (for "say again")


var id := 0
var sim: SimRound
var world: SimWorld
## (from_id: int, msg: Dictionary) -> String: Room.handle_dl.
var send: Callable
## Correct the other controller's unsafe instructions and call them out.
var honest := true
## Served first (the human pilot's callsign).
var priority_cs := ""
var plans: Dictionary = {} ## callsign -> Plan
var spoken := 0 ## messages we put on the frequency (diagnostics)
var _t := 0.0
var _think := 0.0
var _contact_t := -1000.0
var _accused: Dictionary = {} ## player id -> time we last called them out
var _calls: Array[Dictionary] = [] ## calls the full frequency queue refused, to say again
var _gate_leg := GATE_LEG_NM


func _init(controller_id: int, round_sim: SimRound, send_fn: Callable) -> void:
	id = controller_id
	sim = round_sim
	world = round_sim.world
	send = send_fn


func tick(dt: float) -> void:
	_t += dt
	_think -= dt
	if _think > 0.0:
		return
	_think = THINK_S
	var calls := _calls
	_calls = []
	for c in calls:
		_say(c)
	var targets := sim.radar()
	for tg in targets:
		var cs := String(tg["callsign"])
		if not _works(cs):
			continue
		if not plans.has(cs):
			var np := Plan.new()
			np.cs = cs
			np.priority = cs == priority_cs
			plans[cs] = np
		var p: Plan = plans[cs]
		if String(tg["status"]) != "flying":
			p.stage = "done"
			continue
		if p.pending > 0:
			continue
		if not p.retry.is_empty():
			var again := p.retry
			p.retry = {}
			_send_clr(p, again["items"])
			continue
		_work(p, tg, targets)


## Which aircraft this controller works (the impostor only works its target).
func _works(_cs: String) -> bool:
	return true


# ---------------------------------------------------------------- listening

## Every aired message on the frequency (Room.dl_hook via the demo).
func hear(m: Dictionary) -> void:
	var st := String(m.get("status", ""))
	var kind := String(m.get("kind", ""))
	if int(m.get("from", 0)) == id:
		if kind == Datalink.KIND_CLR and plans.has(String(m.get("to", ""))):
			var p: Plan = plans[String(m["to"])]
			p.pending = maxi(0, p.pending - 1)
			if st == "ok":
				p.sent[int(m["id"])] = m
			elif st in ["blocked", "expired"]:
				p.retry = m
		return
	if st != "ok":
		return
	if kind == Datalink.KIND_CLR and String(m.get("role", "")) == "controller":
		_on_other_controller(m)
		return
	var p := _plan_of_cs(String(m.get("from_cs", "")))
	if p == null:
		return
	var it: Dictionary = (m.get("items", [{}]) as Array)[0]
	var t := String(it.get("t", ""))
	if kind == Datalink.KIND_CALL:
		match t:
			"min_fuel", "mayday_fuel":
				if not p.priority:
					p.priority = true
					_send_clr(p, [Datalink.item("roger")])
			"req_vectors":
				p.hdg = -1
				p.said_t = -1000.0
	elif kind == Datalink.KIND_REPLY:
		var ours: Dictionary = p.sent.get(int(m.get("re", 0)), {})
		if ours.is_empty():
			return
		match t:
			"say_again":
				p.retry = ours
			"unable":
				# Be more conservative with this one: an extra 1000 ft and a fresh vector.
				p.level = mini(p.level + 1000, LEVEL_MAX)
				_geometry(p)
				p.hdg = -1
				p.alt = -1
				p.said_t = -1000.0


func _plan_of_cs(cs: String) -> Plan:
	return plans.get(cs, null) if cs != "" else null


## Another controller spoke to one of our aircraft. An honest controller corrects
## anything unsafe straight away and calls the other controller out.
func _on_other_controller(m: Dictionary) -> void:
	if not honest:
		return
	var p := _plan_of_cs(String(m.get("to", "")))
	if p == null or p.stage in ["new", "done"]:
		return
	var tg := _target(p.cs)
	if tg.is_empty():
		return
	var why := unsafe_reason(m, tg)
	if why == "":
		return
	var items: Array = [Datalink.item("disregard")]
	var h := _route_hdg(p, tg) if p.stage == "vector" else (p.hdg if p.hdg > 0 else -1)
	if h > 0:
		items.append(Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)))
	if p.stage != "final":
		items.append(Datalink.alt(_route_alt(p, tg) if p.stage == "vector" else maxi(p.alt, p.level)))
	items.append(Datalink.qnh(sim.qnh))
	p.said_t = -1000.0
	_send_clr(p, items)
	var other := int(m.get("from", 0))
	if _t - float(_accused.get(other, -1000.0)) >= ACCUSE_REPEAT_S:
		_accused[other] = _t
		_say(Datalink.radio_call("accuse", other))


## Why a clearance to the aircraft at `tg` would endanger it, or "".
func unsafe_reason(m: Dictionary, tg: Dictionary) -> String:
	var x := float(tg["x"])
	var y := float(tg["y"])
	var established := _established(tg)
	var a := Datalink.find_item(m, "alt")
	if not a.is_empty() and not established and float(a["v"]) < Geo.msa_at(world, x, y):
		return "msa"
	var q := Datalink.find_item(m, "qnh")
	if not q.is_empty() and int(q["v"]) != sim.qnh:
		return "qnh"
	var h := Datalink.find_item(m, "hdg")
	if not h.is_empty() and not established:
		var alt_ft := float(tg["alt"])
		if not a.is_empty():
			alt_ft = minf(alt_ft, float(a["v"]))
		if AiPilot.heading_hits_terrain(world, x, y, float(h["v"]), alt_ft):
			return "terrain"
		# Pointed well away from the field while far out: burning their fuel.
		var home := Geo.bearing(x, y, 0.0, 0.0)
		if Geo.hypot(x, y) > 15.0 and absf(Geo.angle_diff(home, float(h["v"]))) > 120.0:
			return "away"
	if Datalink.has_item(m, "orbit") and not Datalink.has_item(m, "traffic"):
		return "orbit"
	if Datalink.has_item(m, "cancel") or (Datalink.has_item(m, "ga") and established and Geo.hypot(x, y) > 3.0):
		return "cancel"
	return ""


# ---------------------------------------------------------------- the work

func _work(p: Plan, tg: Dictionary, all: Array) -> void:
	if bool(tg.get("msaw", false)) and p.stage != "final" and _t - p.msaw_t >= MSAW_REPEAT_S:
		p.msaw_t = _t
		var need := maxi(safe_alt(float(tg["x"]), float(tg["y"])), maxi(p.alt, 0))
		_send_clr(p, [Datalink.item("low_alt"), Datalink.alt(need), Datalink.qnh(sim.qnh)])
		return
	if _traffic(p, tg, all):
		return
	match p.stage:
		"new":
			_first_contact(p, tg)
		"vector":
			_vector(p, tg, all)
		"cleared":
			_cleared_stage(p, tg)
		"final":
			_final(p, tg)
		"missed":
			_missed(p, tg)


func _first_contact(p: Plan, tg: Dictionary) -> void:
	if _t - _contact_t < FIRST_CONTACT_GAP_S:
		return
	if not p.priority and priority_cs != "" and plans.has(priority_cs) and (plans[priority_cs] as Plan).stage == "new":
		return
	_contact_t = _t
	_plan(p, tg)
	p.stage = "vector"
	var h := _route_hdg(p, tg)
	_send_clr(p, _contact_items(p, tg, h, _route_alt(p, tg)))


## First contact: radar contact and the ATIS, the first vector and altitude, the QNH.
func _contact_items(_p: Plan, tg: Dictionary, h: int, a: int) -> Array:
	return [
		Datalink.item("contact"), Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)),
		Datalink.alt(a), Datalink.qnh(sim.qnh), Datalink.item("expect"),
	]


func _vector(p: Plan, tg: Dictionary, all: Array) -> void:
	var x := float(tg["x"])
	var y := float(tg["y"])
	if p.orbit_until > _t or p.avoid_until > _t:
		return
	var turned := false
	if p.orbit_until > 0.0:
		p.orbit_until = -1.0
		p.hdg = -1
	var target := p.wps[p.wp]
	var d := Geo.dist(x, y, target.x, target.y)
	var passed := d < WP_RADIUS_NM or (d < WP_PASS_NM and d > p.last_d + 0.05)
	p.last_d = d
	if passed:
		p.last_d = INF
		if p.wp + 1 < p.wps.size():
			p.wp += 1
			turned = true
		else:
			_at_gate(p, tg, all)
			return
	var a := _route_alt(p, tg)
	var h := _route_hdg(p, tg)
	var items: Array = []
	if a != p.alt:
		items.append(Datalink.alt(a))
	if p.hdg < 0 or turned or absf(Geo.angle_diff(float(p.hdg), float(h))) >= HDG_REISSUE_DEG:
		items.append(Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)))
	if not items.is_empty():
		if turned or p.hdg < 0 or _t - p.said_t >= GAP_S:
			if p.alt < 0 and a <= 6000:
				items.append(Datalink.qnh(sim.qnh))
			_send_clr(p, items)
		return
	_compliance(p, tg)


## At the gate: turn onto the intercept and clear the approach, unless it would
## arrive on top of someone (then a 360 for AI traffic; the priority aircraft goes).
func _at_gate(p: Plan, tg: Dictionary, all: Array) -> void:
	if not p.priority and not _spacing_ok(p, all):
		var away := "L" if p.side > 0 else "R"
		p.orbit_until = _t + ORBIT_S
		_send_clr(p, [Datalink.orbit(away)])
		p.wp = p.wps.size() - 1
		p.last_d = INF
		return
	var h := _intercept_hdg(p.side)
	p.stage = "cleared"
	var items: Array = [Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)), Datalink.alt(p.level),
		Datalink.item("app")]
	if p.spd < 0 or p.spd > 180:
		items.append(Datalink.spd(180))
	_send_clr(p, items)


func _cleared_stage(p: Plan, tg: Dictionary) -> void:
	var x := float(tg["x"])
	var y := float(tg["y"])
	if _established(tg):
		p.stage = "final"
		return
	# Missed the localizer: through it by a mile and a half, or past the intercept point.
	if (p.side > 0 and y < -1.5) or (p.side < 0 and y > 1.5) or x < p.d_int - 6.0:
		_revector(p, tg, [Datalink.item("cancel")])
		return
	_compliance(p, tg)


func _final(p: Plan, tg: Dictionary) -> void:
	var x := float(tg["x"])
	var y := float(tg["y"])
	var d := Geo.hypot(x, y)
	if x < -0.3:
		_go_missed(p, tg, false)
		return
	if absf(y) > 1.2:
		_revector(p, tg, [Datalink.item("cancel")])
		return
	# High on the approach close in: it will never capture the glideslope.
	if d < 5.0 and float(tg["alt"]) > Geo.glidepath_alt(world, d) + 700.0:
		_go_missed(p, tg, true)
		return
	# No speed control on final: the landing speed (155 kt or less) is the pilot's.
	if not p.land_cleared and d < LAND_CLEAR_NM:
		p.land_cleared = true
		_send_clr(p, [Datalink.item("land")])


func _go_missed(p: Plan, _tg: Dictionary, order_ga: bool) -> void:
	p.stage = "missed"
	p.land_cleared = false
	p.orbit_until = -1.0
	if order_ga:
		_send_clr(p, [Datalink.item("ga")])
	else:
		_send_clr(p, [Datalink.hdg(60, "R"), Datalink.alt(6000)])
	p.hdg = 60
	p.alt = 6000


## Climbing out on the missed approach: once clear of the field, a new arrival from the north.
func _missed(p: Plan, tg: Dictionary) -> void:
	if float(tg["alt"]) < 2800.0 and float(tg["x"]) < 2.0:
		return
	p.side = 1
	p.level = _base_level(1)
	_geometry(p)
	p.stage = "vector"
	p.hdg = -1
	p.said_t = -1000.0


func _revector(p: Plan, tg: Dictionary, prefix: Array) -> void:
	p.side = 1 if float(tg["y"]) >= 0.0 else -1
	p.level = maxi(_base_level(p.side), p.level)
	_geometry(p)
	p.stage = "vector"
	p.land_cleared = false
	var items: Array = prefix.duplicate()
	var h := _route_hdg(p, tg)
	items.append(Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)))
	items.append(Datalink.alt(_route_alt(p, tg)))
	_send_clr(p, items)


## The pilot has not done what we said: say it again (a different QNH shows as a
## level aircraft sitting a few hundred feet off its altitude).
## Repeats back off (45, 90, 180 s...) so an aircraft that never answers is not nagged.
func _compliance(p: Plan, tg: Dictionary) -> void:
	var wait := REPEAT_S * float(1 << mini(p.repeats, 3))
	if _t - p.said_t < wait:
		return
	if p.hdg > 0 and _t - p.hdg_t >= REPEAT_S and absf(Geo.angle_diff(float(tg["track"]), float(p.hdg))) > 20.0:
		_send_clr(p, [Datalink.hdg(p.hdg, Datalink.turn_dir(float(tg["track"]), p.hdg))], true)
		return
	if p.alt > 0 and p.stage != "final" and int(tg["vs_trend"]) == 0 and _t - p.alt_t >= REPEAT_S:
		var off := absf(float(tg["alt"]) - float(p.alt))
		p.alt_off_n = p.alt_off_n + 1 if off >= ALT_OFF_FT else 0
		if p.alt_off_n >= 3:
			p.alt_off_n = 0
			_send_clr(p, [Datalink.alt(p.alt), Datalink.qnh(sim.qnh)], true)


## Two aircraft about to meet: turn and climb the one we can move.
func _traffic(p: Plan, tg: Dictionary, all: Array) -> bool:
	if _t - p.traffic_t < TRAFFIC_REPEAT_S or p.stage in ["final", "new"]:
		return false
	for o: Dictionary in all:
		if String(o["callsign"]) == p.cs or String(o["status"]) != "flying":
			continue
		if not _converging(tg, o):
			continue
		var op: Plan = plans.get(String(o["callsign"]), null)
		# Move the one that is not the priority aircraft, and not the one on final.
		if p.priority and op != null and not op.priority and op.stage != "final":
			continue
		p.traffic_t = _t
		p.avoid_until = _t + 40.0
		var away := Geo.norm360(Geo.bearing(float(o["x"]), float(o["y"]), float(tg["x"]), float(tg["y"])))
		var h := _round_hdg(away)
		var a := mini(maxi(p.alt, int(float(tg["alt"]) / 100.0) * 100) + 1000, LEVEL_MAX)
		if p.stage == "cleared":
			p.stage = "vector"
		p.level = maxi(p.level, a)
		_geometry(p)
		_send_clr(p, [Datalink.item("traffic"), Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)),
			Datalink.alt(a)])
		return true
	return false


static func _converging(a: Dictionary, b: Dictionary) -> bool:
	var ax := float(a["x"])
	var ay := float(a["y"])
	var bx := float(b["x"])
	var by := float(b["y"])
	var avx := Geo.heading_dx(float(a["track"])) * float(a["gs"]) / 3600.0
	var avy := Geo.heading_dy(float(a["track"])) * float(a["gs"]) / 3600.0
	var bvx := Geo.heading_dx(float(b["track"])) * float(b["gs"]) / 3600.0
	var bvy := Geo.heading_dy(float(b["track"])) * float(b["gs"]) / 3600.0
	var t := 0.0
	while t <= TRAFFIC_LOOK_S:
		var dx := (ax + avx * t) - (bx + bvx * t)
		var dy := (ay + avy * t) - (by + bvy * t)
		if Geo.hypot(dx, dy) < TRAFFIC_NM:
			var dz := (float(a["alt"]) + int(a["vs_trend"]) * 25.0 * t) - (float(b["alt"]) + int(b["vs_trend"]) * 25.0 * t)
			if absf(dz) < TRAFFIC_FT:
				return true
		t += 5.0
	return false


func _spacing_ok(p: Plan, all: Array) -> bool:
	var mine := _gate_leg + p.d_int
	for o: Dictionary in all:
		var cs := String(o["callsign"])
		if cs == p.cs or String(o["status"]) != "flying" or not plans.has(cs):
			continue
		var op: Plan = plans[cs]
		var theirs := -1.0
		var ox := float(o["x"])
		var oy := float(o["y"])
		match op.stage:
			"final":
				theirs = Geo.hypot(ox, oy)
			"cleared":
				theirs = Geo.dist(ox, oy, op.d_int, 0.0) + op.d_int
			"vector":
				if op.priority and not op.wps.is_empty():
					theirs = Geo.dist(ox, oy, op.gate.x, op.gate.y) + _gate_leg + op.d_int
		if theirs >= 0.0 and absf(theirs - mine) < SPACING_NM:
			return false
	return true


# ---------------------------------------------------------------- geometry

func _plan(p: Plan, tg: Dictionary) -> void:
	p.side = 1 if float(tg["y"]) >= 0.0 else -1
	var busy := 0
	for cs: String in plans:
		var o: Plan = plans[cs]
		if o != p and o.side == p.side and o.stage == "vector":
			busy += 1
	p.level = mini(_base_level(p.side) + 1000 * busy, LEVEL_MAX)
	_geometry(p)
	# Coming from the east: straight to the gate. Otherwise round by the base point.
	if float(tg["x"]) > p.gate.x + 1.0:
		p.wp = p.wps.size() - 1


func _geometry(p: Plan) -> void:
	p.d_int = clampf(_gs_dist(p.level) + GS_MARGIN_NM, D_INT_MIN, D_INT_MAX)
	var h := float(_intercept_hdg(p.side))
	p.gate = Vector2(p.d_int - _gate_leg * Geo.heading_dx(h), -_gate_leg * Geo.heading_dy(h))
	var base := p.gate + Vector2(0.0, p.side * BASE_LEG_NM)
	p.wps = [base, p.gate]
	p.wp = 0
	p.last_d = INF


static func _intercept_hdg(side: int) -> int:
	return 240 if side > 0 else 300


## Distance from the threshold where the glideslope passes `alt_ft`.
func _gs_dist(alt_ft: int) -> float:
	return (float(alt_ft) - world.field_elev - world.tch) / (Geo.FT_PER_NM * tan(world.glide_deg * Geo.DEG))


## The side's lowest intercept altitude: its MSA sector rounded up to 500 ft.
func _base_level(side: int) -> int:
	var brg := 45.0 if side > 0 else 135.0
	return _round_up(Geo.msa_at(world, Geo.heading_dx(brg) * 10.0, Geo.heading_dy(brg) * 10.0))


## Lowest altitude we give at a point: its sector MSA rounded up to 500 ft.
func safe_alt(x: float, y: float) -> int:
	return _round_up(Geo.msa_at(world, x, y))


static func _round_up(msa: float) -> int:
	return int(ceil((msa + 100.0) / 500.0)) * 500


func _route_alt(p: Plan, tg: Dictionary) -> int:
	var nx := p.wps[p.wp]
	return maxi(p.level, maxi(safe_alt(float(tg["x"]), float(tg["y"])), safe_alt(nx.x, nx.y)))


func _route_hdg(p: Plan, tg: Dictionary) -> int:
	var nx := p.wps[p.wp]
	return _round_hdg(Geo.bearing(float(tg["x"]), float(tg["y"]), nx.x, nx.y))


static func _round_hdg(h: float) -> int:
	return Datalink.norm_hdg(int(Geo.js_round(h / HDG_ROUND)) * HDG_ROUND)


static func _established(tg: Dictionary) -> bool:
	return absf(float(tg["y"])) < 0.35 and absf(Geo.angle_diff(float(tg["track"]), 270.0)) < 20.0 and float(tg["x"]) > 0.3


func _target(cs: String) -> Dictionary:
	for tg in sim.radar():
		if String(tg["callsign"]) == cs:
			return tg
	return {}


# ---------------------------------------------------------------- talking

## Say a clearance. When the frequency queue is full it is kept and said at the next
## think: stages move on as soon as an instruction is decided, so none may be lost.
func _send_clr(p: Plan, items: Array, repeat: bool = false) -> void:
	var msg := Datalink.clr(p.cs, items)
	var err: Variant = send.call(id, msg)
	if err is String and String(err) != "":
		if String(err).begins_with("Frequency busy"):
			p.retry = msg
		return
	spoken += 1
	p.pending += 1
	p.said_t = _t
	p.repeats = p.repeats + 1 if repeat else 0
	for it: Dictionary in items:
		match String(it["t"]):
			"hdg":
				p.hdg = int(it["v"])
				p.hdg_t = _t
			"alt":
				p.alt = int(it["v"])
				p.alt_t = _t
			"spd":
				p.spd = int(it["v"])


## A call to all stations (said again later if the frequency queue is full).
func _say(msg: Dictionary) -> void:
	var err: Variant = send.call(id, msg)
	if err is String and String(err).begins_with("Frequency busy"):
		_calls.append(msg)
	elif not (err is String and String(err) != ""):
		spoken += 1
