class_name PilotFlightState
extends Node
## Smooth aircraft pose from the 10 Hz `own` samples. Samples are stamped with
## the sim time (`own.time`); a playback clock runs ~INTERP_DELAY behind the
## newest sample and is slewed (not snapped) towards it, so network jitter and
## lost packets do not show. Between samples position/attitude are
## interpolated; past the newest sample they are extrapolated from gs/hdg/vs
## for up to MAX_EXTRAPOLATE. A crash freezes the pose.
## Also owns the debug override (--pilot-debug-pos) used for screenshots.

signal sample(own: Dictionary)
signal touchdown(sink_fpm: float)
signal crashed(outcome: String)
signal landed()

const INTERP_DELAY := 0.1
const MAX_EXTRAPOLATE := 0.6
const MAX_SAMPLES := 8

## Interpolated state (sim units): x/y nm, alt ft (true), hdg deg, pitch/bank deg.
var x := 12.0
var y := 0.0
var alt := 3000.0
var hdg := 270.0
var pitch := 0.0
var bank := 0.0
var gs := 180.0
var vs := 0.0
var on_ground := false
## Latest raw `own` for the instruments (possibly debug-overridden).
var own: Dictionary = {}
var has_data := false
var status := "flying"
var outcome := ""

var _samples: Array[Dictionary] = []
var _clock := -1.0
var _last_sink := 0.0
var _debug: Dictionary = {}


func _ready() -> void:
	process_priority = -20
	Session.own_updated.connect(_on_own)
	if not Session.own.is_empty():
		_on_own(Session.own)


## Place the aircraft at a fixed point on the final approach for screenshots:
## dme nm from the threshold on the extended centreline, height ft above the field.
func set_debug_pose(dme: float, height_ft: float) -> void:
	_debug = {"dme": dme, "height": height_ft}


func _on_own(o: Dictionary) -> void:
	if o.is_empty():
		return
	var s := o.duplicate()
	if not _debug.is_empty():
		s = _apply_debug(s)
	own = s
	has_data = true
	var prev_status := status
	status = String(s.get("status", "flying"))
	outcome = String(s.get("outcome", ""))
	var t := float(s.get("time", 0.0))
	if not _samples.is_empty() and t <= float(_samples[-1]["time"]):
		# Same tick delivered twice or out of order: keep the newest data for the panel only.
		sample.emit(own)
		return
	_samples.append({
		"time": t, "x": float(s.get("x", 0.0)), "y": float(s.get("y", 0.0)),
		"alt": float(s.get("alt_true", 0.0)), "hdg": float(s.get("hdg", 0.0)),
		"pitch": float(s.get("pitch_deg", 0.0)), "bank": float(s.get("bank_deg", 0.0)),
		"gs": float(s.get("gs", 0.0)), "vs": float(s.get("vs", 0.0)),
		"ground": bool(s.get("on_ground", false)),
	})
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
	if _clock < 0.0 or absf(_clock - (t - INTERP_DELAY)) > 2.0:
		_clock = t - INTERP_DELAY
	if prev_status == "flying" and status == "crashed":
		crashed.emit(outcome)
	elif prev_status == "flying" and status == "landed":
		landed.emit()
	sample.emit(own)


func _process(delta: float) -> void:
	if _samples.is_empty():
		return
	if status == "crashed":
		_set_from(_samples[-1])
		return
	var newest := float(_samples[-1]["time"])
	var target := newest - INTERP_DELAY
	_clock += delta
	# Slew the playback clock towards its target: ±5 % rate, hard limits on drift.
	var err := target - _clock
	_clock += clampf(err, -0.1 * delta, 0.1 * delta)
	_clock = clampf(_clock, target - 0.4, newest + MAX_EXTRAPOLATE)
	var was_ground := on_ground
	_evaluate(_clock)
	if on_ground and not was_ground:
		touchdown.emit(_last_sink)
	if not on_ground:
		_last_sink = vs


