extends RefCounted
## Seedable uniform [0, 1) generator: mulberry32, bit-identical to src/shared/sim/rng.ts.
## All arithmetic is kept as unsigned 32-bit values inside 64-bit ints.

const Self := preload("res://core/sim/rng.gd")
const M32 := 0xFFFFFFFF

var _a := 0


func _init(seed_value: int = 0) -> void:
	_a = seed_value & M32


## A generator seeded from the clock and the engine RNG, for real rounds.
static func from_entropy() -> Self:
	var s := (Time.get_ticks_usec() ^ (randi() << 8)) & M32
	return new(s)


## Math.imul for operands already reduced to 32 bits; result reduced mod 2^32.
static func _imul(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & M32


func next_float() -> float:
	_a = (_a + 0x6D2B79F5) & M32
	var t := _a
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & M32)) & M32
	return float(t ^ (t >> 14)) / 4294967296.0


func rand_range(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float()


func rand_int(lo: int, hi_incl: int) -> int:
	return lo + int(floor(next_float() * float(hi_incl - lo + 1)))


func pick(items: Array) -> Variant:
	if items.is_empty():
		push_error("pick from empty list")
		return null
	return items[int(floor(next_float() * float(items.size())))]


func shuffle(items: Array) -> Array:
	var a := items.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := int(floor(next_float() * float(i + 1)))
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
