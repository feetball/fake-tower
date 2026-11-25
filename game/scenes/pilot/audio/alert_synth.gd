class_name PilotAlertSynth
extends RefCounted
## Synthesised flight-deck alerts, sample by sample (no audio files):
##   PULL UP       "whoop whoop": two rising sweeps, then a gap
##   TERRAIN       two-tone warble
##   TOO LOW GEAR  three short square beeps
##   LOW FUEL      a single chime every few seconds
## plus one-shot clicks for knobs and switches. Priority: the highest active
## alert plays; switching restarts its cycle.

const PRIORITY: Array[String] = ["PULL UP", "TERRAIN", "TOO LOW GEAR", "LOW FUEL"]

var rate := 22050.0
var active := ""
var gain := 0.5

var _t := 0.0
var _phase := 0.0
var _click_env := 0.0
var _click_pitch := 2000.0
var _click_phase := 0.0


func set_warnings(w: Array) -> void:
	var top := ""
	for p in PRIORITY:
		if w.has(p):
			top = p
			break
	if top != active:
		active = top
		_t = 0.0


func click(strong: bool = false) -> void:
	_click_env = 1.0 if strong else 0.55
	_click_pitch = 1400.0 if strong else 2600.0


func sample() -> float:
	var dt := 1.0 / rate
	var s := 0.0
	match active:
		"PULL UP":
			s = _whoop()
		"TERRAIN":
			s = _warble()
		"TOO LOW GEAR":
			s = _beeps()
		"LOW FUEL":
			s = _chime()
	_t += dt
	if _click_env > 0.001:
		_click_phase += _click_pitch * dt
		s += sin(_click_phase * TAU) * _click_env * 0.25 + (randf() - 0.5) * _click_env * 0.3
		_click_env *= 0.9965 - 0.004
	return s * gain


func _osc(freq: float) -> float:
	_phase = fmod(_phase + freq / rate, 1.0)
	# Rounded square: buzzy like a real aural warning generator, not harsh.
	return clampf(sin(_phase * TAU) * 2.2, -1.0, 1.0)


func _whoop() -> float:
	var cyc := fmod(_t, 1.9)
	var k := -1.0
	if cyc < 0.42:
		k = cyc / 0.42
	elif cyc > 0.5 and cyc < 0.92:
		k = (cyc - 0.5) / 0.42
	if k < 0.0:
		return 0.0
	var f := 380.0 + 900.0 * k * k
	var env := smoothstep(0.0, 0.04, k) * smoothstep(1.0, 0.9, k)
	return _osc(f) * env * 0.8


func _warble() -> float:
	var cyc := fmod(_t, 1.6)
	if cyc > 1.1:
		return 0.0
	var f := 820.0 if fmod(cyc, 0.25) < 0.125 else 620.0
	return _osc(f) * 0.55 * smoothstep(1.1, 1.05, cyc)


func _beeps() -> float:
	var cyc := fmod(_t, 1.8)
	var b := fmod(cyc, 0.22)
	if cyc > 0.66 or b > 0.13:
		return 0.0
	return _osc(1000.0) * 0.5


func _chime() -> float:
	var cyc := fmod(_t, 5.0)
	if cyc > 1.6:
		return 0.0
	var env := exp(-cyc * 3.2)
	_phase = fmod(_phase + 1046.5 / rate, 1.0)
	return (sin(_phase * TAU) + 0.5 * sin(_phase * TAU * 2.76) + 0.25 * sin(_phase * TAU * 5.4)) * env * 0.45