func _evaluate(t: float) -> void:
	var n := _samples.size()
	if n == 1 or t <= float(_samples[0]["time"]):
		_set_from(_samples[0] if t <= float(_samples[0]["time"]) else _samples[-1])
		return
	for i in range(n - 1, 0, -1):
		var a: Dictionary = _samples[i - 1]
		var b: Dictionary = _samples[i]
		var ta := float(a["time"])
		var tb := float(b["time"])
		if t >= ta and t <= tb:
			_lerp_samples(a, b, (t - ta) / maxf(tb - ta, 1e-4))
			return
	_extrapolate(_samples[-1], t - float(_samples[-1]["time"]))


func _set_from(s: Dictionary) -> void:
	x = s["x"]
	y = s["y"]
	alt = s["alt"]
	hdg = s["hdg"]
	pitch = s["pitch"]
	bank = s["bank"]
	gs = s["gs"]
	vs = s["vs"]
	on_ground = s["ground"]


func _lerp_samples(a: Dictionary, b: Dictionary, k: float) -> void:
	x = lerpf(a["x"], b["x"], k)
	y = lerpf(a["y"], b["y"], k)
	alt = lerpf(a["alt"], b["alt"], k)
	hdg = fposmod(float(a["hdg"]) + wrapf(float(b["hdg"]) - float(a["hdg"]), -180.0, 180.0) * k, 360.0)
	pitch = lerpf(a["pitch"], b["pitch"], k)
	bank = lerpf(a["bank"], b["bank"], k)
	gs = lerpf(a["gs"], b["gs"], k)
	vs = lerpf(a["vs"], b["vs"], k)
	on_ground = b["ground"] if k > 0.5 else a["ground"]


func _extrapolate(s: Dictionary, dt: float) -> void:
	_set_from(s)
	dt = minf(dt, MAX_EXTRAPOLATE)
	var nm := float(s["gs"]) / 3600.0 * dt
	var h := deg_to_rad(float(s["hdg"]))
	x += sin(h) * nm
	y += cos(h) * nm
	if not bool(s["ground"]):
		alt += float(s["vs"]) / 60.0 * dt


## World-space (Godot) position of the eye point.
func eye_position() -> Vector3:
	return World.to_3d(x, y, alt) + Vector3(0.0, CockpitLayout.EYE_HEIGHT_ABOVE_WHEELS_M, 0.0)


## Aircraft attitude as a Basis in the Godot world frame.
func attitude() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(pitch), World.heading_to_rot_y(hdg), -deg_to_rad(bank)))


## Height of the wheels above the field, ft.
func height_above_field() -> float:
	return alt - float(World.DATA["field_elev_ft"])


## Overwrite the pose-related fields of a sample with a stabilised approach at
## the debug point (keeps the sim's time and everything else).
func _apply_debug(s: Dictionary) -> Dictionary:
	var dme := float(_debug["dme"])
	var h := float(_debug["height"])
	var field := float(World.DATA["field_elev_ft"])
	var qnh := int(Session.atis.get("qnh", 1013))
	s["x"] = dme
	s["y"] = 0.0
	s["alt_true"] = field + h
	s["ind_alt"] = int(round(field + h + (int(s.get("alt_setting", qnh)) - qnh) * 27.0))
	s["rad_alt"] = int(round(h)) if h < 2500.0 else null
	s["hdg"] = 270.0
	s["dme"] = snappedf(dme, 0.1)
	s["bearing_to_station"] = 270
	s["ias"] = 138.0 if dme < 6.0 else float(s.get("ias", 180.0))
	s["gs"] = 140.0
	s["vs"] = -740
	s["pitch_deg"] = 2.2
	s["bank_deg"] = 0.0
	s["on_ground"] = h <= 0.0
	s["loc_dev"] = 0.02
	s["gs_dev"] = -0.04
	s["ap_mode"] = "APP"
	s["gs_captured"] = true
	s["app_armed"] = true
	s["gear_down"] = dme < 6.0
	s["flaps"] = 3 if dme < 6.0 else int(s.get("flaps", 1))
	s["status"] = "flying" if String(s.get("status", "flying")) == "landed" else String(s.get("status", "flying"))
	return s
