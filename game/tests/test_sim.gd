extends RefCounted
## Port of src/shared/sim/sim.test.ts (same scenarios, same expectations).

const T := preload("res://tests/lib/t.gd")
const Geo := preload("res://core/sim/geo.gd")
const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const SimAircraft := preload("res://core/sim/aircraft.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")

const DT := 0.1
const QNH := 1003

var W: SimWorld = SimWorld.default_world()


func ac(over: Dictionary = {}) -> Dictionary:
	var d := {
		"callsign": "TST1", "player_id": 1, "x": 20.0, "y": 0.0, "alt": 3000.0, "hdg": 270.0,
		"ias": 180.0, "fuel_min": 30.0, "alt_setting": QNH,
	}
	d.merge(over, true)
	return d


func rnd(inits: Array[Dictionary], qnh: int = QNH) -> SimRound:
	return SimRound.new(SimRng.new(1), [], qnh, inits)


## Step for max_sec seconds, or until the round is finished when stop_when_finished.
func run(r: SimRound, max_sec: float, stop_when_finished: bool = true) -> float:
	var t := 0.0
	while t < max_sec:
		r.step(DT)
		if stop_when_finished and r.is_finished():
			return t
		t += DT
	return max_sec


func test_geo_terrain_msa_glidepath(t: T) -> void:
	t.eq(Geo.terrain_elev_at(W, 9, 9), 4200.0, "Mt Carrow")
	t.eq(Geo.terrain_elev_at(W, 30, 0), W.field_elev, "field elev")
	t.eq(Geo.msa_at(W, 10, 10), 5200.0, "MSA 045")
	t.eq(Geo.msa_at(W, 10, -10), 4400.0, "MSA 135")
	t.eq(Geo.msa_at(W, -10, 10), 5900.0, "MSA 315")
	var faf_x: float = SimWorld.WorldDef.DATA["ils"]["faf"]["x"]
	t.close_to(Geo.glidepath_alt(W, faf_x), 3000.0, -2, "glidepath at FAF")
	t.done()


func test_geo_ils_needles(t: T) -> void:
	var north := Geo.ils_deviation(W, 10, 0.1, 1000)
	t.check(north.valid and north.loc < 0.0, "north of centreline: fly left")
	t.close_to(north.loc, -0.57, 1, "0.57° north")
	t.check(Geo.ils_deviation(W, 10, -0.1, 1000).loc > 0.0, "south: fly right")
	t.close_to(Geo.ils_deviation(W, 10, 0, Geo.glidepath_alt(W, 10)).gs, 0.0, 1, "on glidepath")
	t.eq(Geo.ils_deviation(W, 10, 0, 2000).gs, 2.5, "well below: pegged fly up")
	t.check(not Geo.ils_deviation(W, 26, 0, 3000).valid, "beyond range")
	t.check(not Geo.ils_deviation(W, -1, 0, 1000).valid, "behind threshold")
	t.check(not Geo.ils_deviation(W, 10, 8, 3000).valid, "38.7° off")
	t.done()


func test_altimetry_wrong_setting(t: T) -> void:
	# Pilot left 1013 set with QNH 1003 and was told 4000: indicated 4000, true 3730.
	var r := rnd([ac({"alt": 5000.0, "alt_setting": 1013, "sel_alt": 4000, "x": 40.0})])
	var a := r.aircraft[0]
	run(r, 120, false)
	t.close_to(r.own_view(1)["ind_alt"], 4000, -1, "indicated holds 4000")
	t.close_to(a.alt, 4000 - 10 * 27, -1, "true altitude 270 ft low")
	a.apply({"alt_setting": 1003})
	t.close_to(r.own_view(1)["ind_alt"], 3730, -1, "instantly reads true altitude")
	run(r, 60, false)
	t.close_to(a.alt, 4000, -1, "climbs back to 4000 true")
	t.done()


