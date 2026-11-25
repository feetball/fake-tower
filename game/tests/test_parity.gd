extends RefCounted
## Parity with the TypeScript reference sim. The fixture (scenarios + expected
## trajectories) is produced by tests/tools/gen_parity.ts; see that file to regenerate.

const T := preload("res://tests/lib/t.gd")
const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const Geo := preload("res://core/sim/geo.gd")

const FIXTURE := "res://tests/fixtures/parity.json"
## Tolerances for the continuous state after up to ~10 simulated minutes.
const TOL_NM := 1e-6
const TOL_FT := 1e-4
const TOL_DEG := 1e-6
const TOL_KT := 1e-6
const TOL_FPM := 1e-4
const TOL_MIN := 1e-9

var _fx: Dictionary = {}


func _fixture() -> Dictionary:
	if _fx.is_empty():
		_fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _fx


static func snake(k: String) -> String:
	return k.to_snake_case()


func test_rng_sequences_bit_identical(t: T) -> void:
	for s: Dictionary in _fixture()["rng"]:
		var g := SimRng.new(int(s["seed"]))
		var i := 0
		for v: float in s["u32"]:
			t.eq(int(g.next_float() * 4294967296.0), int(v), "seed %d value %d" % [int(s["seed"]), i])
			i += 1
	t.done()


func test_spawns_and_atis_match(t: T) -> void:
	for s: Dictionary in _fixture()["spawns"]:
		var ids: Array[int] = []
		for i in int(s["pilots"]):
			ids.append(i + 1)
		var r := SimRound.new(SimRng.new(int(s["seed"])), ids)
		var tag := "seed %d" % int(s["seed"])
		t.eq(r.qnh, int(s["qnh"]), tag + " qnh")
		var atis: Dictionary = s["atis"]
		for k: String in atis:
			var want: Variant = atis[k]
			var got: Variant = r.atis[snake(k)]
			t.check(str(got) == str(want) or (typeof(want) == TYPE_FLOAT and float(got) == want), "%s atis.%s: %s vs %s" % [tag, k, got, want])
		var exp: Array = s["aircraft"]
		t.eq(r.aircraft.size(), exp.size(), tag + " count")
		for i in mini(exp.size(), r.aircraft.size()):
			var e: Dictionary = exp[i]
			var a := r.aircraft[i]
			t.eq(a.callsign, e["callsign"], tag + " callsign")
			t.near(a.x, e["x"], 1e-9, tag + " x")
			t.near(a.y, e["y"], 1e-9, tag + " y")
			t.near(a.alt, e["alt"], 1e-9, tag + " alt")
			t.near(a.hdg, e["hdg"], 1e-9, tag + " hdg")
			t.near(a.fuel_min, e["fuel_min"], 1e-9, tag + " fuel")
			t.eq(a.sel_alt, int(e["sel_alt"]), tag + " sel_alt")
	t.done()


func test_scenario_trajectories(t: T) -> void:
	var worst := {"nm": 0.0, "ft": 0.0, "deg": 0.0, "kt": 0.0, "fpm": 0.0}
	for s: Dictionary in _fixture()["scenarios"]:
		_run_scenario(t, s, worst)
	var parts: Array[String] = []
	for k: String in worst:
		parts.append("%s %s" % [k, String.num_scientific(worst[k])])
	print("     parity max |Δ|: " + ", ".join(parts))
	t.done()


func _run_scenario(t: T, s: Dictionary, worst: Dictionary) -> void:
	var name: String = s["name"]
	var inits: Array[Dictionary] = []
	for i: Dictionary in s["inits"]:
		var d := i.duplicate()
		for k: String in ["player_id", "alt_setting", "sel_alt", "flaps"]:
			if d.has(k):
				d[k] = int(d[k])
		inits.append(d)
	var r := SimRound.new(SimRng.new(1), [], int(s["qnh"]), inits)
	var samples: Array = s["samples"]
	var si := 0
	var events: Array = []
	var steps := int(s["steps"])
	for n in steps + 1:
		for c: Dictionary in s["schedule"]:
			if int(c["step"]) == n:
				r.aircraft[int(c["ac"])].apply(c["cmd"])
		if si < samples.size() and int(samples[si]["step"]) == n:
			_compare(t, "%s step %d" % [name, n], r, samples[si], worst)
			si += 1
		if n == steps or r.is_finished():
			break
		events.append_array(r.step(0.1))
	t.eq(si, samples.size(), name + " all samples reached")
	t.eq(JSON.stringify(events), JSON.stringify(s["events"]), name + " events")


