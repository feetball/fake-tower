extends RefCounted
## AI players on the text radio: the AI pilot on its own, then whole solo rounds
## (core/net/demo.gd) played to the end with a stand-in for the human: an AI pilot
## that obeys everyone, only the real controller, only the impostor, or nobody;
## in "solo_controller" an AI controller sitting in the human's chair.

const T := preload("res://tests/lib/t.gd")
const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const Room := preload("res://core/net/room.gd")
const Demo := preload("res://core/net/demo.gd")
const Datalink := preload("res://core/net/datalink.gd")
const AiPilot := preload("res://core/net/ai_pilot.gd")
const AiController := preload("res://core/net/ai_controller.gd")
const ME := 1


## Play `role` to the end. human: "obey" | "obey_real" | "gullible_impostor" | "none" | "ai_tower".
## Returns {outcomes: {cs: outcome}, mine: my outcome, winner, log: [aired messages], demo}.
func play(role: String, seed_v: int, human: String) -> Dictionary:
	var rng := SimRng.new(seed_v)
	var d := Demo.build(role, ME, rng)
	var room := Room.new(func(_to: int, _k: String, _p: Dictionary) -> void: pass, rng, 1)
	room.add(ME, "Me")
	for id: int in d.ai_names:
		room.add(id, d.ai_names[id])
	var log: Array[Dictionary] = []
	var stand: Array = [] # lambdas capture by value: fill the array after creating it
	room.ai_hook = d.tick
	room.dl_hook = func(m: Dictionary) -> void:
		d.hear(m)
		for s: Variant in stand:
			s.hear(m)
		if String(m["status"]) == "ok":
			log.append(m)
	d.attach(room.handle_dl)
	var me := d.sim.by_player(ME)
	if me != null and human != "none":
		var p := AiPilot.new(ME, me, d.sim.world, d.sim.qnh)
		p.checkin_at = -1.0
		match human:
			"obey_real":
				p.obey = [d.roles.real_controller_id] as Array[int]
			"gullible_impostor":
				p.obey = [d.roles.impostor_id] as Array[int]
				p.careful = false
		stand.append(p)
	if human == "ai_tower":
		stand.append(AiController.new(ME, d.sim, room.handle_dl))
	room.begin_round(d.roles, d.sim)
	var n := 0
	while room.phase == "playing" and n < 30000:
		for s: Variant in stand:
			if s is AiPilot:
				(s as AiPilot).tick(Room.DT, room.handle_dl)
			else:
				(s as AiController).tick(Room.DT)
		room.advance(Room.DT)
		n += 1
	var outcomes := {}
	for ac in d.sim.aircraft:
		outcomes[ac.callsign] = ac.outcome
	var res := d.sim.result(d.roles.real_controller_id, d.roles.impostor_id)
	return {"outcomes": outcomes, "mine": me.outcome if me != null else "", "winner": res["winner"],
		"log": log, "demo": d, "ended": room.phase == "ended"}


static func said_by(log: Array[Dictionary], id: int, t: String) -> int:
	var n := 0
	for m in log:
		if int(m["from"]) == id and Datalink.has_item(m, t):
			n += 1
	return n


# ---------------------------------------------------------------- the AI pilot alone

func _lone_pilot(x: float, y: float, alt: float, hdg: float) -> AiPilot:
	var sim := SimRound.new(SimRng.new(3), [], 1009, [SimRound.make_init("TST1", 7, x, y, alt, hdg, 250.0, 30.0)])
	return AiPilot.new(7, sim.by_player(7), sim.world, 1009)


static func _aired(id: int, to: String, items: Array) -> Dictionary:
	var m := Datalink.clr(to, items)
	m.merge({"id": id, "from": -9, "role": "controller", "status": "ok"})
	return m


