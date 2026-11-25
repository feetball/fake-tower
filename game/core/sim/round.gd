extends RefCounted
## A round: spawn the pilots' aircraft, step the world, detect outcomes, and
## produce the pilot and controller views plus the final result.
## Port of src/shared/sim/round.ts (same constants, rules and RNG call order).

const Geo := preload("res://core/sim/geo.gd")
const SimRng := preload("res://core/sim/rng.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")
const SimAircraft := preload("res://core/sim/aircraft.gd")
const SimAtis := preload("res://core/sim/atis.gd")
const WorldDef := preload("res://core/world.gd")

const COLLISION_NM := 0.15
const COLLISION_FT := 200.0
const SPAWN_LATERAL_NM := 5.0 ## margin above the 3 nm minimum at t=0
const SPAWN_LEVELS: Array[int] = [7000, 8000, 9000, 10000] ## indicated with 1013 set
const AIRLINES: Array[String] = ["SKW", "DAL", "UAL", "AAL", "ASA", "JBU", "SWA", "FFT", "ENY", "RPA", "NKS", "QXE"]
const GATES: Array[String] = ["NORBY", "SOLEY", "EASTO", "WHISK"]

var world: SimWorld
var world_dict: Dictionary
var qnh := 0
var atis: Dictionary
var aircraft: Array[SimAircraft] = []
var time := 0.0
var _events: Array[Dictionary] = []


## pilot_ids: one spawned aircraft each, unless `inits` places aircraft explicitly (tests, demos).
## qnh 0 = random. world_data defaults to World.DATA.
func _init(rng: SimRng, pilot_ids: Array[int] = [], qnh_override: int = 0,
		inits: Array[Dictionary] = [], world_data: Dictionary = {}) -> void:
	world_dict = WorldDef.DATA if world_data.is_empty() else world_data
	world = SimWorld.from_dict(world_dict)
	qnh = qnh_override if qnh_override > 0 else SimAtis.random_qnh(rng)
	atis = SimAtis.make_atis(world, qnh, rng)
	var list := inits if not inits.is_empty() else _spawn(pilot_ids, rng)
	for i in list:
		aircraft.append(SimAircraft.new(i, qnh))
	for ac in aircraft:
		ac.update_warnings(world)


## Fuel for a "competent direct approach": direct to the intermediate fix at
## ~220 kt average groundspeed, then the final from there at ~150 kt.
static func direct_approach_minutes(w: SimWorld, x: float, y: float) -> float:
	var i := w.fix_index("RIDGE")
	var ix := w.fix_x[i] if i >= 0 else 14.0
	var iy := w.fix_y[i] if i >= 0 else 0.0
	var final_nm := Geo.hypot(ix, iy)
	return (Geo.dist(x, y, ix, iy) / 220.0) * 60.0 + (final_nm / 150.0) * 60.0


## Init Dictionary for SimAircraft (the only place spawn keys are written).
static func make_init(callsign: String, player_id: int, x: float, y: float, alt: float,
		hdg: float, ias: float, fuel_min: float) -> Dictionary:
	return {
		"callsign": callsign, "player_id": player_id, "x": x, "y": y, "alt": alt,
		"hdg": hdg, "ias": ias, "fuel_min": fuel_min,
	}


func _spawn(pilot_ids: Array[int], rng: SimRng) -> Array[Dictionary]:
	var gate_idx: Array[int] = []
	for n: Variant in rng.shuffle(GATES):
		var fi := world.fix_index(String(n))
		if fi >= 0:
			gate_idx.append(fi)
	var used: Dictionary = {}
	var out: Array[Dictionary] = []
	for i in pilot_ids.size():
		var callsign := ""
		while true:
			callsign = String(rng.pick(AIRLINES)) + str(rng.rand_int(100, 2999))
			if not used.has(callsign):
				break
		used[callsign] = true
		var placed := false
		for attempt in 1000:
			# Prefer spreading across gates; fall back to any gate if one fills up.
			var g: int = gate_idx[i % gate_idx.size()] if attempt < 200 else int(rng.pick(gate_idx))
			var r := rng.rand_range(25.0, 35.0)
			var brg := Geo.bearing(0.0, 0.0, world.fix_x[g], world.fix_y[g]) + rng.rand_range(-6.0, 6.0)
			var x := Geo.heading_dx(brg) * r
			var y := Geo.heading_dy(brg) * r
			var level: int = rng.pick(SPAWN_LEVELS)
			var alt := float(level) - float(1013 - qnh) * 27.0 # true altitude for that pressure level
			var separated := true
			for o in out:
				if not (Geo.dist(x, y, o["x"], o["y"]) >= SPAWN_LATERAL_NM or absf(alt - float(o["alt"])) >= 1000.0):
					separated = false
					break
			if not separated or alt <= Geo.msa_at(world, x, y) + 500.0:
				continue
			var hdg := Geo.bearing(x, y, 0.0, 0.0) + rng.rand_range(-10.0, 10.0)
			var fuel := Geo.js_round((direct_approach_minutes(world, x, y) + rng.rand_range(8.0, 14.0)) * 10.0) / 10.0
			var init := make_init(callsign, pilot_ids[i], x, y, alt, hdg, 250.0, fuel)
			init["sel_alt"] = level
			var probe := SimAircraft.new(init, qnh)
			probe.update_warnings(world)
			if not probe.warnings.is_empty():
				continue
			out.append(init)
			placed = true
			break
		if not placed:
			push_error("could not find a separated spawn")
	return out