func _compare(t: T, tag: String, r: SimRound, smp: Dictionary, worst: Dictionary) -> void:
	t.near(r.time, smp["time"], 1e-9, tag + " time")
	var exp_ac: Array = smp["ac"]
	for i in exp_ac.size():
		var e: Dictionary = exp_ac[i]
		var a := r.aircraft[i]
		var dpos := maxf(absf(a.x - float(e["x"])), absf(a.y - float(e["y"])))
		var dalt := absf(a.alt - float(e["alt"]))
		var dhdg := absf(Geo.angle_diff(a.hdg, float(e["hdg"])))
		var dias := absf(a.ias - float(e["ias"]))
		var dvs := absf(a.vs - float(e["vs"]))
		worst["nm"] = maxf(worst["nm"], dpos)
		worst["ft"] = maxf(worst["ft"], dalt)
		worst["deg"] = maxf(worst["deg"], dhdg)
		worst["kt"] = maxf(worst["kt"], dias)
		if a.status != "landed":
			worst["fpm"] = maxf(worst["fpm"], dvs)
		t.check(dpos <= TOL_NM, "%s ac%d position off by %s nm" % [tag, i, String.num_scientific(dpos)])
		t.check(dalt <= TOL_FT, "%s ac%d alt off by %s ft" % [tag, i, String.num_scientific(dalt)])
		t.check(dhdg <= TOL_DEG, "%s ac%d hdg off by %s" % [tag, i, String.num_scientific(dhdg)])
		t.check(dias <= TOL_KT, "%s ac%d ias off by %s" % [tag, i, String.num_scientific(dias)])
		# The GDScript aircraft keeps its vertical speed after landing (rollout animation).
		if a.status != "landed":
			t.check(dvs <= TOL_FPM, "%s ac%d vs off by %s" % [tag, i, String.num_scientific(dvs)])
		t.near(a.fuel_min, e["fuel_min"], TOL_MIN, tag + " fuel")
		t.eq(a.status, e["status"], tag + " status")
		t.eq(a.outcome, e["outcome"], tag + " outcome")
		t.eq(a.ap_mode(), e["ap_mode"], tag + " ap_mode")
		t.eq(JSON.stringify(a.warnings), JSON.stringify(e["warnings"]), tag + " warnings")
	# Rounded views must match field for field (keys camelCase in TS, snake_case here).
	var radar := r.radar()
	var exp_radar: Array = smp["radar"]
	for i in exp_radar.size():
		_compare_view(t, "%s radar[%d]" % [tag, i], radar[i], exp_radar[i])
	var exp_own: Array = smp["own"]
	for i in exp_own.size():
		var own := r.own_view(r.aircraft[i].player_id)
		if r.aircraft[i].status == "landed":
			own["vs"] = 0 # see above: TS zeroes vs on landing
		_compare_view(t, "%s own[%d]" % [tag, i], own, exp_own[i])


func _compare_view(t: T, tag: String, got: Dictionary, want: Dictionary) -> void:
	for k: String in want:
		var gk := snake(k)
		if not got.has(gk):
			t.check(false, "%s missing %s" % [tag, gk])
			continue
		var g: Variant = got[gk]
		var w: Variant = want[k]
		if typeof(w) == TYPE_FLOAT:
			t.check(g != null and absf(float(g) - w) < 1e-9, "%s.%s: %s vs %s" % [tag, gk, g, w])
		elif typeof(w) == TYPE_ARRAY:
			t.eq(JSON.stringify(g), JSON.stringify(w), "%s.%s" % [tag, gk])
		else:
			t.eq(g, w, "%s.%s" % [tag, gk])
	# TS omits `outcome` while flying; the contract sends "".
	if not want.has("outcome") and got.has("outcome") and got.has("callsign") and got.has("ap_mode"):
		t.eq(got["outcome"], "", tag + ".outcome")
