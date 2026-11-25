extends RefCounted
## Offline demo rounds: the real sim with scripted AI pilots (see demo_ai.gd).
##   "controller": you are the real tower; 4 AI aircraft arrive staggered (one is
##                 on final at the start, one descends early and trips MSAW).
##   "pilot":      you fly one aircraft established on a 12 nm final at the
##                 platform altitude (APP armed, flaps 1, 180 kt); 2 AI behind you.
##   "pilot_far":  you are spawned normally at an arrival gate; 2 AI spawned too.

const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const Room := preload("res://core/net/room.gd")
const DemoAi := preload("res://core/net/demo_ai.gd")

const Self := preload("res://core/net/demo.gd")
const ROLES: Array[String] = ["controller", "pilot", "pilot_far"]

var sim: SimRound
var roles: Room.Roles
var ai: Array[DemoAi] = []
## AI player id (negative) -> display name.
var ai_names: Dictionary = {}


func tick() -> void:
	for p in ai:
		p.tick(Room.DT)


static func ai_id(i: int) -> int:
	return -1 - i


## Build the demo for `role` with the local player `me`. Returns null for an unknown role.
static func build(role: String, me: int, rng: SimRng) -> Self:
	if not ROLES.has(role):
		return null
	var d := Self.new()
	d._build(role, me, rng)
	return d


func _build(role: String, me: int, rng: SimRng) -> void:
	roles = Room.Roles.new()
	match role:
		"controller":
			roles.real_controller_id = me
			var inits: Array[Dictionary] = [
				_init_ac("SKW412", 0, 15.0, 0.3, 4600.0, 265.0, 190.0, 30.0),
				_init_ac("ASA277", 1, 27.0, 14.0, 7000.0, 200.0, 250.0, 35.0),
				_init_ac("DAL1873", 2, 21.0, -24.0, 8000.0, 340.0, 250.0, 40.0),
				_init_ac("UAL905", 3, 22.0, 29.0, 9000.0, 180.0, 250.0, 45.0),
			]
			inits[0]["flaps"] = 1
			sim = SimRound.new(rng, [], 0, inits)
			for i in 4:
				roles.pilots.append(ai_id(i))
			_add_ai(0, [], 270.0, 3000, 0.0)
			# Descends to 3000 long before the localizer: MSAW until established.
			_add_ai(1, [Vector3(30, 6, 3000)], 240.0, 3000, 0.0)
			_add_ai(2, [Vector3(26, -7, 4500)], 300.0, 4500, 0.0)
			_add_ai(3, [Vector3(31, 14, 7000), Vector3(31, 7, 5500)], 240.0, 5500, 90.0)
		"pilot":
			var mine := _init_ac("N12FT", 0, 12.0, 0.0, 3000.0, 270.0, 180.0, 25.0)
			mine["player_id"] = me
			mine["flaps"] = 1
			var inits: Array[Dictionary] = [
				mine,
				_init_ac("DAL1873", 0, 21.0, -24.0, 8000.0, 340.0, 250.0, 40.0),
				_init_ac("UAL905", 1, 22.0, 29.0, 9000.0, 180.0, 250.0, 45.0),
			]
			sim = SimRound.new(rng, [], 0, inits)
			var own := sim.by_player(me)
			own.apply({"alt_setting": sim.qnh, "alt": 3000, "app": true})
			roles.pilots.append_array([me, ai_id(0), ai_id(1)])
			_add_ai(0, [Vector3(26, -7, 4500)], 300.0, 4500, 60.0)
			_add_ai(1, [Vector3(31, 14, 7000), Vector3(31, 7, 5500)], 240.0, 5500, 120.0)
		"pilot_far":
			var ids: Array[int] = [me, ai_id(0), ai_id(1)]
			sim = SimRound.new(rng, ids)
			roles.pilots.append_array(ids)
			for i in 2:
				var ac := sim.by_player(ai_id(i))
				var side := 1.0 if ac.y >= 0.0 else -1.0
				var alt := 5500 if side > 0.0 else 4500
				_add_ai(i, [Vector3(30, 7 * side, 6000), Vector3(30, 6 * side, alt)],
					240.0 if side > 0.0 else 300.0, alt, 150.0 * i)


static func _init_ac(cs: String, idx: int, x: float, y: float, alt: float, hdg: float, ias: float, fuel: float) -> Dictionary:
	return SimRound.make_init(cs, ai_id(idx), x, y, alt, hdg, ias, fuel)


func _add_ai(idx: int, route: Array[Vector3], hdg: float, alt: int, delay: float) -> void:
	var ac := sim.by_player(ai_id(idx))
	var p := DemoAi.new(ac, sim.qnh)
	p.route = route
	p.intercept_hdg = hdg
	p.intercept_alt = alt
	p.delay_s = delay
	ai.append(p)
	ai_names[ai_id(idx)] = "AI " + ac.callsign
