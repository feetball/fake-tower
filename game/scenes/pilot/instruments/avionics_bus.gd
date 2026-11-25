class_name PilotAvionicsBus
extends Node
## Data source for every display: the latest `own`, values smoothed between
## the 10 Hz samples (tapes must not step), commanded selections from the
## autopilot panel, FMA change times, gear/flap actuation animation and a
## plausible engine model (N1 from speed changes, climb, drag configuration).

const GEAR_TRANSIT_S := 7.0
const FLAP_S_PER_DETENT := 4.5
const FLAP_MIN: Array[int] = [200, 180, 160, 135]

var flight: PilotFlightState
var ap: PilotAutopilot
var own: Dictionary = {}

var ias := 0.0
var ias_trend := 0.0 ## kt per 10 s
var ind_alt := 0.0
var vs := 0.0
var rad_alt := -1.0 ## -1 = no radio altitude (above 2500 ft)
var hdg := 0.0
var pitch := 0.0
var bank := 0.0
## Gear: 0 = up and locked, 1 = down and locked, in between = in transit.
var gear_pos := 0.0
var gear_target := 0.0
var flap_pos := 0.0
var n1: Array[float] = [25.0, 25.0]
var engines_running := true
var warnings: Array = []
var debug_warnings: Array = []
## FMA: active modes per column and the time each last changed (s since start).
var fma: Array[String] = ["", "", ""]
var fma_changed: Array[float] = [-99.0, -99.0, -99.0]
var now := 0.0

var _prev_ias := 0.0
var _have := false


func _ready() -> void:
	process_priority = -10


func _process(delta: float) -> void:
	now += delta
	if flight == null or not flight.has_data:
		return
	own = flight.own
	var k := 1.0 - exp(-delta * 6.0)
	var t_ias := float(own.get("ias", 0.0))
	var t_alt := float(own.get("ind_alt", 0.0))
	var t_vs := float(own.get("vs", 0.0))
	if not _have:
		ias = t_ias
		ind_alt = t_alt
		vs = t_vs
		gear_pos = 1.0 if own.get("gear_down", false) else 0.0
		flap_pos = float(own.get("flaps", 0))
		_have = true
	# Altitude: follow the interpolated true altitude so the tape glides, with
	# the indicated offset (altimeter setting) taken from the latest sample.
	var offset := t_alt - float(own.get("alt_true", t_alt))
	ind_alt = lerpf(ind_alt, flight.alt + offset, 1.0 - exp(-delta * 12.0))
	ias = lerpf(ias, t_ias, k)
	vs = lerpf(vs, t_vs, k)
	var accel := (ias - _prev_ias) / maxf(delta, 1e-3)
	_prev_ias = ias
	ias_trend = lerpf(ias_trend, accel * 10.0, 1.0 - exp(-delta * 1.5))
	var ra: Variant = own.get("rad_alt", null)
	if ra == null:
		rad_alt = -1.0
	else:
		var tra := float(ra)
		rad_alt = tra if rad_alt < 0.0 else lerpf(rad_alt, tra, k)
	hdg = flight.hdg
	pitch = flight.pitch
	bank = flight.bank
	_animate_config(delta)
	_engines(delta)
	_update_fma()
	warnings = debug_warnings if not debug_warnings.is_empty() else own.get("warnings", [])


func _animate_config(delta: float) -> void:
	gear_target = 1.0 if own.get("gear_down", false) else 0.0
	gear_pos = move_toward(gear_pos, gear_target, delta / GEAR_TRANSIT_S)
	flap_pos = move_toward(flap_pos, float(own.get("flaps", 0)), delta / FLAP_S_PER_DETENT)


## Thrust needed: drag rises with speed, flaps and gear; climbing and
## accelerating need more, descending less. Spools with a few seconds of lag.
func _engines(delta: float) -> void:
	var status := String(own.get("status", "flying"))
	var fuel := float(own.get("fuel_min", 10.0))
	engines_running = status != "crashed" and fuel > 0.0
	var target := 24.0
	if engines_running and not bool(own.get("on_ground", false)):
		var drag := 38.0 + (ias - 140.0) * 0.12 + flap_pos * 3.5 + gear_pos * 6.0
		var climb := vs / 2000.0 * 30.0
		var acc := clampf(ias_trend, -15.0, 15.0) * 1.6
		target = clampf(drag + climb + acc, 26.0, 92.0)
	elif engines_running:
		# Rollout: reversers / idle reverse right after touchdown, then idle.
		target = 70.0 if ias > 70.0 else 22.0
	else:
		target = 0.0 if status == "crashed" else 9.0 # windmilling
	for i in 2:
		var spool := 0.25 if target > n1[i] else 0.35
		n1[i] = lerpf(n1[i], target + (0.6 if i == 1 else 0.0), 1.0 - exp(-delta * spool))


func _update_fma() -> void:
	var mode := String(own.get("ap_mode", "HDG"))
	var lat := "HDG SEL" if mode == "HDG" else "LOC"
	var vert := "G/S" if bool(own.get("gs_captured", false)) else _vert_mode()
	var cols: Array[String] = ["SPEED", lat, vert]
	for i in 3:
		if cols[i] != fma[i]:
			if fma[i] != "":
				fma_changed[i] = now
			fma[i] = cols[i]


func _vert_mode() -> String:
	var sel := float(own.get("sel_alt", 0))
	var alt := float(own.get("ind_alt", 0))
	if absf(alt - sel) < 60.0 and absf(float(own.get("vs", 0))) < 300.0:
		return "ALT"
	if absf(alt - sel) < 600.0:
		return "ALT*"
	return "CLB" if sel > alt else "DES"


func sel(k: String) -> int:
	if ap != null:
		return ap.display_value(k)
	return int(own.get(PilotAutopilot.SERVER_KEY[k], 0))


func flap_min() -> int:
	return FLAP_MIN[clampi(int(own.get("flaps", 0)), 0, 3)]


func has_warning(w: String) -> bool:
	return warnings.has(w)
