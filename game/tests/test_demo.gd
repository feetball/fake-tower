extends RefCounted
## Offline demos (scripted AI over the real sim) and the Session autoload driving them.

const T := preload("res://tests/lib/t.gd")
const SimRng := preload("res://core/sim/rng.gd")
const Demo := preload("res://core/net/demo.gd")


## Run a demo's sim to the end; returns {landed, msaw, conflict, outcomes}.
func run_demo(role: String, seed_v: int, max_steps: int = 30000) -> Dictionary:
	var d := Demo.build(role, 1, SimRng.new(seed_v))
	var msaw := {}
	var conflict := {}
	var n := 0
	while n < max_steps and not d.sim.is_finished():
		d.tick()
		d.sim.step(0.1)
		if n % 10 == 0:
			for tg in d.sim.radar():
				if tg["msaw"]:
					msaw[tg["callsign"]] = true
				if tg["conflict"]:
					conflict[tg["callsign"]] = true
		n += 1
	var outcomes := {}
	for a in d.sim.aircraft:
		outcomes[a.callsign] = a.outcome
	return {"msaw": msaw, "conflict": conflict, "outcomes": outcomes, "time": d.sim.time}


func test_controller_demo_varied_traffic_all_land(t: T) -> void:
	var r := run_demo("controller", 1)
	t.eq(r["outcomes"].size(), 4, "4 aircraft")
	for cs: String in r["outcomes"]:
		t.eq(r["outcomes"][cs], "landed", cs + " lands")
	t.check(not r["msaw"].is_empty(), "someone trips MSAW")
	t.check(not r["conflict"].is_empty(), "a conflict alert happens")
	t.done()


func test_pilot_demo_start_state(t: T) -> void:
	var d := Demo.build("pilot", 1, SimRng.new(4))
	t.eq(d.roles.pilots.size(), 3, "you + 2 AI")
	t.eq(d.roles.real_controller_id, 0, "no controllers")
	d.tick()
	d.sim.step(0.1)
	var own := d.sim.own_view(1)
	t.eq(own["ap_mode"], "LOC", "established on the localizer")
	t.near(float(own["dme"]), 12.0, 0.1, "12 nm final")
	t.near(float(own["ind_alt"]), 3000.0, 5.0, "platform altitude, correct QNH set")
	t.eq(own["alt_setting"], d.sim.qnh, "QNH set")
	t.eq(own["flaps"], 1, "flaps 1")
	var r := run_demo("pilot", 4)
	for cs: String in r["outcomes"]:
		if cs != "N12FT":
			t.eq(r["outcomes"][cs], "landed", cs + " AI lands")
	t.done()


func test_pilot_far_demo_ai_land(t: T) -> void:
	for seed_v in [1, 2]:
		var d := Demo.build("pilot_far", 1, SimRng.new(seed_v))
		var mine := d.sim.by_player(1)
		var dist := sqrt(mine.x * mine.x + mine.y * mine.y)
		t.check(dist >= 25.0 and dist <= 35.0, "spawned at a gate")
		var r := run_demo("pilot_far", seed_v)
		var landed := 0
		for cs: String in r["outcomes"]:
			if r["outcomes"][cs] == "landed":
				landed += 1
		t.eq(landed, 2, "both AI land (seed %d)" % seed_v)
	t.check(Demo.build("nope", 1, SimRng.new(1)) == null, "unknown role")
	t.done()


func _session() -> Node:
	var root := (Engine.get_main_loop() as SceneTree).root
	var s := root.get_node_or_null("Session")
	if s == null:
		s = load("res://core/session.gd").new()
		s.name = "Session"
		root.add_child(s)
	return s


func test_session_controller_demo(t: T) -> void:
	var s := _session()
	var swept: Array[int] = [0]
	var cb := func(_targets: Array) -> void: swept[0] += 1
	s.radar_swept.connect(cb)
	s.start_demo("controller")
	t.eq(s.phase, "playing", "phase")
	t.eq(s.my_role, "controller", "role")
	t.eq(s.i_am_impostor, false, "real tower")
	t.eq(s.round_players.size(), 5, "you + 4 AI in the roster")
	t.eq(s.radar.size(), 4, "initial sweep")
	t.check(s.own.is_empty(), "controllers get no own")
	for i in 25:
		s._process(0.1)
	t.eq(swept[0], 2, "sweeps at 0 and 2 s")
	t.near(s.round_time, 2.5, 0.11, "round time")
	s.send_ap({"hdg": 90}) # ignored: not a pilot
	s.radar_swept.disconnect(cb)
	s.leave()
	t.eq(s.phase, "menu", "left")
	t.done()


func test_session_pilot_demo(t: T) -> void:
	var s := _session()
	s.start_demo("pilot")
	t.eq(s.my_role, "pilot", "role")
	t.eq(s.my_callsign, "N12FT", "callsign")
	t.eq(s.callsign_of(s.my_id), "N12FT", "callsign_of")
	t.check(s.radar.is_empty(), "pilots get no radar")
	t.eq(s.own["callsign"], "N12FT", "own at start")
	s.send_ap({"hdg": 265, "flaps": 2, "spd": 150})
	s.set_ptt(true)
	t.eq(s.radio_tx, [s.my_id] as Array[int], "keyed")
	s.set_ptt(false)
	t.eq(s.radio_tx, [] as Array[int], "released")
	var prev_x: float = s.own["x"]
	for i in 3:
		s._process(0.1)
	t.eq(s.own["sel_spd"], 160, "ap applied, clamped to flaps-2 minimum")
	t.eq(s.own["flaps"], 2, "flaps")
	t.check(float(s.own["x"]) < prev_x, "flying west")
	t.check(s.own.has("pitch_deg") and s.own.has("time"), "view fields")
	s.return_to_lobby() # demo: back to the menu
	t.eq(s.phase, "menu", "demo exits to menu")
	s.start_demo("bogus")
	t.eq(s.phase, "menu", "unknown demo role refused")
	t.done()