func test_ai_pilot_follows_and_reads_back(t: T) -> void:
	var p := _lone_pilot(25.0, 10.0, 8000.0, 250.0)
	var said: Array[Dictionary] = []
	var send := func(_from: int, msg: Dictionary) -> String:
		said.append(msg)
		return ""
	p.checkin_at = 0.5
	p.tick(1.0, send)
	t.eq(String(said[0]["items"][0]["t"]), "checkin", "checks in")
	p.hear(_aired(5, "TST1", [Datalink.hdg(200, "L"), Datalink.alt(6000), Datalink.spd(220)]))
	t.eq(p.ac.sel_hdg, 200, "heading")
	t.eq(p.ac.sel_alt, 6000, "altitude")
	t.eq(p.ac.sel_spd, 220, "speed")
	t.eq(p.ac.alt_setting, 1013, "still on standard above the transition altitude")
	p.hear(_aired(6, "TST1", [Datalink.alt(5500)]))
	t.eq(p.ac.alt_setting, 1009, "sets the ATIS QNH descending below 6000")
	p.hear(_aired(7, "OTHER", [Datalink.hdg(90)]))
	t.eq(p.ac.sel_hdg, 200, "ignores other callsigns")
	p.tick(3.0, send)
	var replies := said.filter(func(m: Dictionary) -> bool: return m["kind"] == "reply")
	t.eq(replies.map(func(m: Dictionary) -> int: return int(m["re"])), [5, 6], "WILCO to each, after a pause")
	p.hear(_aired(8, "TST1", [Datalink.hdg(240, "R"), Datalink.alt(5500), Datalink.item("app")]))
	t.check(p.is_cleared() and p.ac.app_armed, "cleared: APP armed")
	t.check(p.ac.flaps >= 1 and p.ac.sel_spd <= 180, "configures for the approach")
	t.done()


func test_ai_pilot_refuses_the_tells(t: T) -> void:
	var p := _lone_pilot(25.0, 10.0, 8000.0, 250.0) # NE sector, MSA 5200
	var said: Array[Dictionary] = []
	var send := func(_from: int, msg: Dictionary) -> String:
		said.append(msg)
		return ""
	p.checkin_at = -1.0
	var alt0 := p.ac.sel_alt
	p.hear(_aired(1, "TST1", [Datalink.alt(3000)]))
	p.hear(_aired(2, "TST1", [Datalink.qnh(1016)]))
	t.eq(p.ac.sel_alt, alt0, "did not descend below the MSA")
	t.eq(p.ac.alt_setting, 1013, "did not set a wrong QNH")
	p.tick(2.0, send)
	# Low over the south, pointed at Saddleback (3, -11), 3400 ft: the heading alone is refused.
	var low := _lone_pilot(12.0, -11.0, 3500.0, 180.0)
	low.checkin_at = -1.0
	low.hear(_aired(3, "TST1", [Datalink.hdg(270, "R")]))
	t.check(low.ac.sel_hdg != 270, "did not turn into the hill")
	low.tick(2.0, send)
	t.eq(said.map(func(m: Dictionary) -> String: return String(m["items"][0].get("why", ""))), ["msa", "qnh", "terrain"],
		"UNABLE with the reason")
	var g := _lone_pilot(25.0, 10.0, 8000.0, 250.0)
	g.careful = false
	g.hear(_aired(1, "TST1", [Datalink.alt(3000), Datalink.qnh(1016)]))
	t.eq(g.ac.sel_alt, 3000, "a gullible pilot does as told")
	var o := _lone_pilot(25.0, 10.0, 8000.0, 250.0)
	o.obey = [4] as Array[int]
	o.hear(_aired(1, "TST1", [Datalink.hdg(90)]))
	t.check(o.ac.sel_hdg != 90, "only listens to the controllers it trusts")
	t.done()


func test_ai_pilot_orbit_and_go_around(t: T) -> void:
	var p := _lone_pilot(25.0, 10.0, 8000.0, 250.0)
	p.talk = false
	p.hear(_aired(1, "TST1", [Datalink.orbit("L")]))
	var turned := 0.0
	var prev := p.ac.hdg
	var sim_world := p.world
	for i in 1400:
		p.tick(0.1, Callable())
		p.ac.step(0.1, sim_world, 1009)
		turned += _turned(prev, p.ac.hdg)
		prev = p.ac.hdg
	t.check(turned < -330.0 and turned > -400.0, "a left 360 (turned %.0f°)" % turned)
	t.near(p.ac.hdg, 250.0, 6.0, "back on the heading it had")
	p.hear(_aired(2, "TST1", [Datalink.item("ga")]))
	t.eq(p.ac.sel_hdg, 60, "above 3000: straight onto the missed approach heading")
	t.eq(p.ac.sel_alt, 6000, "missed approach altitude")
	t.check(not p.ac.app_armed, "approach disarmed")
	t.done()


