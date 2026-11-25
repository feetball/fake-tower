extends RefCounted
## Contract additions to the sim for the 3D view: attitude, landing rollout, crash freeze.

const T := preload("res://tests/lib/t.gd")
const Geo := preload("res://core/sim/geo.gd")
const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
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


func rnd(inits: Array[Dictionary]) -> SimRound:
	return SimRound.new(SimRng.new(1), [], QNH, inits)


func test_own_view_has_view_fields(t: T) -> void:
	var r := rnd([ac()])
	r.step(DT)
	var own := r.own_view(1)
	for k: String in ["x", "y", "alt_true", "gs", "pitch_deg", "bank_deg", "on_ground", "time"]:
		t.check(own.has(k), "own has " + k)
	t.eq(own["outcome"], "", "outcome empty while flying")
	t.near(own["time"], 0.1, 1e-9, "time")
	t.near(own["gs"], r.aircraft[0].tas(), 1e-9, "gs = tas")
	t.eq(own["on_ground"], false, "airborne")
	t.eq(own["rad_alt"], 2488, "rad_alt below 2500 AGL")
	var high := rnd([ac({"alt": 5000.0})])
	t.check(high.own_view(1)["rad_alt"] == null, "rad_alt null above 2500 AGL")
	t.check(own["loc_dev"] != null, "loc_dev present on the localizer")
	t.done()


func test_bank_rolls_in_smoothly_and_caps(t: T) -> void:
	var r := rnd([ac({"ias": 250.0, "alt": 8000.0, "sel_alt": 8000, "x": 30.0, "y": 20.0})])
	var a := r.aircraft[0]
	a.apply({"hdg": 90}) # 180° right turn
	var prev := a.att.bank_deg
	var max_step := 0.0
	var max_bank := 0.0
	for i in 900:
		r.step(DT)
		max_step = maxf(max_step, absf(a.att.bank_deg - prev))
		max_bank = maxf(max_bank, a.att.bank_deg)
		prev = a.att.bank_deg
	t.near(max_bank, 25.0, 1e-9, "standard rate at 250+ kt TAS capped at 25°")
	t.check(max_step <= 0.5 + 1e-9, "rolls at ≤ 5°/s (max step %f)" % max_step)
	t.near(a.att.bank_deg, 0.0, 1e-6, "wings level after the turn")
	var slow := rnd([ac({"ias": 140.0, "flaps": 3, "alt": 3000.0, "x": 30.0, "y": 20.0})])
	slow.aircraft[0].apply({"hdg": 180})
	for i in 100:
		slow.step(DT)
	var b := slow.aircraft[0].att.bank_deg
	t.check(b < -15.0 and b > -25.0, "left standard-rate turn at 140 kt ≈ -21° (got %f)" % b)
	t.done()


func test_pitch_plausible(t: T) -> void:
	var r := rnd([ac({"x": 6.0, "alt": Geo.glidepath_alt(W, 6) - 150.0, "ias": 140.0, "gear_down": true, "flaps": 3})])
	var a := r.aircraft[0]
	a.apply({"app": true})
	for i in 200:
		r.step(DT)
	t.check(a.gs_captured, "on the glideslope")
	t.check(a.att.pitch_deg > 1.0 and a.att.pitch_deg < 4.5, "approach pitch ~2.5° (got %f)" % a.att.pitch_deg)
	var c := rnd([ac({"ias": 250.0, "alt": 5000.0, "sel_alt": 5000, "x": 30.0, "y": 20.0})])
	for i in 100:
		c.step(DT)
	var p := c.aircraft[0].att.pitch_deg
	t.check(p > 1.0 and p < 5.0, "clean cruise pitch (got %f)" % p)
	c.aircraft[0].apply({"alt": 9000})
	for i in 150:
		c.step(DT)
	t.check(c.aircraft[0].att.pitch_deg > p + 2.0, "climb pitch higher (got %f)" % c.aircraft[0].att.pitch_deg)
	t.done()


