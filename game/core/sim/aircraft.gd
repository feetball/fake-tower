extends RefCounted
## One aircraft: kinematic state, autopilot, altimetry, ILS, fuel and GPWS.
## Port of src/shared/sim/aircraft.ts. Pure and deterministic: advances only via step(dt).
## Additions for the 3D view (not in the TS version): attitude (pitch/bank) and a
## kinematic flare/touchdown/rollout after a successful landing (see attitude.gd).

const Geo := preload("res://core/sim/geo.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")
const Attitude := preload("res://core/sim/attitude.gd")

const MIN_SPD: Array[int] = [200, 180, 160, 135] ## by flap setting
const MAX_SPD := 250
const TURN_RATE_DEG_S := 3.0
const CLIMB_FPM := 1800.0
const DESCENT_FPM := 1800.0
const MAX_DESCENT_FPM := 2500.0
const ACCEL_KT_S := 1.5
const VS_ACCEL_FPM_S := 400.0
const MIN_ALT_SEL := 0
const MAX_ALT_SEL := 20000
const MIN_ALT_SETTING := 950
const MAX_ALT_SETTING := 1050
## Altimeter error: ft of indicated altitude per hPa of setting error.
const FT_PER_HPA := 27.0

const LANDING_MAX_IAS := 155.0
const GPWS_LOOKAHEAD_S := 30
const GPWS_PULLUP_S := 12
const RADALT_MAX := 2500.0
const LOC_GAIN_DEG_PER_NM := 80.0
const LOC_MAX_CUT_DEG := 30.0
const GS_GAIN_FPM_PER_FT := 6.0

## Keys accepted in an init Dictionary (AircraftInit in the TS version).
const INIT_KEYS: Array[String] = [
	"callsign", "player_id", "x", "y", "alt", "hdg", "ias", "fuel_min",
	"sel_alt", "alt_setting", "gear_down", "flaps",
]

var callsign := ""
var player_id := 0
var x := 0.0
var y := 0.0
var alt := 0.0 ## true altitude ft MSL
var hdg := 0.0
var ias := 0.0
var vs := 0.0
var fuel_min := 0.0
var sel_hdg := 0
var sel_alt := 0
var sel_spd := 0
var app_armed := false
var loc_captured := false
var gs_captured := false
## Glideslope seen above the aircraft since LOC capture (capture from below only).
var _gs_below_seen := false
var gear_down := false
var flaps := 0
var alt_setting := 1013
var status := "flying" ## flying | landed | crashed
var outcome := "flying" ## flying | landed | terrain | collision | fuel | runway
var warnings: Array[String] = []
var att := Attitude.new()


func _init(init: Dictionary, qnh: int) -> void:
	for k: Variant in init:
		if not INIT_KEYS.has(k):
			push_error("Aircraft init: unknown key %s" % k)
	callsign = String(init["callsign"])
	player_id = int(init["player_id"])
	x = float(init["x"])
	y = float(init["y"])
	alt = float(init["alt"])
	hdg = Geo.norm360(float(init["hdg"]))
	ias = float(init["ias"])
	fuel_min = float(init["fuel_min"])
	alt_setting = int(init.get("alt_setting", 1013))
	gear_down = bool(init.get("gear_down", false))
	flaps = int(init.get("flaps", 0))
	sel_hdg = int(Geo.js_round(hdg)) % 360
	if init.has("sel_alt"):
		sel_alt = int(init["sel_alt"])
	else:
		sel_alt = int(Geo.js_round(indicated_alt(qnh) / 100.0)) * 100
	sel_spd = clampi(int(Geo.js_round(ias)), MIN_SPD[flaps], MAX_SPD)
	att.reset(self)


func is_flying() -> bool:
	return status == "flying"


## Indicated = true + (setting − QNH) × 27 ft.
func indicated_alt(qnh: int) -> float:
	return alt + float(alt_setting - qnh) * FT_PER_HPA


## True airspeed (= ground speed, no wind): +2 % per 1000 ft.
func tas() -> float:
	return ias * (1.0 + 0.02 * maxf(0.0, alt) / 1000.0)


func ap_mode() -> String:
	return "APP" if gs_captured else ("LOC" if loc_captured else "HDG")