## Downwind-ish start north-east, vectored: heading 210 descending to 3000, then a
## 30° intercept heading 240 with APP armed, configure on the glideslope.
func fly_approach(gear: bool) -> SimRound:
	var r := rnd([ac({"x": 24.0, "y": 12.0, "alt": 6000.0, "hdg": 210.0, "ias": 220.0, "sel_alt": 6000})])
	var a := r.aircraft[0]
	a.apply({"hdg": 210, "alt": 3000, "spd": 200})
	var phase := 0
	var t := 0.0
	while t < 1200.0:
		if phase == 0 and a.y < 3.0:
			a.apply({"hdg": 240, "app": true, "flaps": 1, "spd": 180})
			phase = 1
		elif phase == 1 and a.ap_mode() == "LOC":
			a.apply({"flaps": 2, "spd": 160})
			phase = 2
		elif phase == 2 and a.gs_captured:
			a.apply({"gear": gear, "flaps": 3, "spd": 140})
			phase = 3
		r.step(DT)
		if r.is_finished():
			break
		t += DT
	return r


func test_vectored_ils_lands(t: T) -> void:
	var r := fly_approach(true)
	var a := r.aircraft[0]
	t.eq(a.outcome, "landed", "outcome")
	t.eq(a.status, "landed", "status")
	t.check(absf(a.y) < 0.05, "on the centreline (y=%f)" % a.y)
	var kinds: Array = r.all_events().map(func(e: Dictionary) -> String: return e["kind"])
	t.eq(kinds, ["landed"], "events")
	t.done()


func test_gear_up_landing_is_runway(t: T) -> void:
	t.eq(fly_approach(false).aircraft[0].outcome, "runway", "outcome")
	t.done()


func test_glideslope_no_capture_from_above(t: T) -> void:
	var r := rnd([ac({"x": 8.0, "y": 0.0, "alt": 4500.0, "hdg": 270.0, "ias": 160.0})])
	var a := r.aircraft[0]
	a.apply({"app": true})
	run(r, 20, false)
	t.eq(a.ap_mode(), "LOC", "LOC only")
	t.eq(a.gs_captured, false, "no GS")
	t.done()


func test_too_low_gear(t: T) -> void:
	var r := rnd([ac({"x": 1.0, "y": 0.0, "alt": Geo.glidepath_alt(W, 1), "ias": 140.0, "flaps": 3})])
	r.step(DT)
	t.check(r.aircraft[0].warnings.has("TOO LOW GEAR"), "TOO LOW GEAR")
	t.done()


func test_terrain_mt_carrow_warns_then_crashes(t: T) -> void:
	var r := rnd([ac({"x": 20.0, "y": 9.0, "alt": 3000.0, "hdg": 270.0, "ias": 200.0})])
	var a := r.aircraft[0]
	var seen := {}
	var tm := 0.0
	while tm < 600.0:
		for w in a.warnings:
			seen[w] = true
		r.step(DT)
		if r.is_finished():
			break
		tm += DT
	t.check(seen.has("TERRAIN"), "TERRAIN seen")
	t.check(seen.has("PULL UP"), "PULL UP seen")
	t.eq(a.outcome, "terrain", "outcome")
	t.close_to(a.x, 12.5, 0, "hit the cylinder edge")
	t.done()


func test_descending_into_ground_is_terrain(t: T) -> void:
	var r := rnd([ac({"x": 20.0, "y": -20.0, "alt": 3000.0, "hdg": 90.0, "sel_alt": 0})])
	run(r, 600)
	t.eq(r.aircraft[0].outcome, "terrain", "outcome")
	t.done()


func test_no_terrain_warning_when_established(t: T) -> void:
	var r := rnd([ac({"x": 5.0, "y": 0.0, "alt": Geo.glidepath_alt(W, 5) - 150.0, "ias": 140.0, "gear_down": true, "flaps": 3})])
	var a := r.aircraft[0]
	a.apply({"app": true})
	var warned := false
	var tm := 0.0
	while tm < 600.0:
		warned = warned or (a.gs_captured and (a.warnings.has("TERRAIN") or a.warnings.has("PULL UP")))
		r.step(DT)
		if r.is_finished():
			break
		tm += DT
	t.eq(a.outcome, "landed", "outcome")
	t.eq(warned, false, "no GPWS on the glidepath")
	t.done()