func by_player(player_id: int) -> SimAircraft:
	for ac in aircraft:
		if ac.player_id == player_id:
			return ac
	return null


func by_callsign(cs: String) -> SimAircraft:
	for ac in aircraft:
		if ac.callsign == cs:
			return ac
	return null


## Apply an autopilot command from a pilot. Returns false if they have no flying aircraft.
func apply_ap(player_id: int, cmd: Dictionary) -> bool:
	var ac := by_player(player_id)
	if ac == null or not ac.is_flying():
		return false
	ac.apply(cmd)
	return true


func is_finished() -> bool:
	for ac in aircraft:
		if ac.is_flying():
			return false
	return true


static func make_event(t: float, kind: String, callsigns: Array[String]) -> Dictionary:
	var cs: Array = []
	cs.append_array(callsigns)
	return {"time": t, "kind": kind, "callsigns": cs}


## Advance the world. Returns the events that happened during this step.
func step(dt: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_finished():
		return out
	time += dt
	var t := Geo.js_round(time * 10.0) / 10.0
	var flying: Array[SimAircraft] = []
	for ac in aircraft:
		if ac.is_flying():
			flying.append(ac)
		else:
			ac.animate_landed(dt, world)
	for ac in flying:
		var o := ac.step(dt, world, qnh)
		if o != "":
			out.append(make_event(t, o, [ac.callsign]))
	var still: Array[SimAircraft] = []
	for ac in flying:
		if ac.is_flying():
			still.append(ac)
	var collided: Array[SimAircraft] = []
	for i in still.size():
		for j in range(i + 1, still.size()):
			var a := still[i]
			var b := still[j]
			if Geo.dist(a.x, a.y, b.x, b.y) < COLLISION_NM and absf(a.alt - b.alt) < COLLISION_FT:
				if not collided.has(a):
					collided.append(a)
				if not collided.has(b):
					collided.append(b)
	if not collided.is_empty():
		var names: Array[String] = []
		for ac in collided:
			ac.finish("collision")
			names.append(ac.callsign)
		out.append(make_event(t, "collision", names))
	for ac in aircraft:
		ac.update_warnings(world)
	_events.append_array(out)
	return out


## The contract `own` view for a player's aircraft, or {} if they have none.
func own_view(player_id: int) -> Dictionary:
	var ac := by_player(player_id)
	if ac == null:
		return {}
	var v := ac.own_view(world, qnh)
	v["time"] = Geo.js_round(time * 10.0) / 10.0
	return v


## MSAW: flying, not established on the localizer/ILS, and below the sector MSA.
func msaw(ac: SimAircraft) -> bool:
	return ac.is_flying() and not ac.loc_captured and ac.alt < Geo.msa_at(world, ac.x, ac.y)


func conflict(ac: SimAircraft) -> bool:
	if not ac.is_flying():
		return false
	for o in aircraft:
		if o != ac and o.is_flying() and Geo.dist(ac.x, ac.y, o.x, o.y) < world.sep_lateral_nm \
				and absf(ac.alt - o.alt) < world.sep_vertical_ft:
			return true
	return false


func radar() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ac in aircraft:
		out.append(ac.radar_view(conflict(ac), msaw(ac)))
	return out


func all_events() -> Array[Dictionary]:
	return _events


## Tower wins if strictly more than half of the aircraft landed.
static func winner(outcomes: Array[String]) -> String:
	var landed := outcomes.count("landed")
	return "tower" if landed * 2 > outcomes.size() else "impostor"


## The contract `result` shape. Ids are 0 when the role does not exist.
func result(real_controller_id: int, impostor_id: int) -> Dictionary:
	var outcomes: Array = []
	var kinds: Array[String] = []
	for ac in aircraft:
		outcomes.append({"callsign": ac.callsign, "player_id": ac.player_id, "outcome": ac.outcome})
		kinds.append(ac.outcome)
	return {
		"winner": winner(kinds),
		"real_controller_id": real_controller_id,
		"impostor_id": impostor_id,
		"outcomes": outcomes,
		"duration_sec": int(Geo.js_round(time)),
	}
