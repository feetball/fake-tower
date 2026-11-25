extends RefCounted
## G.711 mu-law codec (8-bit, ~14-bit dynamic range). Floats are -1..1.

const BIAS := 0x84
const CLIP := 32635

static var _dec: PackedFloat32Array = PackedFloat32Array()
static var _exp: PackedByteArray = PackedByteArray()


static func _ensure_tables() -> void:
	if _dec.size() == 256:
		return
	_dec.resize(256)
	for i in 256:
		var u: int = ~i & 0xFF
		var e: int = (u >> 4) & 7
		var m: int = u & 0xF
		var mag: int = (((m << 3) + BIAS) << e) - BIAS
		_dec[i] = (-mag if (u & 0x80) != 0 else mag) / 32768.0
	_exp.resize(256)
	for i in 256:
		var e2: int = 0 # floor(log2(i)), 0 for i < 2, capped at 7
		var v: int = i >> 1
		while v > 0 and e2 < 7:
			e2 += 1
			v >>= 1
		_exp[i] = e2


static func encode_sample(x: float) -> int:
	if _exp.is_empty():
		_ensure_tables()
	var pcm: int = int(clampf(x, -1.0, 1.0) * 32767.0)
	var sign: int = 0
	if pcm < 0:
		pcm = -pcm
		sign = 0x80
	var mag: int = mini(pcm, CLIP) + BIAS
	var e: int = _exp[(mag >> 7) & 0xFF]
	var m: int = (mag >> (e + 3)) & 0xF
	return ~(sign | (e << 4) | m) & 0xFF


static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	_ensure_tables()
	var n: int = samples.size()
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		out[i] = encode_sample(samples[i])
	return out


static func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	_ensure_tables()
	var n: int = bytes.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = _dec[bytes[i]]
	return out
