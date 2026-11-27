class_name PilotCockpitAudio
extends AudioStreamPlayer
## Procedural flight-deck sound, synthesised into an AudioStreamGenerator:
## engine hum and fan whine following N1, slipstream noise rising with
## airspeed (more with the gear down), rain patter on the windshield, gear and
## flap motors with clunks, touchdown thump, rollout rumble and reverse roar,
## and the aural alerts (PilotAlertSynth). A crash cuts everything to a low
## boom; fuel exhaustion spools the engines down first.

const RATE := 22050.0
const MAX_FRAMES := 2048

var avionics: PilotAvionicsBus
var flight: PilotFlightState
var wetness := 0.5
var alerts := PilotAlertSynth.new()

var _pb: AudioStreamGeneratorPlayback
# Filter / oscillator state.
var _lp_engine := 0.0
var _lp_wind := 0.0
var _bp_wind := 0.0
var _lp_rumble := 0.0
var _lp_boom := 0.0
var _ph_fan := 0.0
var _ph_core := 0.0
var _ph_motor := 0.0
# Control values (smoothed per block).
var _eng := 0.0
var _n1 := 0.0
var _wind := 0.0
var _rumble := 0.0
var _reverse := 0.0
var _motor := 0.0
var _thump := 0.0
var _clunk := 0.0
var _boom := 0.0
var _dead := false
var _master := 1.0
var _prev_gear := -1.0
var _prev_flap := -1.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	stream = gen
	volume_db = -6.0
	alerts.rate = RATE
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback


func touchdown(sink_fpm: float) -> void:
	_thump = clampf(0.6 + absf(sink_fpm) / 600.0, 0.6, 1.4)
	_reverse = 1.0


func crash(outcome: String) -> void:
	if outcome == "fuel":
		# Engines run down first; the view cuts to black when they are quiet.
		_dead = true
		return
	_boom = 1.0
	_dead = true
	_master = 0.0


func click(strong: bool = false) -> void:
	alerts.click(strong)


func _process(delta: float) -> void:
	if avionics == null or _pb == null:
		return
	var own := avionics.own
	var crashed := String(own.get("status", "flying")) == "crashed"
	# Smooth the controls.
	var k := 1.0 - exp(-delta * 4.0)
	_n1 = lerpf(_n1, (avionics.n1[0] + avionics.n1[1]) * 0.5, k)
	_eng = clampf(_n1 / 90.0, 0.0, 1.1)
	var spd := avionics.ias if not bool(own.get("on_ground", false)) or avionics.ias > 1.0 else 0.0
	var w := clampf(spd / 250.0, 0.0, 1.2)
	_wind = lerpf(_wind, w * w * (1.0 + avionics.gear_pos * 0.35 + avionics.flap_pos * 0.06), k)
	var on_ground := bool(own.get("on_ground", false))
	_rumble = lerpf(_rumble, clampf(avionics.ias / 130.0, 0.0, 1.0) if on_ground else 0.0, k)
	_reverse = maxf(0.0, _reverse - delta / 9.0) if on_ground else 0.0
	# Gear and flap actuation.
	var gear_moving := avionics.gear_pos > 0.001 and avionics.gear_pos < 0.999
	var flap_moving := absf(avionics.flap_pos - float(own.get("flaps", 0))) > 0.005
	_motor = lerpf(_motor, (0.6 if gear_moving else 0.0) + (0.35 if flap_moving else 0.0), k)
	if _prev_gear >= 0.0:
		var locked_now := avionics.gear_pos <= 0.001 or avionics.gear_pos >= 0.999
		var locked_before := _prev_gear <= 0.001 or _prev_gear >= 0.999
		if locked_now != locked_before:
			_clunk = 1.0
	_prev_gear = avionics.gear_pos
	_prev_flap = avionics.flap_pos
	alerts.set_warnings([] if crashed else avionics.warnings)
	if _dead and _boom <= 0.0 and _n1 < 2.0:
		_master = maxf(0.0, _master - delta)
	_fill()


func _fill() -> void:
	var n := mini(_pb.get_frames_available(), MAX_FRAMES)
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	var fan_f := 60.0 + _n1 * 7.5
	var core_f := 28.0 + _n1 * 1.4
	var eng_g := _eng * 0.22
	var wind_g := _wind * 0.32
	var wind_cut := 0.04 + _wind * 0.1
	var rain_rate := wetness * (0.3 + _wind) * 0.004
	var motor_g := _motor * 0.06
	# Settings > Ambient noise scales the flight-deck sound; alerts and the crash stay full.
	var ambient := _master * UiSettings.ambient_volume()
	for i in n:
		var white := randf() * 2.0 - 1.0
		# Engine: low rumble (heavily filtered noise) + fan tone + core hum.
		_lp_engine += (white - _lp_engine) * 0.02
		_ph_fan = fmod(_ph_fan + fan_f * dt, 1.0)
		_ph_core = fmod(_ph_core + core_f * dt, 1.0)
		var engine := _lp_engine * 3.0 + sin(_ph_fan * TAU) * 0.08 + sin(_ph_core * TAU) * 0.25
		# Slipstream: band-limited noise, brighter with speed.
		_lp_wind += (white - _lp_wind) * wind_cut
		_bp_wind += (_lp_wind - _bp_wind) * 0.01
		var wind := (_lp_wind - _bp_wind) * 2.5
		# Rain: sparse ticks on the glass.
		var rain := (randf() * 2.0 - 1.0) * 0.5 if randf() < rain_rate else 0.0
		# Ground rumble and reverse roar.
		_lp_rumble += (white - _lp_rumble) * 0.012
		var ground := _lp_rumble * (4.0 * _rumble + 5.0 * _reverse)
		# Hydraulic motor whine.
		_ph_motor = fmod(_ph_motor + (320.0 + sin(_ph_core * TAU) * 6.0) * dt, 1.0)
		var motor := (sin(_ph_motor * TAU) + 0.4 * sin(_ph_motor * TAU * 3.0)) * motor_g
		# Thump / clunk / boom transients.
		var trans := 0.0
		if _thump > 0.001:
			trans += sin(_ph_core * TAU * 1.7) * _thump * 0.9 + white * _thump * 0.25
			_thump *= 0.9993
		if _clunk > 0.001:
			trans += (white * 0.5 + sin(_ph_motor * TAU * 0.3)) * _clunk * 0.35
			_clunk *= 0.9975
		var boom := 0.0
		if _boom > 0.0005:
			_lp_boom += (white - _lp_boom) * 0.006
			boom = _lp_boom * 9.0 * _boom
			_boom *= 0.99985
		var s := (engine * eng_g + wind * wind_g + rain * wetness + ground + motor + trans) * ambient
		s += boom + alerts.sample() * (1.0 if _master > 0.0 else 0.0)
		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)