func test_head_on_collision(t: T) -> void:
	var r := rnd([
		ac({"callsign": "AAA1", "player_id": 1, "x": 30.0, "y": 15.0, "hdg": 270.0, "alt": 6000.0}),
		ac({"callsign": "BBB2", "player_id": 2, "x": 20.0, "y": 15.0, "hdg": 90.0, "alt": 6000.0}),
	])
	run(r, 300)
	t.eq([r.aircraft[0].outcome, r.aircraft[1].outcome], ["collision", "collision"], "outcomes")
	t.eq(r.all_events().size(), 1, "one event")
	var cs: Array = r.all_events()[0]["callsigns"].duplicate()
	cs.sort()
	t.eq(cs, ["AAA1", "BBB2"], "callsigns")
	t.done()


func test_1000ft_apart_pass_safely(t: T) -> void:
	var r := rnd([
		ac({"player_id": 1, "x": 30.0, "y": 15.0, "hdg": 270.0, "alt": 6000.0}),
		ac({"player_id": 2, "x": 20.0, "y": 15.0, "hdg": 90.0, "alt": 7000.0}),
	])
	var conflict := false
	var tm := 0.0
	while tm < 200.0:
		for tg in r.radar():
			conflict = conflict or bool(tg["conflict"])
		r.step(DT)
		tm += DT
	t.check(r.aircraft[0].is_flying() and r.aircraft[1].is_flying(), "both flying")
	t.eq(conflict, false, "no conflict alert")
	t.done()


func test_conflict_alert(t: T) -> void:
	var r := rnd([
		ac({"player_id": 1, "x": 30.0, "y": 15.0, "alt": 6000.0}),
		ac({"player_id": 2, "x": 32.0, "y": 15.0, "alt": 6500.0}),
		ac({"player_id": 3, "x": 30.0, "y": 25.0, "alt": 6000.0}),
	])
	t.eq(r.radar().map(func(x: Dictionary) -> bool: return x["conflict"]), [true, true, false], "conflict flags")
	t.done()


func test_msaw(t: T) -> void:
	var r := rnd([
		ac({"player_id": 1, "x": 20.0, "y": 5.0, "alt": 3000.0}),
		ac({"player_id": 2, "x": 20.0, "y": 5.0, "alt": 6000.0}),
	])
	t.eq(r.radar().map(func(x: Dictionary) -> bool: return x["msaw"]), [true, false], "msaw flags")
	var est := rnd([ac({"x": 12.0, "y": 0.0, "alt": 3000.0})])
	est.aircraft[0].apply({"app": true})
	est.step(DT)
	t.eq(est.aircraft[0].ap_mode(), "LOC", "established")
	t.eq(est.radar()[0]["msaw"], false, "no MSAW when established")
	t.done()


func test_fuel_exhaustion(t: T) -> void:
	var r := rnd([ac({"x": 30.0, "y": 30.0, "alt": 8000.0, "fuel_min": 6.0})])
	var a := r.aircraft[0]
	var low := false
	var tm := 0.0
	while tm < 3600.0:
		low = low or a.warnings.has("LOW FUEL")
		r.step(DT)
		if r.is_finished():
			break
		tm += DT
	t.check(low, "LOW FUEL first")
	t.eq(a.outcome, "fuel", "outcome")
	t.close_to(r.time, 360, 0, "after 6 minutes")
	t.done()


func test_autopilot_clamping(t: T) -> void:
	var a := SimAircraft.new(ac(), QNH)
	a.apply({"hdg": -10, "alt": 123456, "spd": 90, "alt_setting": 2000})
	t.eq(a.sel_hdg, 350, "hdg wraps")
	t.eq(a.sel_alt, 20000, "alt max")
	t.eq(a.sel_spd, 200, "clean minimum")
	t.eq(a.alt_setting, 1050, "baro max")
	a.apply({"flaps": 3, "spd": 90})
	t.eq(a.sel_spd, 135, "flaps 3 minimum")
	a.apply({"flaps": 0})
	t.eq(a.sel_spd, 200, "re-clamped on retraction")
	a.apply({"spd": 400, "hdg": 360})
	t.eq(a.sel_spd, 250, "max speed")
	t.eq(a.sel_hdg, 0, "360 -> 0")
	t.done()


