extends RefCounted
## Port of src/shared/sim/regression.test.ts: invariants over many seeds, ILS and
## landing edge cases, clamping, GPWS ordering, alert boundaries and golden masters.
## Differences from TS: player ids are ints; a landed aircraft keeps its vertical
## speed (rollout animation), so that one check reads the radar trend instead.

const T := preload("res://tests/lib/t.gd")
const Geo := preload("res://core/sim/geo.gd")
const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const SimAircraft := preload("res://core/sim/aircraft.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")

const DT := 0.1
const QNH := 1013
const KNOWN_WARNINGS: Array[String] = ["TERRAIN", "PULL UP", "TOO LOW GEAR", "LOW FUEL"]

var W: SimWorld = SimWorld.default_world()


func ac(over: Dictionary = {}) -> Dictionary:
	var d := {"callsign": "TST1", "player_id": 1, "x": 20.0, "y": 0.0, "alt": 3000.0, "hdg": 270.0, "ias": 180.0, "fuel_min": 30.0}
	d.merge(over, true)
	return d


func rnd(inits: Array[Dictionary], qnh: int = QNH) -> SimRound:
	return SimRound.new(SimRng.new(1), [], qnh, inits)


## Aircraft already established on the ILS (LOC + G/S captured).
func established(over: Dictionary = {}) -> SimRound:
	var x: float = over.get("x", 3.0)
	var d := {"x": x, "y": 0.0, "alt": Geo.glidepath_alt(W, x), "ias": 140.0, "gear_down": true, "flaps": 3}
	d.merge(over, true)
	var r := rnd([ac(d)])
	var a := r.aircraft[0]
	a.app_armed = true
	a.loc_captured = true
	a.gs_captured = true
	return r


## Step until `until` (or max_sec); returns elapsed seconds or INF. `each` gets t.
func run_until(r: SimRound, max_sec: float, until: Callable, each: Callable = Callable()) -> float:
	var t := 0.0
	while t < max_sec:
		if each.is_valid():
			each.call(t)
		r.step(DT)
		if until.call():
			return t + DT
		t += DT
	return INF


