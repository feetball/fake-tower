extends RefCounted
## Per-sender reorder/jitter buffer. Sequence numbers are 16-bit and wrap.
## pop() returns the next packet's payload and sets `last`:
##   PACKET  payload is valid
##   LOST    next packet never arrived but later ones did: conceal with silence
##   EMPTY   nothing to play (buffering, or the sender stopped)

enum Result { PACKET, LOST, EMPTY }

var target_packets: int = 3 # ~90 ms at 30 ms packets
var max_wait_ms: int = 120  # start playout anyway when a short burst never fills the target
var max_packets: int = 12
var last: int = Result.EMPTY
var dropped_late: int = 0
var concealed: int = 0

var _packets: Dictionary = {} # extended seq -> PackedByteArray
var _started: bool = false
var _next: int = 0
var _ref: int = 0
var _have_ref: bool = false
var _first_ms: int = 0


func is_started() -> bool:
	return _started


func buffered() -> int:
	return _packets.size()


func push(seq: int, payload: PackedByteArray, now_ms: int) -> bool:
	var ext: int = seq
	if _have_ref:
		var d: int = (seq - (_ref & 0xFFFF)) & 0xFFFF
		if d >= 0x8000:
			d -= 0x10000
		ext = _ref + d
	if _started and ext < _next:
		dropped_late += 1
		return false
	if _packets.has(ext):
		return false
	if _packets.is_empty() and not _started:
		_first_ms = now_ms
	_packets[ext] = payload
	if not _have_ref or ext > _ref:
		_ref = ext
		_have_ref = true
	while _packets.size() > max_packets:
		# Sender is ahead of playout: discard the oldest so latency stays bounded.
		var lo: int = _min_key()
		_packets.erase(lo)
		if _started and lo >= _next:
			_next = lo + 1
	return true


func pop(now_ms: int) -> PackedByteArray:
	last = Result.EMPTY
	if not _started:
		if _packets.is_empty():
			return PackedByteArray()
		if _packets.size() < target_packets and now_ms - _first_ms < max_wait_ms:
			return PackedByteArray()
		_started = true
		_next = _min_key()
	if _packets.is_empty():
		_reset()
		return PackedByteArray()
	if _packets.has(_next):
		var p: PackedByteArray = _packets[_next]
		_packets.erase(_next)
		_next += 1
		last = Result.PACKET
		return p
	var lo: int = _min_key()
	if lo - _next > max_packets:
		_next = lo # long gap (sender paused): don't synthesise seconds of silence
		return pop(now_ms)
	_next += 1
	concealed += 1
	last = Result.LOST
	return PackedByteArray()


func _min_key() -> int:
	var lo: int = 0x7FFFFFFFFFFF
	for k: int in _packets:
		if k < lo:
			lo = k
	return lo


func _reset() -> void:
	_packets.clear()
	_started = false
	_have_ref = false