func test_spawns(t: T) -> void:
	var all_ids: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	for seed_v in range(1, 201):
		var ids: Array[int] = all_ids.slice(0, 1 + (seed_v % 8))
		var r := SimRound.new(SimRng.new(seed_v), ids)
		if r.aircraft.size() != ids.size():
			t.check(false, "seed %d: %d aircraft for %d pilots" % [seed_v, r.aircraft.size(), ids.size()])
			continue
		var cs := {}
		for a in r.aircraft:
			cs[a.callsign] = true
			var d := Geo.hypot(a.x, a.y)
			var dam := SimRound.direct_approach_minutes(W, a.x, a.y)
			var ok := d >= 25.0 and d <= 35.0 and a.alt > Geo.msa_at(W, a.x, a.y) and a.alt > 6400.0 \
				and a.warnings.is_empty() and a.ias == 250.0 and a.alt_setting == 1013 \
				and a.fuel_min >= dam + 7.9 and a.fuel_min <= dam + 14.1
			t.check(ok, "seed %d %s: spawn constraints" % [seed_v, a.callsign])
		t.eq(cs.size(), ids.size(), "seed %d unique callsigns" % seed_v)
		for tg in r.radar():
			t.check(not tg["conflict"] and not tg["msaw"], "seed %d no alerts at spawn" % seed_v)
		for a in r.aircraft:
			for b in r.aircraft:
				if a != b:
					t.check(Geo.dist(a.x, a.y, b.x, b.y) >= 3.0 or absf(a.alt - b.alt) >= 1000.0, "seed %d separated" % seed_v)
	t.done()


func test_direct_approach_from_spawn_lands(t: T) -> void:
	var r := SimRound.new(SimRng.new(7), [1] as Array[int])
	var a := r.aircraft[0]
	a.apply({"alt_setting": r.qnh, "alt": 3000, "spd": 220})
	var phase := 0
	var tm := 0.0
	while tm < 3600.0:
		var tx := 18.0
		var ty := 4.0 if a.y > 0.0 else -4.0
		if phase == 0:
			a.apply({"hdg": atan2(tx - a.x, ty - a.y) * 180.0 / PI})
			if Geo.dist(a.x, a.y, tx, ty) < 1.5:
				a.apply({"hdg": 240 if a.y > 0.0 else 300, "app": true, "flaps": 1, "spd": 180})
				phase = 1
		elif phase == 1 and a.gs_captured:
			a.apply({"gear": true, "flaps": 3, "spd": 140})
			phase = 2
		r.step(DT)
		if r.is_finished():
			break
		tm += DT
	t.eq(a.outcome, "landed", "outcome")
	t.check(a.fuel_min > 7.0, "fuel to spare (%f)" % a.fuel_min)
	t.done()


func test_winner(t: T) -> void:
	t.eq(SimRound.winner(["landed", "landed", "terrain"] as Array[String]), "tower", "2/3")
	t.eq(SimRound.winner(["landed", "terrain"] as Array[String]), "impostor", "1/2")
	t.eq(SimRound.winner(["landed", "landed", "fuel", "collision"] as Array[String]), "impostor", "2/4")
	t.eq(SimRound.winner(["landed", "landed", "landed", "collision"] as Array[String]), "tower", "3/4")
	t.eq(SimRound.winner(["landed"] as Array[String]), "tower", "1/1")
	t.eq(SimRound.winner(["runway"] as Array[String]), "impostor", "0/1")
	t.done()


func test_end_result(t: T) -> void:
	var r := rnd([ac({"player_id": 5, "callsign": "X1", "alt": 520.0, "sel_alt": 0, "x": 20.0, "y": 20.0})])
	run(r, 60)
	t.check(r.is_finished(), "finished")
	var res := r.result(11, 12)
	t.eq(res["winner"], "impostor", "winner")
	t.eq(res["real_controller_id"], 11, "real id")
	t.eq(res["impostor_id"], 12, "impostor id")
	t.eq(res["outcomes"], [{"callsign": "X1", "player_id": 5, "outcome": "terrain"}], "outcomes")
	t.done()


func test_deterministic_for_seed(t: T) -> void:
	var ids: Array[int] = [1, 2, 3]
	var a := SimRound.new(SimRng.new(42), ids)
	var b := SimRound.new(SimRng.new(42), ids)
	t.eq(a.radar(), b.radar(), "radar")
	t.eq(a.atis, b.atis, "atis")
	t.done()