## Apply an already type-checked autopilot command (any subset of
## hdg, alt, spd, app, gear, flaps, alt_setting), clamping every field.
func apply(cmd: Dictionary) -> void:
	if not is_flying():
		return
	if cmd.has("flaps"):
		flaps = clampi(int(Geo.js_round(float(cmd["flaps"]))), 0, 3)
	if cmd.has("gear"):
		gear_down = bool(cmd["gear"])
	if cmd.has("hdg"):
		sel_hdg = int(Geo.js_round(Geo.norm360(float(cmd["hdg"])))) % 360
	if cmd.has("alt"):
		sel_alt = clampi(int(Geo.js_round(float(cmd["alt"]) / 100.0)) * 100, MIN_ALT_SEL, MAX_ALT_SEL)
	if cmd.has("spd"):
		sel_spd = int(Geo.js_round(float(cmd["spd"])))
	if cmd.has("alt_setting"):
		alt_setting = clampi(int(Geo.js_round(float(cmd["alt_setting"]))), MIN_ALT_SETTING, MAX_ALT_SETTING)
	if cmd.has("app"):
		app_armed = bool(cmd["app"])
		if not app_armed:
			_disconnect_approach()
	# Re-clamp after any flap change too: retracting flaps raises the minimum.
	sel_spd = clampi(sel_spd, MIN_SPD[flaps], MAX_SPD)


func _disconnect_approach() -> void:
	loc_captured = false
	gs_captured = false
	_gs_below_seen = false


## Advance dt seconds. Returns an outcome if the aircraft stopped flying
## (except collisions, handled by the round), else "".
func step(dt: float, w: SimWorld, qnh: int) -> String:
	if not is_flying():
		return ""

	# --- lateral ---
	var target_hdg := float(sel_hdg)
	if loc_captured:
		# Steer to the centreline with a cut proportional to cross-track error, capped at 30°.
		var back := Geo.norm360(w.course_deg + 180.0)
		var off := Geo.angle_diff(back, Geo.bearing(0.0, 0.0, x, y))
		var xtk := Geo.hypot(x, y) * sin(off * Geo.DEG)
		target_hdg = Geo.norm360(w.course_deg + Geo.clamp_f(xtk * LOC_GAIN_DEG_PER_NM, -LOC_MAX_CUT_DEG, LOC_MAX_CUT_DEG))
	var turn_err := Geo.angle_diff(hdg, target_hdg)
	var turn_rate := Geo.clamp_f(turn_err * 1.0, -TURN_RATE_DEG_S, TURN_RATE_DEG_S)
	hdg = Geo.norm360(hdg + turn_rate * dt)

	# --- speed ---
	var target_spd := float(clampi(sel_spd, MIN_SPD[flaps], MAX_SPD))
	ias += Geo.clamp_f(target_spd - ias, -ACCEL_KT_S * dt, ACCEL_KT_S * dt)

	# --- vertical ---
	var vs_cmd: float
	if gs_captured:
		var d := Geo.hypot(x, y)
		var nominal := -(tas() / 60.0) * Geo.FT_PER_NM * tan(w.glide_deg * Geo.DEG)
		vs_cmd = Geo.clamp_f(nominal + GS_GAIN_FPM_PER_FT * (Geo.glidepath_alt(w, d) - alt), -MAX_DESCENT_FPM, CLIMB_FPM)
	else:
		# The autopilot holds INDICATED altitude, so a wrong setting puts the aircraft at the wrong true altitude.
		var err := float(sel_alt) - indicated_alt(qnh)
		var max_desc := MAX_DESCENT_FPM if err < -3000.0 else DESCENT_FPM
		vs_cmd = Geo.clamp_f(err * 5.0, -max_desc, CLIMB_FPM)
	vs += Geo.clamp_f(vs_cmd - vs, -VS_ACCEL_FPM_S * dt, VS_ACCEL_FPM_S * dt)

	# --- move ---
	var prev_x := x
	var nm := (tas() / 3600.0) * dt
	x += Geo.heading_dx(hdg) * nm
	y += Geo.heading_dy(hdg) * nm
	alt += (vs / 60.0) * dt
	fuel_min = maxf(0.0, fuel_min - dt / 60.0)
	att.update_airborne(self, dt, turn_rate)

	# --- threshold crossing, judged on the approach state we arrived with ---
	if prev_x > 0.0 and x <= 0.0 and absf(y) < 0.5 and loc_captured and gs_captured:
		var stable := gear_down and flaps == 3 and ias <= LANDING_MAX_IAS
		return finish("landed" if stable else "runway")

	# --- ILS capture (on the new position) ---
	var now := Geo.ils_deviation(w, x, y, alt)
	if loc_captured and not now.valid:
		_disconnect_approach() # flew out of coverage
	if app_armed and not loc_captured and now.valid:
		var intercept := absf(Geo.angle_diff(hdg, w.course_deg))
		if absf(now.loc) < 2.5 and intercept <= 90.0:
			loc_captured = true
	if loc_captured and not gs_captured and now.valid:
		if now.gs > 0.05:
			_gs_below_seen = true
		elif _gs_below_seen:
			gs_captured = true

	# --- outcomes ---
	if alt < Geo.terrain_elev_at(w, x, y):
		return finish("terrain")
	if fuel_min <= 0.0:
		return finish("fuel")
	return ""