static func bad_own(o: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var chk := func(ok: bool, what: String) -> void:
		if not ok:
			bad.append(what)
	var flaps: int = o["flaps"]
	chk.call(o["hdg"] >= 0.0 and o["hdg"] < 360.0, "hdg")
	chk.call(o["ias"] >= 135 - 0.05 and o["ias"] <= 250 + 0.05, "ias")
	chk.call(typeof(o["ind_alt"]) == TYPE_INT, "ind_alt")
	chk.call(o["rad_alt"] == null or (typeof(o["rad_alt"]) == TYPE_INT and o["rad_alt"] >= 0 and o["rad_alt"] < 2500), "rad_alt")
	chk.call(o["vs"] >= -2500 and o["vs"] <= 1800, "vs")
	chk.call(o["fuel_min"] >= 0.0 and is_finite(o["fuel_min"]), "fuel")
	chk.call(o["dme"] >= 0.0 and is_finite(o["dme"]), "dme")
	chk.call(typeof(o["bearing_to_station"]) == TYPE_INT and o["bearing_to_station"] >= 0 and o["bearing_to_station"] < 360, "brg")
	chk.call(o["loc_dev"] == null or (o["loc_dev"] >= -2.5 and o["loc_dev"] <= 2.5), "loc_dev")
	chk.call(o["gs_dev"] == null or (o["gs_dev"] >= -2.5 and o["gs_dev"] <= 2.5), "gs_dev")
	chk.call(o["sel_hdg"] >= 0 and o["sel_hdg"] <= 359, "sel_hdg")
	chk.call(o["sel_alt"] % 100 == 0 and o["sel_alt"] >= 0 and o["sel_alt"] <= 20000, "sel_alt")
	chk.call(o["sel_spd"] >= SimAircraft.MIN_SPD[flaps] and o["sel_spd"] <= 250, "sel_spd")
	chk.call(o["alt_setting"] >= 950 and o["alt_setting"] <= 1050, "alt_setting")
	chk.call(flaps >= 0 and flaps <= 3, "flaps")
	chk.call(["HDG", "LOC", "APP"].has(o["ap_mode"]), "ap_mode")
	chk.call(o["gs_captured"] == (o["ap_mode"] == "APP"), "gs/mode")
	chk.call((o["warnings"] as Array).all(func(w: String) -> bool: return KNOWN_WARNINGS.has(w)), "warnings")
	chk.call((o["status"] == "flying") == (o["outcome"] == ""), "outcome")
	chk.call(o["status"] == "flying" or (o["warnings"] as Array).is_empty(), "warnings after finish")
	return bad


static func radar_ok(tg: Dictionary) -> bool:
	return tg["alt"] % 100 == 0 and tg["gs"] >= 0 and tg["track"] >= 0 and tg["track"] < 360 \
		and [-1, 0, 1].has(tg["vs_trend"]) \
		and (tg["status"] == "flying" or (not tg["conflict"] and not tg["msaw"] and tg["gs"] == 0))


static func random_command(g: SimRng) -> Dictionary:
	var cmd := {}
	if g.next_float() < 0.5:
		cmd["hdg"] = g.rand_range(-720, 720)
	if g.next_float() < 0.5:
		cmd["alt"] = g.rand_range(-2000, 30000)
	if g.next_float() < 0.4:
		cmd["spd"] = g.rand_range(-50, 500)
	if g.next_float() < 0.3:
		cmd["flaps"] = g.rand_int(0, 3)
	if g.next_float() < 0.2:
		cmd["gear"] = g.next_float() < 0.5
	if g.next_float() < 0.3:
		cmd["app"] = g.next_float() < 0.7
	if g.next_float() < 0.3:
		cmd["alt_setting"] = g.rand_range(900, 1100)
	return cmd


static func ids(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(i + 1)
	return out


# ---------------------------------------------------------------- properties

func test_spawn_properties_1000_rounds(t: T) -> void:
	for seed_v in range(1000, 2000):
		var r := SimRound.new(SimRng.new(seed_v), ids(1 + seed_v % 8))
		for a in r.aircraft:
			t.check(a.warnings.is_empty(), "seed %d warnings" % seed_v)
			var bad := bad_own(r.own_view(a.player_id))
			t.check(bad.is_empty(), "seed %d bad own %s" % [seed_v, bad])
		for tg in r.radar():
			t.check(radar_ok(tg) and not tg["conflict"] and not tg["msaw"], "seed %d radar" % seed_v)
		t.check(absi(r.qnh - 1013) >= 4, "seed %d qnh" % seed_v)
	t.done()


func test_random_command_sequences(t: T) -> void:
	for seed_v in range(1, 7): # TS runs 40 seeds; 6 keep the GDScript suite fast
		var g := SimRng.new(seed_v * 7919)
		var pid := ids(1 + seed_v % 6)
		var r := SimRound.new(SimRng.new(seed_v), pid)
		var fuel := {}
		var finished := {}
		for a in r.aircraft:
			fuel[a.player_id] = a.fuel_min
		var last := 0.0
		var k := 0
		var problems := 0
		while k < 4000 and not r.is_finished() and problems < 5:
			if k % 15 == 0:
				for id in pid:
					if g.next_float() < 0.5:
						r.apply_ap(id, random_command(g))
			r.step(DT)
			if r.time <= last:
				problems += 1
			last = r.time
			for a in r.aircraft:
				var bad := bad_own(r.own_view(a.player_id))
				if not bad.is_empty():
					t.check(false, "seed %d t=%.1f bad own %s" % [seed_v, r.time, bad])
					problems += 1
				if not (a.hdg >= 0.0 and a.hdg < 360.0 and is_finite(a.x) and is_finite(a.alt) and is_finite(a.vs)):
					t.check(false, "seed %d raw state" % seed_v)
					problems += 1
				if a.fuel_min > fuel[a.player_id]:
					t.check(false, "seed %d fuel increased" % seed_v)
					problems += 1
				fuel[a.player_id] = a.fuel_min
				if finished.has(a.player_id):
					if a.outcome != finished[a.player_id]:
						t.check(false, "seed %d outcome changed" % seed_v)
						problems += 1
				elif not a.is_flying():
					finished[a.player_id] = a.outcome
			for tg in r.radar():
				if not radar_ok(tg):
					t.check(false, "seed %d bad radar %s" % [seed_v, tg])
					problems += 1
			k += 1
		for e in r.all_events():
			for cs: String in e["callsigns"]:
				t.eq(r.by_callsign(cs).outcome, e["kind"], "event matches outcome")
	t.done()


# ---------------------------------------------------------------- ILS capture

func test_above_glideslope_never_captures_goes_missed(t: T) -> void:
	var r := rnd([ac({"x": 12.0, "alt": 6000.0, "ias": 160.0, "sel_alt": 6000})])
	var a := r.aircraft[0]
	a.apply({"app": true})
	var seen := {"gs": false, "loc": false}
	run_until(r, 600, func() -> bool: return a.x < -2.0, func(_t: float) -> void:
		seen["gs"] = seen["gs"] or a.gs_captured
		seen["loc"] = seen["loc"] or a.loc_captured)
	t.eq(seen["loc"], true, "loc captured")
	t.eq(seen["gs"], false, "gs never")
	t.check(a.is_flying(), "still flying")
	t.eq(a.ap_mode(), "HDG", "loc lost behind the threshold")
	t.eq(r.all_events().size(), 0, "no events")
	t.done()


func test_app_false_drops_capture_and_rearm_recaptures(t: T) -> void:
	var r := established({"x": 6.0})
	var a := r.aircraft[0]
	r.step(DT)
	t.eq(a.ap_mode(), "APP", "APP")
	a.apply({"app": false})
	t.eq([a.app_armed, a.loc_captured, a.gs_captured, a.ap_mode()], [false, false, false, "HDG"], "disconnected")
	r.step(DT)
	t.eq(a.ap_mode(), "HDG", "stays HDG")
	a.apply({"app": true})
	r.step(DT)
	t.eq(a.ap_mode(), "LOC", "recaptured")
	a.apply({"hdg": 90, "alt": 9000, "spd": 140, "gear": true, "flaps": 3, "alt_setting": 1000})
	t.check(a.loc_captured, "other commands leave the approach alone")
	t.done()


func test_localizer_intercept_angle(t: T) -> void:
	var capture := func(hdg: float) -> bool:
		var r := rnd([ac({"x": 10.0, "y": 0.05, "hdg": hdg, "ias": 180.0})])
		r.aircraft[0].apply({"app": true})
		r.step(DT)
		return r.aircraft[0].loc_captured
	for h in [270, 0, 180, 359]:
		t.eq(capture.call(h), true, "captures at %d" % h)
	for h in [1, 179, 90]:
		t.eq(capture.call(h), false, "no capture at %d" % h)
	t.done()


func test_needs_app_and_needle_inside_full_scale(t: T) -> void:
	var unarmed := rnd([ac({"x": 10.0})])
	unarmed.step(DT)
	t.eq(unarmed.aircraft[0].loc_captured, false, "unarmed")
	var offside := rnd([ac({"x": 10.0, "y": 0.5, "hdg": 240.0})])
	offside.aircraft[0].apply({"app": true})
	offside.step(DT)
	t.eq(offside.aircraft[0].loc_captured, false, "needle pegged")
	t.done()


func test_no_capture_beyond_range(t: T) -> void:
	var r := rnd([ac({"x": W.range_nm + 2.0, "hdg": 270.0, "ias": 250.0, "alt": 4000.0})])
	var a := r.aircraft[0]
	a.apply({"app": true})
	var early := [false]
	var t_cap := run_until(r, 120, func() -> bool: return a.loc_captured, func(_t: float) -> void:
		if Geo.hypot(a.x, a.y) > W.range_nm and a.loc_captured:
			early[0] = true)
	t.eq(early[0], false, "not captured outside range")
	t.check(t_cap < 120.0, "captured inside")
	var d := Geo.hypot(a.x, a.y)
	t.check(d <= W.range_nm and d > W.range_nm - 0.1, "captured at the range edge (%f)" % d)
	t.check(not Geo.ils_deviation(W, W.range_nm + 0.01, 0, 4000).valid, "no signal beyond range")
	t.done()


func test_out_of_coverage_disconnects(t: T) -> void:
	var r := rnd([ac({"x": 10.0, "hdg": 270.0})])
	var a := r.aircraft[0]
	a.apply({"app": true})
	r.step(DT)
	t.check(a.loc_captured, "captured")
	a.x = 10.0
	a.y = 8.0
	r.step(DT)
	t.eq(a.ap_mode(), "HDG", "disconnected")
	t.eq(a.app_armed, true, "still armed")
	t.done()


# ---------------------------------------------------------------- threshold

func final_outcome(over: Dictionary) -> SimAircraft:
	var d := {"x": 0.3}
	d.merge(over, true)
	var r := established(d)
	run_until(r, 60, func() -> bool: return r.is_finished())
	return r.aircraft[0]


func test_stable_landing_limits(t: T) -> void:
	t.eq(final_outcome({}).outcome, "landed", "nominal")
	t.eq(final_outcome({"ias": 155.0}).outcome, "landed", "155 kt")
	t.eq(final_outcome({"ias": 156.0}).outcome, "runway", "156 kt")
	t.eq(final_outcome({"gear_down": false}).outcome, "runway", "gear up")
	t.eq(final_outcome({"flaps": 2, "ias": 160.0}).outcome, "runway", "flaps 2")
	var l := final_outcome({})
	t.eq(l.status, "landed", "status")
	t.eq(l.radar_view(false, false)["vs_trend"], 0, "level trend after landing")
	t.eq(l.warnings, [] as Array[String], "no warnings")
	t.done()


func test_uncaptured_threshold_crossing_keeps_flying(t: T) -> void:
	for setup in ["none", "loc-only"]:
		var r := rnd([ac({"x": 1.0, "alt": 1500.0, "ias": 140.0, "gear_down": true, "flaps": 3, "sel_alt": 1500})])
		var a := r.aircraft[0]
		if setup == "loc-only":
			a.app_armed = true
			a.loc_captured = true
		run_until(r, 120, func() -> bool: return a.x < -1.0)
		t.check(a.is_flying(), setup + " flying")
		t.eq(a.outcome, "flying", setup + " outcome")
		t.eq(r.all_events().size(), 0, setup + " no events")
	t.done()


func test_regression_off_centreline_close_in_still_lands(t: T) -> void:
	var r := established({"x": 0.01, "y": 0.008, "alt": Geo.glidepath_alt(W, 0.0128)})
	run_until(r, 10, func() -> bool: return r.is_finished())
	t.eq(r.aircraft[0].outcome, "landed", "landed")
	t.done()


func test_regression_hair_short_of_threshold_still_lands(t: T) -> void:
	var r := established({"x": 1e-12, "alt": Geo.glidepath_alt(W, 0)})
	var dev := Geo.ils_deviation(W, 1e-12, 0, 600)
	t.check(dev.valid and dev.loc == 0.0 and dev.gs == 0.0, "centred needles over the antenna")
	r.step(DT)
	t.eq(r.aircraft[0].outcome, "landed", "landed")
	t.done()


func test_near_threshold_coverage(t: T) -> void:
	var close := Geo.ils_deviation(W, 0.01, 0.008, 600)
	t.check(close.valid and close.loc == -2.5, "close in: signal, pegged")
	var far := Geo.ILS_NEAR_NM + 0.1
	t.check(not Geo.ils_deviation(W, far * cos(0.7), far * sin(0.7), 600).valid, "40° off beyond 0.5 nm")
	t.check(not Geo.ils_deviation(W, -0.01, 0, 600).valid, "behind the threshold")
	t.check(not Geo.ils_deviation(W, -0.001, 0.3, 600).valid, "abeam, just behind")
	t.done()


# ---------------------------------------------------------------- clamping

func test_clamp_hdg(t: T) -> void:
	var a := SimAircraft.new(ac(), QNH)
	for c: Array in [[0, 0], [359.4, 359], [359.6, 0], [360, 0], [-0.4, 0], [-1, 359], [725, 5], [-725, 355], [1e9, int(fmod(1e9, 360.0))]]:
		a.apply({"hdg": c[0]})
		t.eq(a.sel_hdg, c[1], "hdg %s" % c[0])
	t.done()


func test_clamp_alt(t: T) -> void:
	var a := SimAircraft.new(ac(), QNH)
	for c: Array in [[3049, 3000], [3050, 3100], [-49, 0], [-5000, 0], [20049, 20000], [1e9, 20000], [0, 0]]:
		a.apply({"alt": c[0]})
		t.eq(a.sel_alt, c[1], "alt %s" % c[0])
	t.done()


func test_clamp_spd(t: T) -> void:
	var a := SimAircraft.new(ac({"flaps": 0}), QNH)
	a.apply({"spd": 210.4})
	t.eq(a.sel_spd, 210, "whole knots")
	a.apply({"spd": -100})
	t.eq(a.sel_spd, 200, "clean minimum")
	a.apply({"spd": 9999})
	t.eq(a.sel_spd, 250, "max")
	for f in [1, 2, 3]:
		a.apply({"flaps": f, "spd": 0})
		t.eq(a.sel_spd, SimAircraft.MIN_SPD[f], "flaps %d minimum" % f)
	a.apply({"flaps": 0})
	t.eq(a.sel_spd, 200, "retracting raises the minimum")
	a.apply({"spd": 135, "flaps": 3})
	t.eq(a.sel_spd, 135, "flaps before speed in one command")
	t.done()


func test_clamp_alt_setting_flaps_bools(t: T) -> void:
	var a := SimAircraft.new(ac(), QNH)
	for c: Array in [[1003.4, 1003], [1003.5, 1004], [0, 950], [5000, 1050]]:
		a.apply({"alt_setting": c[0]})
		t.eq(a.alt_setting, c[1], "baro %s" % c[0])
	a.apply({"flaps": 7})
	t.eq(a.flaps, 3, "flaps 7")
	a.apply({"flaps": -2})
	t.eq(a.flaps, 0, "flaps -2")
	a.apply({"flaps": 1.6})
	t.eq(a.flaps, 2, "flaps 1.6")
	a.apply({"gear": true, "app": true})
	t.eq([a.gear_down, a.app_armed], [true, true], "bools")
	a.apply({})
	t.eq([a.gear_down, a.app_armed, a.flaps, a.alt_setting], [true, true, 2, 1050], "empty command")
	t.done()


func test_commands_ignored_after_finish(t: T) -> void:
	var r := rnd([ac()])
	var a := r.aircraft[0]
	a.finish("terrain")
	var before := [a.sel_hdg, a.sel_alt, a.gear_down]
	t.eq(r.apply_ap(1, {"hdg": 10, "alt": 0, "gear": true}), false, "refused")
	a.apply({"hdg": 10})
	t.eq([a.sel_hdg, a.sel_alt, a.gear_down], before, "unchanged")
	t.eq(r.apply_ap(99, {"hdg": 10}), false, "nobody")
	r.step(DT)
	t.eq(r.time, 0.0, "finished round does not advance")
	t.done()


# ---------------------------------------------------------------- GPWS

func onsets(r: SimRound) -> Dictionary:
	var a := r.aircraft[0]
	var first := {}
	var t_end := run_until(r, 900, func() -> bool: return not a.is_flying(), func(tt: float) -> void:
		for w in a.warnings:
			if not first.has(w):
				first[w] = tt)
	return {"first": first, "end": t_end}


func test_gpws_level_into_mountain(t: T) -> void:
	var o := onsets(rnd([ac({"x": 20.0, "y": 9.0, "alt": 3000.0, "hdg": 270.0, "ias": 200.0, "sel_alt": 3000})]))
	var f: Dictionary = o["first"]
	var e: float = o["end"]
	t.check(f["TERRAIN"] < f["PULL UP"], "TERRAIN first")
	t.check(e - f["TERRAIN"] > 29.0 and e - f["TERRAIN"] < 31.5, "TERRAIN ~30 s before")
	t.check(e - f["PULL UP"] > 11.0 and e - f["PULL UP"] < 13.5, "PULL UP ~12 s before")
	t.done()


func test_gpws_descending_into_flat_ground(t: T) -> void:
	var o := onsets(rnd([ac({"x": 20.0, "y": -20.0, "alt": 4000.0, "hdg": 90.0, "ias": 200.0, "sel_alt": 0})]))
	var f: Dictionary = o["first"]
	t.check(f["TERRAIN"] < f["PULL UP"], "order")
	t.check(f.has("TOO LOW GEAR"), "TOO LOW GEAR")
	t.done()


func test_gpws_clears_on_climb_away(t: T) -> void:
	var r := rnd([ac({"x": 20.0, "y": 9.0, "alt": 3000.0, "hdg": 270.0, "ias": 200.0, "sel_alt": 3000})])
	var a := r.aircraft[0]
	run_until(r, 300, func() -> bool: return a.warnings.has("TERRAIN"))
	a.apply({"hdg": 90, "alt": 6000})
	run_until(r, 300, func() -> bool: return a.warnings.is_empty())
	t.check(a.is_flying(), "flying")
	t.eq(a.warnings, [] as Array[String], "cleared")
	t.done()


# ---------------------------------------------------------------- boundaries

func pair(b: Dictionary) -> SimRound:
	var second := {"player_id": 2, "callsign": "B2", "x": 20.0, "y": 10.0, "alt": 6000.0}
	second.merge(b, true)
	return rnd([ac({"callsign": "A1", "x": 20.0, "y": 10.0, "alt": 6000.0}), ac(second)])


func conflicts(b: Dictionary) -> Array:
	return pair(b).radar().map(func(x: Dictionary) -> bool: return x["conflict"])


func test_conflict_boundaries(t: T) -> void:
	t.eq(conflicts({"y": 10.0 + W.sep_lateral_nm - 1e-6}), [true, true], "inside 3 nm")
	t.eq(conflicts({"y": 10.0 + W.sep_lateral_nm + 1e-6}), [false, false], "outside 3 nm")
	t.eq(conflicts({"alt": 6000.0 + W.sep_vertical_ft - 1.0}), [true, true], "999 ft")
	t.eq(conflicts({"alt": 6000.0 + W.sep_vertical_ft}), [false, false], "1000 ft")
	t.eq(conflicts({"y": 11.0, "alt": 5001.0}), [true, true], "below")
	var r := pair({"y": 11.0})
	r.aircraft[1].finish("terrain")
	t.eq(r.radar().map(func(x: Dictionary) -> bool: return x["conflict"]), [false, false], "finished aircraft")
	t.done()


func test_msaw_boundaries(t: T) -> void:
	var msaw := func(x: float, y: float, alt: float) -> bool:
		return rnd([ac({"x": x, "y": y, "alt": alt})]).radar()[0]["msaw"]
	t.eq(msaw.call(10, 10, 5199), true, "5199 in 045")
	t.eq(msaw.call(10, 10, 5200), false, "5200 in 045")
	t.eq(Geo.msa_at(W, 10, 0), 4400.0, "090 belongs to 090-180")
	t.eq(Geo.msa_at(W, 0, 10), 5200.0, "000")
	t.eq(Geo.msa_at(W, 0, -10), 5900.0, "180")
	t.eq(msaw.call(10, 0, 4399), true, "4399")
	t.eq(msaw.call(10, 0, 4400), false, "4400")
	var done_r := rnd([ac({"x": 10.0, "y": 10.0, "alt": 1000.0})])
	done_r.aircraft[0].finish("terrain")
	t.eq(done_r.radar()[0]["msaw"], false, "finished")
	t.done()


func test_collision_boundaries(t: T) -> void:
	var outcomes := func(b: Dictionary) -> Array:
		var r := pair(b)
		r.step(DT)
		return r.aircraft.map(func(a: SimAircraft) -> String: return a.outcome)
	t.eq(outcomes.call({"y": 10.0 + SimRound.COLLISION_NM - 0.001}), ["collision", "collision"], "inside 0.15 nm")
	t.eq(outcomes.call({"y": 10.0 + SimRound.COLLISION_NM + 0.001}), ["flying", "flying"], "outside 0.15 nm")
	t.eq(outcomes.call({"y": 10.1, "alt": 6000.0 + SimRound.COLLISION_FT - 1.0}), ["collision", "collision"], "199 ft")
	t.eq(outcomes.call({"y": 10.1, "alt": 6000.0 + SimRound.COLLISION_FT + 1.0}), ["flying", "flying"], "201 ft")
	t.done()


func test_three_way_collision_one_event_landed_never_hit(t: T) -> void:
	var r := rnd([
		ac({"player_id": 1, "callsign": "A1", "y": 10.0}),
		ac({"player_id": 2, "callsign": "B2", "y": 10.05}),
		ac({"player_id": 3, "callsign": "C3", "y": 10.1}),
		ac({"player_id": 4, "callsign": "D4", "y": 10.02}),
	])
	r.aircraft[3].finish("landed")
	var ev := r.step(DT)
	t.eq(ev.size(), 1, "one event")
	var cs: Array = ev[0]["callsigns"].duplicate()
	cs.sort()
	t.eq(cs, ["A1", "B2", "C3"], "three aircraft")
	t.eq(r.aircraft[3].outcome, "landed", "landed untouched")
	t.done()


# ---------------------------------------------------------------- golden masters

## JavaScript Number.toFixed (round half away from zero on the decimal value is
## close enough here; String.num uses the same digits for these magnitudes).
static func fx(v: float, d: int = 0) -> String:
	var s := ("%." + str(d) + "f") % v
	return s


static func js_num(v: Variant) -> String:
	if v == null:
		return "null"
	var f := float(v)
	return str(int(f)) if f == floorf(f) else str(f)


func test_golden_vectored_ils(t: T) -> void:
	var r := rnd([ac({"x": 24.0, "y": 12.0, "alt": 6000.0, "hdg": 210.0, "ias": 220.0, "sel_alt": 6000, "alt_setting": 1013})], 1003)
	var a := r.aircraft[0]
	a.apply({"alt_setting": 1003, "alt": 3000, "spd": 200})
	var lines: Array[String] = []
	var phase := 0
	var k := 0
	while k < 9000 and not r.is_finished():
		if phase == 0 and a.y < 3.0:
			a.apply({"hdg": 240, "app": true, "flaps": 1, "spd": 180})
			phase = 1
		elif phase == 1 and a.ap_mode() == "LOC":
			a.apply({"flaps": 2, "spd": 160})
			phase = 2
		elif phase == 2 and a.gs_captured:
			a.apply({"gear": true, "flaps": 3, "spd": 140})
			phase = 3
		if k % 300 == 0:
			var o := r.own_view(1)
			lines.append("t=%s %s,%s alt %s hdg %s ias %s vs %s %s loc %s gs %s [%s]" % [
				fx(r.time), fx(a.x, 2), fx(a.y, 3), fx(a.alt), fx(a.hdg, 1), fx(a.ias, 1), fx(a.vs),
				o["ap_mode"], js_num(o["loc_dev"]), js_num(o["gs_dev"]), ",".join(o["warnings"])])
		r.step(DT)
		k += 1
	lines.append("end t=%s %s y=%s ias=%s fuel=%s" % [fx(r.time, 1), a.outcome, fx(a.y, 4), fx(a.ias, 1), fx(a.fuel_min, 2)])
	var want: Array[String] = [
		"t=0 24.00,12.000 alt 6000 hdg 210.0 ias 220.0 vs 0 HDG loc null gs null []",
		"t=30 23.05,10.359 alt 5166 hdg 210.0 ias 200.0 vs -1800 HDG loc null gs null []",
		"t=60 22.14,8.779 alt 4266 hdg 210.0 ias 200.0 vs -1800 HDG loc -2.5 gs 2.5 []",
		"t=90 21.24,7.226 alt 3366 hdg 210.0 ias 200.0 vs -1800 HDG loc -2.5 gs 2.5 []",
		"t=120 20.36,5.692 alt 3030 hdg 210.0 ias 200.0 vs -150 HDG loc -2.5 gs 2.5 []",
		"t=150 19.47,4.162 alt 3002 hdg 210.0 ias 200.0 vs -12 HDG loc -2.5 gs 2.5 []",
		"t=180 18.54,2.689 alt 3000 hdg 231.6 ias 189.2 vs -1 HDG loc -2.5 gs 2.5 []",
		"t=210 17.16,1.879 alt 3000 hdg 240.0 ias 180.0 vs -0 HDG loc -2.5 gs 2.5 []",
		"t=240 15.78,1.084 alt 3000 hdg 240.0 ias 180.0 vs -0 HDG loc -2.5 gs 2.5 []",
		"t=270 14.44,0.313 alt 3000 hdg 243.3 ias 160.0 vs -0 LOC loc -1.24 gs 2.5 []",
		"t=300 13.06,0.039 alt 3000 hdg 266.7 ias 160.0 vs -0 LOC loc -0.17 gs 2.5 []",
		"t=330 11.65,0.005 alt 3000 hdg 269.6 ias 160.0 vs -0 LOC loc -0.02 gs 2.5 []",
		"t=360 10.24,0.001 alt 3000 hdg 270.0 ias 160.0 vs -0 LOC loc 0 gs 2.16 []",
		"t=390 8.82,0.000 alt 3000 hdg 270.0 ias 160.0 vs -0 LOC loc 0 gs 1.13 []",
		"t=420 7.42,0.000 alt 2925 hdg 270.0 ias 150.7 vs -853 APP loc 0 gs 0 []",
		"t=450 6.18,0.000 alt 2529 hdg 270.0 ias 140.0 vs -781 APP loc 0 gs 0 []",
		"t=480 4.96,0.000 alt 2140 hdg 270.0 ias 140.0 vs -775 APP loc 0 gs 0 []",
		"t=510 3.74,0.000 alt 1754 hdg 270.0 ias 140.0 vs -769 APP loc 0 gs 0 []",
		"t=540 2.54,0.000 alt 1371 hdg 270.0 ias 140.0 vs -763 APP loc 0 gs 0 []",
		"t=570 1.35,0.000 alt 991 hdg 270.0 ias 140.0 vs -758 APP loc 0 gs 0 []",
		"t=600 0.16,0.000 alt 613 hdg 270.0 ias 140.0 vs -752 APP loc 0 gs 0 []",
		"end t=604.1 landed y=0.0000 ias=140.0 fuel=19.93",
	]
	_compare_lines(t, lines, want)
	t.done()


func test_golden_scripted_three_aircraft(t: T) -> void:
	var r := SimRound.new(SimRng.new(20261125), ids(3))
	var script := {
		0: [[1, {"alt_setting": r.qnh, "alt": 4000, "spd": 220}], [2, {"alt_setting": r.qnh, "alt": 5000}], [3, {"alt": 3000, "spd": 200}]],
		600: [[1, {"hdg": 240, "app": true, "flaps": 1, "spd": 180}], [2, {"hdg": 180, "spd": 230}], [3, {"alt_setting": 1013, "hdg": 90}]],
		1500: [[1, {"flaps": 3, "gear": true, "spd": 140}], [2, {"alt": 3000, "app": true, "hdg": 300}]],
		3000: [[3, {"alt": 0}]],
	}
	var css: Array[String] = []
	for a in r.aircraft:
		css.append(a.callsign)
	var lines: Array[String] = ["qnh %d atis %s %s" % [r.qnh, r.atis["letter"], " ".join(css)]]
	for k in 4801:
		for c: Array in script.get(k, []):
			r.apply_ap(c[0], c[1])
		if k % 600 == 0:
			var parts: Array[String] = []
			for a in r.aircraft:
				var w := ("[%s]" % "/".join(a.warnings)) if not a.warnings.is_empty() else ""
				parts.append("%s:%s%s,%s,%s,%s,%s,%s,%s,%s%s" % [a.callsign, a.status[0], fx(a.x, 2), fx(a.y, 2), fx(a.alt),
					fx(a.hdg, 1), fx(a.ias, 1), fx(a.vs), fx(a.fuel_min, 2), a.ap_mode(), w])
			lines.append("t=%s %s" % [fx(r.time), " ".join(parts)])
		r.step(DT)
	var evs: Array[String] = []
	for e in r.all_events():
		evs.append("%s:%s:%s" % [js_num(e["time"]), e["kind"], "+".join(e["callsigns"])])
	lines.append("events " + " ".join(evs))
	var want: Array[String] = [
		"qnh 1005 atis I AAL2529 SWA430 SKW1441",
		"t=0 AAL2529:f-23.79,22.46,9784,143.3,250.0,0,28.90,HDG SWA430:f21.47,25.60,9784,228.7,250.0,0,26.50,HDG SKW1441:f28.82,2.35,8784,269.6,250.0,0,18.30,HDG",
		"t=60 AAL2529:f-21.14,18.94,7412,143.0,220.0,-2500,27.90,HDG SWA430:f17.78,22.40,7567,229.0,250.0,-1800,25.50,HDG SKW1441:f24.71,2.35,6412,270.0,200.0,-2500,17.30,HDG",
		"t=120 AAL2529:f-22.77,16.42,5487,240.0,180.0,-1800,26.90,HDG SWA430:f17.28,18.16,5767,180.0,230.0,-1800,24.50,HDG SKW1441:f24.69,-0.00,4426,91.0,200.0,-1800,16.30,HDG",
		"t=180 AAL2529:f-25.44,14.88,4055,240.0,140.0,-278,25.90,HDG SWA430:f15.94,14.70,4227,270.0,230.0,-1800,23.50,HDG SKW1441:f28.26,-0.00,2869,90.0,200.0,-428,15.30,HDG",
		"t=240 AAL2529:f-27.62,13.62,4000,240.0,140.0,-2,24.90,HDG SWA430:f12.33,16.58,3027,300.0,230.0,-135,22.50,HDG SKW1441:f31.78,-0.00,2785,90.0,200.0,-3,14.30,HDG",
		"t=300 AAL2529:f-29.80,12.36,4000,240.0,140.0,-0,23.90,HDG SWA430:f8.81,18.61,3000,300.0,230.0,-1,21.50,HDG SKW1441:f35.30,-0.00,2784,90.0,200.0,-0,13.30,HDG",
		"t=360 AAL2529:f-31.99,11.10,4000,240.0,140.0,-0,22.90,HDG SWA430:f5.29,20.65,3000,300.0,230.0,-0,20.50,HDG SKW1441:f38.76,-0.00,1050,90.0,200.0,-1800,12.30,HDG[TERRAIN]",
		"t=420 AAL2529:f-34.17,9.84,4000,240.0,140.0,-0,21.90,HDG SWA430:f1.77,22.68,3000,300.0,230.0,-0,19.50,HDG SKW1441:c39.78,-0.00,510,90.0,200.0,0,12.00,HDG",
		"t=480 AAL2529:f-36.35,8.58,4000,240.0,140.0,-0,20.90,HDG SWA430:f-1.74,24.71,3000,300.0,230.0,-0,18.50,HDG SKW1441:c39.78,-0.00,510,90.0,200.0,0,12.00,HDG",
		"events 378:terrain:SKW1441",
	]
	_compare_lines(t, lines, want)
	t.done()


func _compare_lines(t: T, got: Array[String], want: Array[String]) -> void:
	t.eq(got.size(), want.size(), "line count")
	for i in mini(got.size(), want.size()):
		if got[i] != want[i]:
			t.check(false, "line %d\n       got  %s\n       want %s" % [i, got[i], want[i]])