func test_landing_flare_touchdown_rollout(t: T) -> void:
	# A second aircraft keeps the round running so the landed one animates.
	var r := rnd([
		ac({"x": 5.0, "y": 0.02, "alt": Geo.glidepath_alt(W, 5) - 150.0, "ias": 140.0, "gear_down": true, "flaps": 3}),
		ac({"callsign": "FAR1", "player_id": 2, "x": 30.0, "y": 30.0, "alt": 9000.0, "sel_alt": 9000, "fuel_min": 60.0}),
	])
	var a := r.aircraft[0]
	a.apply({"app": true})
	var landed_at := -1.0
	var td_x := 0.0
	var td_vs := 0.0
	var max_jump := 0.0
	var max_pitch := -INF
	var prev_x := a.x
	var prev_y := a.y
	var prev_on_ground := false
	var flare_seen := false
	for i in 3000:
		var vs_before := a.vs
		r.step(DT)
		var own := r.own_view(1)
		max_jump = maxf(max_jump, Geo.dist(prev_x, prev_y, a.x, a.y))
		prev_x = a.x
		prev_y = a.y
		if a.status == "landed" and landed_at < 0.0:
			landed_at = r.time
		if a.status == "landed":
			max_pitch = maxf(max_pitch, own["pitch_deg"])
			if not own["on_ground"] and a.vs > vs_before + 1.0:
				flare_seen = true
		if own["on_ground"] and not prev_on_ground:
			td_x = a.x
			td_vs = vs_before
		prev_on_ground = own["on_ground"]
		if a.att.stopped:
			break
	t.eq(a.outcome, "landed", "outcome")
	t.eq(a.status, "landed", "status stays landed")
	t.check(landed_at > 0.0, "landing check at the threshold")
	t.check(flare_seen, "flare reduces the sink rate")
	t.check(td_x < -0.12 and td_x > -0.5, "touchdown in the touchdown zone (x=%f nm)" % td_x)
	t.check(td_vs > -250.0, "gentle touchdown (%f fpm)" % td_vs)
	t.check(max_pitch > 3.0 and max_pitch < 9.0, "flare pitch (max %f)" % max_pitch)
	t.check(a.att.stopped, "comes to a stop")
	t.check(a.x > -W.runway_length_nm and a.x < 0.0, "stops on the runway (x=%f)" % a.x)
	t.check(absf(a.y) < 0.01, "on the centreline (y=%f)" % a.y)
	t.near(a.alt, W.field_elev, 1e-9, "on the ground")
	var own := r.own_view(1)
	t.eq(own["gs"], 0.0, "stopped: gs 0")
	t.eq(own["on_ground"], true, "on_ground")
	t.check(absf(float(own["pitch_deg"])) < 0.5, "nose down after rollout")
	t.check(max_jump < 0.02, "continuous motion (max step %f nm)" % max_jump)
	t.check(r.aircraft[1].is_flying(), "other aircraft unaffected")
	t.done()


func test_crashed_aircraft_freeze(t: T) -> void:
	var r := rnd([
		ac({"x": 20.0, "y": -20.0, "alt": 600.0, "hdg": 90.0, "sel_alt": 0}),
		ac({"callsign": "FAR1", "player_id": 2, "x": 30.0, "y": 30.0, "alt": 9000.0, "sel_alt": 9000}),
	])
	var a := r.aircraft[0]
	for i in 600:
		r.step(DT)
		if a.status == "crashed":
			break
	t.eq(a.outcome, "terrain", "crashed")
	var before := r.own_view(1)
	for i in 50:
		r.step(DT)
	var after := r.own_view(1)
	for k: String in ["x", "y", "alt_true", "hdg", "pitch_deg", "bank_deg", "ias"]:
		t.eq(after[k], before[k], "frozen " + k)
	t.eq(after["gs"], 0.0, "crashed gs 0")
	t.eq(after["status"], "crashed", "status")
	t.eq(after["outcome"], "terrain", "outcome")
	t.done()
