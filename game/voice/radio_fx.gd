extends RefCounted
## Radio sound: bus/effect construction (in code) and a procedural generator for
## static, noise bed, heterodyne squeal and squelch bursts. No asset files.

const BUS_CAPTURE := "MicCapture"
const BUS_CLEAN := "VoiceClean"
const BUS_RADIO := "Radio"

const STATIC_LEVEL := 0.012
const BED_LEVEL := 0.035
const SQUEAL_LEVEL := 0.16
const SQUEAL_F1 := 1480.0
const SQUEAL_F2 := 1870.0
const SQUEAL_WOBBLE_HZ := 35.0
const SQUEAL_LFO_HZ := 0.9

var _rate: float
var _noise: PackedFloat32Array = PackedFloat32Array()
var _ni: int = 0
var _t_static: float = 0.0
var _t_bed: float = 0.0
var _t_squeal: float = 0.0
var _g_static: float = 0.0
var _g_bed: float = 0.0
var _g_squeal: float = 0.0
var _k_static: float
var _k_bed: float
var _k_squeal: float
var _p1: float = 0.0
var _p2: float = 0.0
var _lfo: float = 0.0
var _wob: float = 0.0
var _burst_left: int = 0
var _burst_env: float = 0.0
var _burst_decay: float = 1.0
var _out: PackedVector2Array = PackedVector2Array()


func _init(mix_rate: float) -> void:
	_rate = mix_rate
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7A11
	_noise.resize(65536)
	for i in _noise.size():
		_noise[i] = rng.randf() * 2.0 - 1.0
	_k_static = 1.0 - exp(-1.0 / (0.08 * _rate))
	_k_bed = 1.0 - exp(-1.0 / (0.05 * _rate))
	_k_squeal = 1.0 - exp(-1.0 / (0.02 * _rate))


static func ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_CAPTURE) == -1:
		AudioServer.add_bus()
		var i: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS_CAPTURE)
		AudioServer.add_bus_effect(i, AudioEffectCapture.new())
		# Attenuate after the capture tap instead of muting the bus: whether a
		# muted bus still feeds its effects is an engine detail we don't rely on.
		var amp := AudioEffectAmplify.new()
		amp.volume_db = -80.0
		AudioServer.add_bus_effect(i, amp)
	if AudioServer.get_bus_index(BUS_CLEAN) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_CLEAN)
	if AudioServer.get_bus_index(BUS_RADIO) == -1:
		AudioServer.add_bus()
		var r: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(r, BUS_RADIO)
		_build_radio_chain(r)


static func _build_radio_chain(bus: int) -> void:
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 300.0
	hp.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(bus, hp)
	for _i in 2: # two 24 dB/oct stages: steep roll-off above 3 kHz
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 3000.0
		lp.db = AudioEffectFilter.FILTER_24DB
		AudioServer.add_bus_effect(bus, lp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_ATAN
	dist.pre_gain = 4.0
	dist.drive = 0.3
	dist.post_gain = -3.0
	AudioServer.add_bus_effect(bus, dist)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -22.0
	comp.ratio = 6.0
	comp.attack_us = 300.0
	comp.release_ms = 150.0
	comp.gain = 6.0
	AudioServer.add_bus_effect(bus, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(bus, lim)


func set_state(static_on: bool, bed_on: bool, squeal_on: bool) -> void:
	_t_static = STATIC_LEVEL if static_on else 0.0
	_t_bed = BED_LEVEL if bed_on else 0.0
	_t_squeal = SQUEAL_LEVEL if squeal_on else 0.0


func trigger_burst(opening: bool) -> void:
	var dur: float = 0.08 if opening else 0.11
	var peak: float = 0.18 if opening else 0.12
	_burst_left = int(dur * _rate)
	_burst_env = peak
	_burst_decay = pow(0.001 / peak, 1.0 / maxf(1.0, float(_burst_left)))


func is_active() -> bool:
	return (_burst_left > 0 or _t_static > 0.0 or _t_bed > 0.0 or _t_squeal > 0.0
		or _g_static > 0.0005 or _g_bed > 0.0005 or _g_squeal > 0.0005)


## Renders `frames` stereo frames. The returned array is reused between calls.
func render(frames: int) -> PackedVector2Array:
	if _out.size() != frames:
		_out.resize(frames)
	var nsz: int = _noise.size()
	var w1: float = TAU * SQUEAL_F1 / _rate
	var w2: float = TAU * SQUEAL_F2 / _rate
	for i in frames:
		_g_static += (_t_static - _g_static) * _k_static
		_g_bed += (_t_bed - _g_bed) * _k_bed
		_g_squeal += (_t_squeal - _g_squeal) * _k_squeal
		var n: float = _noise[_ni]
		_ni += 1
		if _ni >= nsz:
			_ni = 0
		var s: float = n * (_g_static + _g_bed)
		if _g_squeal > 0.0005:
			if (i & 63) == 0:
				_lfo += TAU * SQUEAL_LFO_HZ * 64.0 / _rate
				if _lfo > TAU:
					_lfo -= TAU
				_wob = SQUEAL_WOBBLE_HZ * sin(_lfo) * TAU / _rate
			_p1 += w1 + _wob
			_p2 += w2 + _wob
			if _p1 > TAU:
				_p1 -= TAU
			if _p2 > TAU:
				_p2 -= TAU
			var raw: float = 0.5 * sin(_p1) + 0.5 * sin(_p2) + 0.25 * _noise[(_ni + 20011) % nsz]
			s += _g_squeal * raw / (1.0 + 0.6 * absf(raw)) # soft clip: harsh edge on the beat
		if _burst_left > 0:
			s += n * _burst_env
			_burst_env *= _burst_decay
			_burst_left -= 1
		_out[i] = Vector2(s, s)
	return _out
