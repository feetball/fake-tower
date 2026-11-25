extends RefCounted
## Streaming windowed-sinc polyphase resampler (mono). The low-pass cutoff is
## applied for both directions, so decimation is alias-free and interpolation
## has no imaging. Feed arbitrary-sized chunks to process().

var _step: float
var _half: int
var _taps: int
var _phases: int
var _table: PackedFloat32Array = PackedFloat32Array()
var _buf: PackedFloat32Array = PackedFloat32Array()
var _pos: float


func _init(in_rate: float, out_rate: float, cutoff_hz: float = 3300.0, lobes: int = 6, phases: int = 128) -> void:
	_step = in_rate / out_rate
	_phases = phases
	var c: float = 2.0 * cutoff_hz / in_rate # cutoff relative to input Nyquist
	_half = ceili(lobes / c)
	_taps = _half * 2
	_table.resize(_phases * _taps)
	for p in _phases:
		var frac: float = float(p) / _phases
		var sum: float = 0.0
		for j in _taps:
			var x: float = float(j - _half + 1) - frac
			var h: float = c if absf(x) < 1e-9 else sin(PI * c * x) / (PI * x)
			var t: float = x / _half
			var w: float = 0.42 + 0.5 * cos(PI * t) + 0.08 * cos(2.0 * PI * t)
			h *= w
			_table[p * _taps + j] = h
			sum += h
		for j in _taps:
			_table[p * _taps + j] /= sum
	reset()


func reset() -> void:
	_buf.resize(_half)
	_buf.fill(0.0)
	_pos = float(_half)


func process(input: PackedFloat32Array) -> PackedFloat32Array:
	_buf.append_array(input)
	var n: int = _buf.size()
	var out := PackedFloat32Array()
	out.resize(maxi(int((n - _pos) / _step) + 2, 0))
	var count: int = 0
	var taps: int = _taps
	while true:
		var i0: int = int(_pos)
		var ph: int = int((_pos - i0) * _phases + 0.5)
		if ph >= _phases:
			ph = 0
			i0 += 1
		if i0 + _half >= n:
			break
		var base: int = i0 - _half + 1
		var tb: int = ph * taps
		var acc: float = 0.0
		for j in taps:
			acc += _buf[base + j] * _table[tb + j]
		out[count] = acc
		count += 1
		_pos += _step
	out.resize(count)
	var drop: int = int(_pos) - _half + 1
	if drop > 0:
		_buf = _buf.slice(drop)
		_pos -= drop
	return out