## Signed degrees turned from heading a to b (shortest way).
static func _turned(a: float, b: float) -> float:
	return fmod(b - a + 540.0, 360.0) - 180.0


# ---------------------------------------------------------------- whole solo rounds

func test_demo_solo_modes_shapes(t: T) -> void:
	var d := Demo.build("solo", ME, SimRng.new(1))
	t.eq(d.roles.pilots.size(), 3, "you + 2 AI pilots")
	t.eq(d.roles.real_controller_id, Demo.ai_id(2), "an AI tower")
	t.eq(d.roles.impostor_id, 0, "no impostor")
	t.eq(String(d.ai_names[Demo.ai_id(2)]), Demo.AI_TOWER_NAME, "tower name")
	var duel := Demo.build("solo_impostor", ME, SimRng.new(1))
	t.eq(duel.roles.pilots.size(), 2, "you + 1 AI pilot")
	t.check(duel.roles.impostor_id != 0 and duel.roles.real_controller_id != 0, "two AI controllers")
	t.check(duel.impostor != null and duel.impostor.target_cs == duel.sim.by_player(ME).callsign, "after you")
	var names := [duel.ai_names[duel.roles.real_controller_id], duel.ai_names[duel.roles.impostor_id]]
	names.sort()
	t.eq(names, Demo.DUEL_NAMES, "neutral names")
	var ctl := Demo.build("solo_controller", ME, SimRng.new(1))
	t.eq(ctl.roles.real_controller_id, ME, "you are the tower")
	t.eq(ctl.pilots.size(), 4, "4 AI pilots")
	t.done()


func test_solo_ai_tower_lands_everyone(t: T) -> void:
	for seed_v in [1, 2]:
		var r := play("solo", seed_v, "obey")
		t.check(r["ended"], "round ended (seed %d)" % seed_v)
		for cs: String in r["outcomes"]:
			t.eq(r["outcomes"][cs], "landed", "%s lands (seed %d)" % [cs, seed_v])
		var tower: int = (r["demo"] as Demo).roles.real_controller_id
		t.check(said_by(r["log"], tower, "contact") >= 3, "radar contact with everyone")
		t.check(said_by(r["log"], tower, "app") >= 3 and said_by(r["log"], tower, "land") >= 3, "approach and landing clearances")
	var lazy := play("solo", 1, "none")
	var landed := 0
	for cs: String in lazy["outcomes"]:
		if lazy["outcomes"][cs] == "landed":
			landed += 1
	t.eq(landed, 2, "with a pilot who ignores it, the AI traffic still lands")
	t.done()


func test_solo_impostor_duel(t: T) -> void:
	for seed_v in [1, 4]:
		var good := play("solo_impostor", seed_v, "obey_real")
		t.eq(good["mine"], "landed", "obeying the real tower lands you (seed %d)" % seed_v)
		t.eq(good["winner"], "tower", "tower wins (seed %d)" % seed_v)
		var d: Demo = good["demo"]
		t.check(not d.impostor.lies.is_empty(), "the impostor lied (%s)" % d.impostor.scheme)
		t.check(said_by(good["log"], d.roles.real_controller_id, "disregard") >= 1, "the real tower corrected a lie")
		t.check(said_by(good["log"], d.roles.real_controller_id, "accuse") >= 1, "and called the impostor out")
		var bad := play("solo_impostor", seed_v, "gullible_impostor")
		t.check(bad["mine"] != "landed", "obeying the impostor kills you (seed %d: %s)" % [seed_v, bad["mine"]])
		t.eq(bad["winner"], "impostor", "impostor wins (seed %d)" % seed_v)
	t.done()


func test_solo_controller_ai_pilots_obey_you(t: T) -> void:
	var r := play("solo_controller", 1, "ai_tower")
	var landed := 0
	for cs: String in r["outcomes"]:
		if r["outcomes"][cs] == "landed":
			landed += 1
	t.check(landed >= 3, "your clearances land them (%d of 4)" % landed)
	var idle := play("solo_controller", 2, "none")
	t.eq((idle["outcomes"] as Dictionary).values().count("landed"), 0, "nobody lands without a controller")
	t.done()
