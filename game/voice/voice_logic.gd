extends RefCounted
## Pure decision logic (no engine state): audibility, relay rules, packet format.

const HEADER_BYTES: int = 2
const MIN_PAYLOAD: int = 16
const MAX_PAYLOAD: int = 400


## Port of computeAudibility (src/client/voice/logic.ts). mode: "open" | "radio".
static func compute_audibility(mode: String, self_id: int, tx_ids: Array, peer_ids: Array) -> Dictionary:
	var gains: Dictionary = {}
	var out: Dictionary = {
		"gains": gains, "radio": mode == "radio", "squeal": false,
		"static_noise": false, "bed": false, "squelch_open": false,
	}
	if mode != "radio":
		for id: int in peer_ids:
			gains[id] = 1.0
		return out
	var tx: Array[int] = []
	for v: int in tx_ids:
		if not tx.has(v):
			tx.append(v)
	for id: int in peer_ids:
		gains[id] = 0.0
	out["squelch_open"] = tx.size() > 0
	if tx.is_empty():
		out["static_noise"] = true
	elif tx.size() >= 2:
		out["squeal"] = true
	else:
		var only: int = tx[0]
		if only != self_id: # self keying: silence, no sidetone, no bed
			if gains.has(only):
				gains[only] = 1.0
			out["bed"] = true
	return out


## Host relay rule. Playing: only the sole keyer's audio goes out. Lobby/ended: open mic.
static func should_forward(phase: String, radio_tx: Array, sender: int) -> bool:
	match phase:
		"playing":
			if radio_tx.is_empty():
				return false
			for v: int in radio_tx:
				if v != sender:
					return false
			return true
		"lobby", "ended":
			return true
	return false


static func mic_enabled(mode: String, ptt: bool) -> bool:
	return mode != "radio" or ptt


static func build_packet(seq: int, payload: PackedByteArray) -> PackedByteArray:
	var p := PackedByteArray([seq & 0xFF, (seq >> 8) & 0xFF])
	p.append_array(payload)
	return p


static func valid_packet(p: PackedByteArray) -> bool:
	var n: int = p.size() - HEADER_BYTES
	return n >= MIN_PAYLOAD and n <= MAX_PAYLOAD


static func packet_seq(p: PackedByteArray) -> int:
	return p[0] | (p[1] << 8)


static func packet_payload(p: PackedByteArray) -> PackedByteArray:
	return p.slice(HEADER_BYTES)


## Byte budget limiter for untrusted senders: sustained `rate` bytes/s, `burst` bytes of slack.
class TokenBucket extends RefCounted:
	var rate: float
	var burst: float
	var _tokens: float
	var _t: float = -1.0

	func _init(rate_bytes_s: float, burst_bytes: float) -> void:
		rate = rate_bytes_s
		burst = burst_bytes
		_tokens = burst_bytes

	func try_take(now_s: float, cost: float) -> bool:
		if _t >= 0.0:
			_tokens = minf(burst, _tokens + (now_s - _t) * rate)
		_t = now_s
		if _tokens < cost:
			return false
		_tokens -= cost
		return true
