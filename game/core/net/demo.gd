extends RefCounted
## Offline demo rounds: the real sim with AI players.
## Scripted AI pilots (demo_ai.gd), for development, screenshots and tests:
##   "controller": you are the real tower; 4 AI aircraft arrive staggered (one is
##                 on final at the start, one descends early and trips MSAW).
##   "pilot":      you fly one aircraft established on a 12 nm final at the
##                 platform altitude (APP armed, flaps 1, 180 kt); 2 AI behind you.
##   "pilot_far":  you are spawned normally at an arrival gate; 2 AI spawned too.
## Solo practice on the text radio (core/net/datalink.gd), AI players that talk:
##   "solo":            you fly from an arrival gate; an AI approach controller
##                      (ai_controller.gd) works you and 2 AI pilots (ai_pilot.gd).
##   "solo_impostor":   you and 1 AI pilot; two AI controllers on frequency, one of
##                      them the impostor (ai_impostor.gd) out to get you.
##   "solo_controller": you are the real tower; 4 AI pilots fly by your clearances.
## attach() wires the AI players' mouths to Room.handle_dl; hear() is their ears.

const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const Room := preload("res://core/net/room.gd")
const DemoAi := preload("res://core/net/demo_ai.gd")
const AiPilot := preload("res://core/net/ai_pilot.gd")
const AiController := preload("res://core/net/ai_controller.gd")
const AiImpostor := preload("res://core/net/ai_impostor.gd")

const Self := preload("res://core/net/demo.gd")
const ROLES: Array[String] = ["controller", "pilot", "pilot_far", "solo", "solo_impostor", "solo_controller"]
const AI_TOWER_NAME := "Approach (AI)"
const DUEL_NAMES: Array[String] = ["Controller A", "Controller B"]

var role := ""
var sim: SimRound
var roles: Room.Roles
var ai: Array[DemoAi] = []
var pilots: Array[AiPilot] = []
var controllers: Array[AiController] = []
## The impostor in "solo_impostor" (also in `controllers`), else null.
var impostor: AiImpostor = null
## AI player id (negative) -> display name.
var ai_names: Dictionary = {}
var _send := Callable()


func tick() -> void:
	for p in ai:
		p.tick(Room.DT)
	for p in pilots:
		p.tick(Room.DT, _forward)
	for c in controllers:
		c.tick(Room.DT)


## Every aired text message (Room.dl_hook).
func hear(m: Dictionary) -> void:
	for p in pilots:
		p.hear(m)
	for c in controllers:
		c.hear(m)


## Where the AI players' messages go: (from_id, msg) -> error, i.e. Room.handle_dl.
func attach(send: Callable) -> void:
	_send = send


func _forward(from_id: int, msg: Dictionary) -> String:
	if not _send.is_valid():
		return "No room"
	return String(_send.call(from_id, msg))


static func ai_id(i: int) -> int:
	return -1 - i


## Build the demo for `role` with the local player `me`. Returns null for an unknown role.
static func build(demo_role: String, me: int, rng: SimRng) -> Self:
	if not ROLES.has(demo_role):
		return null
	var d := Self.new()
	d.role = demo_role
	d._build(demo_role, me, rng)
	return d


func _build(demo_role: String, me: int, rng: SimRng) -> void:
	roles = Room.Roles.new()
	match demo_role:
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
		"solo":
			var ids: Array[int] = [me, ai_id(0), ai_id(1)]
			sim = SimRound.new(rng, ids)
			roles.pilots.append_array(ids)
			roles.real_controller_id = ai_id(2)
			for i in 2:
				_add_pilot(ai_id(i), [], 3.0 + 5.0 * i)
			_add_controller(ai_id(2), AI_TOWER_NAME, sim.by_player(me).callsign)
		"solo_impostor":
			var ids: Array[int] = [me, ai_id(0)]
			sim = SimRound.new(rng, ids)
			roles.pilots.append_array(ids)
			# Which id is real, which name it gets and who speaks first are all random, so
			# neither the roster order (colours, call-out buttons) nor the order of the
			# read-aloud voices gives the impostor away.
			var real_id := ai_id(1) if rng.rand_int(0, 1) == 0 else ai_id(2)
			var imp_id := ai_id(1) + ai_id(2) - real_id
			var real_name := rng.rand_int(0, 1)
			roles.real_controller_id = real_id
			roles.impostor_id = imp_id
			var mine := sim.by_player(me).callsign
			var obey: Array[int] = [real_id]
			var traffic := _add_pilot(ai_id(0), obey, 3.0)
			# It reads back both controllers (as a pilot who cannot tell either would) but
			# flies only the real one's instructions: the impostor talks to it too.
			traffic.ack_others = true
			var real := AiController.new(real_id, sim, _forward)
			real.priority_cs = mine
			impostor = AiImpostor.new(imp_id, sim, _forward, mine, rng)
			for id in [ai_id(1), ai_id(2)]:
				ai_names[id] = DUEL_NAMES[real_name if id == real_id else 1 - real_name]
			if rng.rand_int(0, 1) == 0:
				controllers.append_array([real, impostor])
			else:
				controllers.append_array([impostor, real])
		"solo_controller":
			var ids: Array[int] = []
			for i in 4:
				ids.append(ai_id(i))
			sim = SimRound.new(rng, ids)
			roles.pilots.append_array(ids)
			roles.real_controller_id = me
			var obey: Array[int] = [me]
			for i in 4:
				_add_pilot(ai_id(i), obey, 4.0 + 7.0 * i)


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


func _add_pilot(pid: int, obey: Array[int], checkin_at: float) -> AiPilot:
	var ac := sim.by_player(pid)
	var p := AiPilot.new(pid, ac, sim.world, sim.qnh)
	p.obey = obey
	p.checkin_at = checkin_at
	pilots.append(p)
	ai_names[pid] = "AI " + ac.callsign
	return p


func _add_controller(cid: int, display: String, priority_cs: String) -> AiController:
	var c := AiController.new(cid, sim, _forward)
	c.priority_cs = priority_cs
	controllers.append(c)
	ai_names[cid] = display
	return c