## End the flight. A landed aircraft keeps its vertical speed (unlike the TS
## version, which zeroes it) because the rollout animation continues from it.
func finish(result: String) -> String:
	status = "landed" if result == "landed" else "crashed"
	outcome = result
	if status != "landed":
		vs = 0.0
	warnings = []
	return result


## After a successful landing: flare, touchdown and rollout (kinematic, view only).
func animate_landed(dt: float, w: SimWorld) -> void:
	if status == "landed":
		att.update_rollout(self, dt, w)


func rad_alt(w: SimWorld) -> Variant:
	var agl := alt - Geo.terrain_elev_at(w, x, y)
	return maxf(0.0, agl) if agl < RADALT_MAX else null


## Seconds until the straight-line projected flight path hits terrain, or -1 within the look-ahead.
func _seconds_to_impact(w: SimWorld) -> int:
	# Established and descending to the runway: only obstacles count, not the ground ahead.
	var established := loc_captured and gs_captured
	var dx := Geo.heading_dx(hdg)
	var dy := Geo.heading_dy(hdg)
	var nm_per_s := tas() / 3600.0
	for t in range(1, GPWS_LOOKAHEAD_S + 1):
		var px := x + dx * nm_per_s * t
		var py := y + dy * nm_per_s * t
		var pa := alt + (vs / 60.0) * t
		var ground := Geo.obstacle_elev_at(w, px, py) if established else Geo.terrain_elev_at(w, px, py)
		if pa < ground:
			return t
	return -1


func update_warnings(w: SimWorld) -> void:
	if not is_flying():
		warnings = []
		return
	var out: Array[String] = []
	var tti := _seconds_to_impact(w)
	if tti >= 0:
		out.append("TERRAIN")
		if tti <= GPWS_PULLUP_S:
			out.append("PULL UP")
	var ra: Variant = rad_alt(w)
	if ra != null and float(ra) < 500.0 and not gear_down:
		out.append("TOO LOW GEAR")
	if fuel_min < 5.0:
		out.append("LOW FUEL")
	warnings = out


static func _r1(v: float) -> float:
	return Geo.js_round(v * 10.0) / 10.0


static func _r2(v: float) -> float:
	return Geo.js_round(v * 100.0) / 100.0


## The contract `own` shape (without `time`, which the round adds).
func own_view(w: SimWorld, qnh: int) -> Dictionary:
	var ils := Geo.ils_deviation(w, x, y, alt) if is_flying() else Geo.IlsDev.new()
	var ra: Variant = rad_alt(w)
	return {
		"callsign": callsign,
		"status": status,
		"outcome": "" if outcome == "flying" else outcome,
		"hdg": fmod(_r1(hdg), 360.0),
		"ias": _r1(ias),
		"ind_alt": int(Geo.js_round(indicated_alt(qnh))),
		"rad_alt": null if ra == null else int(Geo.js_round(float(ra))),
		"vs": int(Geo.js_round(vs / 10.0)) * 10,
		"fuel_min": _r1(fuel_min),
		"dme": _r1(Geo.hypot(x, y)),
		"bearing_to_station": int(Geo.js_round(Geo.bearing(x, y, 0.0, 0.0))) % 360,
		"loc_dev": _r2(ils.loc) if ils.valid else null,
		"gs_dev": _r2(ils.gs) if ils.valid else null,
		"sel_hdg": sel_hdg,
		"sel_alt": sel_alt,
		"sel_spd": sel_spd,
		"app_armed": app_armed,
		"ap_mode": ap_mode(),
		"gs_captured": gs_captured,
		"gear_down": gear_down,
		"flaps": flaps,
		"alt_setting": alt_setting,
		"warnings": warnings.duplicate(),
		"x": x,
		"y": y,
		"alt_true": alt,
		"gs": 0.0 if att.stopped else tas(),
		"pitch_deg": att.pitch_deg,
		"bank_deg": att.bank_deg,
		"on_ground": att.on_ground,
	}


## The contract `radar target` shape.
func radar_view(conflict: bool, msaw: bool) -> Dictionary:
	var trend := 0
	if vs > 300.0:
		trend = 1
	elif vs < -300.0:
		trend = -1
	return {
		"callsign": callsign,
		"x": Geo.js_round(x * 1000.0) / 1000.0,
		"y": Geo.js_round(y * 1000.0) / 1000.0,
		"alt": int(Geo.js_round(alt / 100.0)) * 100,
		"gs": int(Geo.js_round(tas())) if is_flying() else 0,
		"track": int(Geo.js_round(hdg)) % 360,
		"vs_trend": trend,
		"status": status,
		"conflict": conflict,
		"msaw": msaw,
	}
