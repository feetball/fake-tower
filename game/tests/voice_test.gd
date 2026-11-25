extends SceneTree
## Headless voice logic tests:
## godot --headless --path game -s res://tests/voice_test.gd

const MuLaw := preload("res://voice/mulaw.gd")
const Resampler := preload("res://voice/resampler.gd")
const Logic := preload("res://voice/voice_logic.gd")
const JitterBuffer := preload("res://voice/jitter_buffer.gd")
const RadioFx := preload("res://voice/radio_fx.gd")

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	test_mulaw()
	test_tone_roundtrip(48000.0)
	test_tone_roundtrip(44100.0)
	test_streaming_chunks_match()
	test_audibility()
	test_should_forward()
	test_packets()
	test_token_bucket()
	test_jitter_order_and_late()
	test_jitter_loss_and_wrap()
	test_jitter_idle_and_short_burst()
	test_radio_fx()
	print("SUMMARY: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("PASS  ", name)
	else:
		_fail += 1
		print("FAIL  ", name, "  ", detail)


func tone(freq: float, rate: float, seconds: float, amp: float) -> PackedFloat32Array:
	var n: int = int(rate * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = amp * sin(TAU * freq * i / rate)
	return out


## Amplitude of the sinusoid at `freq` (Goertzel), over buf[from, to).
func amp_at(buf: PackedFloat32Array, rate: float, freq: float, from: int, to: int) -> float:
	var w: float = TAU * freq / rate
	var coeff: float = 2.0 * cos(w)
	var s1: float = 0.0
	var s2: float = 0.0
	for i in range(from, to):
		var s: float = buf[i] + coeff * s1 - s2
		s2 = s1
		s1 = s
	var power: float = s1 * s1 + s2 * s2 - coeff * s1 * s2
	return 2.0 * sqrt(maxf(power, 0.0)) / float(to - from)


func rms(buf: PackedFloat32Array, from: int, to: int) -> float:
	var e: float = 0.0
	for i in range(from, to):
		e += buf[i] * buf[i]
	return sqrt(e / float(to - from))


func roundtrip(src: PackedFloat32Array, rate: float) -> PackedFloat32Array:
	var down: RefCounted = Resampler.new(rate, 8000.0)
	var up: RefCounted = Resampler.new(8000.0, rate, 3700.0, 5)
	var low: PackedFloat32Array = down.process(src)
	var dec: PackedFloat32Array = MuLaw.decode(MuLaw.encode(low))
	return up.process(dec)


func test_mulaw() -> void:
	check("mulaw zero encodes to 0xFF", MuLaw.encode_sample(0.0) == 0xFF)
	check("mulaw full-scale positive is 0x80", MuLaw.encode_sample(1.0) == 0x80)
	check("mulaw full-scale negative is 0x00", MuLaw.encode_sample(-1.0) == 0x00)
	var worst: float = 0.0
	for i in range(-1000, 1001):
		var x: float = i / 1000.0
		var y: float = MuLaw.decode(PackedByteArray([MuLaw.encode_sample(x)]))[0]
		var tol: float = maxf(0.004, absf(x) * 0.04)
		worst = maxf(worst, absf(y - x) / tol)
	check("mulaw round-trip error within companding bounds", worst <= 1.0, "ratio %.2f" % worst)
	var mono_ok: bool = true
	var prev: float = 0.0
	for b in range(0xFF, 0x7F, -1): # 0xFF..0x80: positive, magnitude growing as byte falls
		var v: float = MuLaw.decode(PackedByteArray([b]))[0]
		if v < 0.0 or v < prev:
			mono_ok = false
		prev = v
	check("mulaw decode table monotonic (positive half)", mono_ok)


func test_tone_roundtrip(rate: float) -> void:
	var tag: String = "%d Hz" % int(rate)
	var out: PackedFloat32Array = roundtrip(tone(1000.0, rate, 1.0, 0.5), rate)
	var a: int = int(out.size() * 0.2)
	var b: int = int(out.size() * 0.8)
	var best_f: float = 0.0
	var best_a: float = 0.0
	var f: float = 100.0
	while f <= 4000.0:
		var m: float = amp_at(out, rate, f, a, b)
		if m > best_a:
			best_a = m
			best_f = f
		f += 100.0
	check("1 kHz tone dominant frequency (%s)" % tag, absf(best_f - 1000.0) < 1.0, "got %.0f" % best_f)
	var level: float = amp_at(out, rate, 1000.0, a, b)
	check("1 kHz tone level within 1.5 dB (%s)" % tag, level > 0.42 and level < 0.59, "amp %.3f" % level)
	var out6: PackedFloat32Array = roundtrip(tone(6000.0, rate, 1.0, 0.5), rate)
	var r6: float = rms(out6, a, b)
	var in_rms: float = 0.5 / sqrt(2.0)
	check("6 kHz tone attenuated > 30 dB (%s)" % tag, r6 < in_rms / 31.6, "rms %.4f vs input %.3f" % [r6, in_rms])


func test_streaming_chunks_match() -> void:
	var src: PackedFloat32Array = tone(700.0, 48000.0, 0.5, 0.4)
	var whole: PackedFloat32Array = Resampler.new(48000.0, 8000.0).process(src)
	var rs: RefCounted = Resampler.new(48000.0, 8000.0)
	var parts := PackedFloat32Array()
	var i: int = 0
	var sizes: Array[int] = [333, 1024, 77, 800]
	var k: int = 0
	while i < src.size():
		var n: int = mini(sizes[k % 4], src.size() - i)
		parts.append_array(rs.process(src.slice(i, i + n)))
		i += n
		k += 1
	var m: int = mini(whole.size(), parts.size())
	var maxd: float = 0.0
	for j in m:
		maxd = maxf(maxd, absf(whole[j] - parts[j]))
	check("resampler is chunk-size independent", m > 3000 and maxd < 1e-4, "maxd %.6f m %d" % [maxd, m])
	check("resampler output count ~ input/6", absi(whole.size() - src.size() / 6) <= 10, str(whole.size()))


func test_audibility() -> void:
	var a: Dictionary = Logic.compute_audibility("open", 1, [], [2, 3])
	check("open: all peers audible, not radio", a.gains[2] == 1.0 and a.gains[3] == 1.0 and not a.radio and not a.squeal)
	a = Logic.compute_audibility("radio", 1, [2], [2, 3])
	check("radio: sole other keyer audible, bed on", a.gains[2] == 1.0 and a.gains[3] == 0.0 and a.bed and a.squelch_open and not a.squeal)
	a = Logic.compute_audibility("radio", 1, [1], [2, 3])
	check("radio: self keying is silent, no bed", a.gains[2] == 0.0 and a.gains[3] == 0.0 and not a.bed and a.squelch_open)
	a = Logic.compute_audibility("radio", 1, [2, 3], [2, 3])
	check("radio: two keyers -> squeal, voices muted", a.squeal and a.gains[2] == 0.0 and a.gains[3] == 0.0 and not a.bed)
	a = Logic.compute_audibility("radio", 1, [], [2])
	check("radio: nobody keying -> static, squelch closed", a.static_noise and not a.squelch_open and a.gains[2] == 0.0)
	a = Logic.compute_audibility("radio", 1, [2, 2], [2])
	check("radio: duplicate ids count once", not a.squeal and a.gains[2] == 1.0)
	a = Logic.compute_audibility("radio", 1, [1, 2], [2])
	check("radio: self + other keying is blocked", a.squeal and a.gains[2] == 0.0)
	check("mic_enabled open always", Logic.mic_enabled("open", false))
	check("mic_enabled radio follows ptt", Logic.mic_enabled("radio", true) and not Logic.mic_enabled("radio", false))


func test_should_forward() -> void:
	check("forward: playing, sole sender", Logic.should_forward("playing", [4], 4))
	check("forward: playing, other sole keyer -> drop", not Logic.should_forward("playing", [3], 4))
	check("forward: playing, nobody keyed -> drop", not Logic.should_forward("playing", [], 4))
	check("forward: playing, two keyers -> drop", not Logic.should_forward("playing", [3, 4], 4))
	check("forward: lobby open", Logic.should_forward("lobby", [], 4))
	check("forward: ended open", Logic.should_forward("ended", [3, 4], 4))
	check("forward: menu dropped", not Logic.should_forward("menu", [], 4))


func test_packets() -> void:
	var payload := PackedByteArray()
	payload.resize(240)
	payload.fill(0x55)
	var p: PackedByteArray = Logic.build_packet(0xABCD, payload)
	check("packet seq/payload round-trip", Logic.packet_seq(p) == 0xABCD and Logic.packet_payload(p) == payload and Logic.valid_packet(p))
	check("packet too small rejected", not Logic.valid_packet(PackedByteArray([1, 2, 3])))
	var big := PackedByteArray()
	big.resize(5000)
	check("packet too large rejected", not Logic.valid_packet(big))


func test_token_bucket() -> void:
	var tb: Logic.TokenBucket = Logic.TokenBucket.new(10000.0, 2000.0)
	var ok: int = 0
	for i in 40: # 40 x 240 B within 0.4 s ~ 24 kB/s: well over budget
		if tb.try_take(i * 0.01, 240.0):
			ok += 1
	check("token bucket throttles a flood", ok <= 27 and ok >= 20, "ok=%d" % ok)
	var tb2: Logic.TokenBucket = Logic.TokenBucket.new(10000.0, 4000.0)
	var all_ok: bool = true
	for i in 100: # nominal 30 ms packets
		all_ok = all_ok and tb2.try_take(i * 0.03, 240.0)
	check("token bucket passes nominal stream", all_ok)


func pl(tag: int) -> PackedByteArray:
	return PackedByteArray([tag])


func test_jitter_order_and_late() -> void:
	var jb: RefCounted = JitterBuffer.new()
	jb.push(10, pl(10), 0)
	jb.push(12, pl(12), 5)
	check("jitter waits for target before playing", jb.pop(10).is_empty() and jb.last == JitterBuffer.Result.EMPTY)
	jb.push(11, pl(11), 10)
	var order: Array[int] = []
	for i in 3:
		var d: PackedByteArray = jb.pop(20)
		if jb.last == JitterBuffer.Result.PACKET:
			order.append(d[0])
	check("jitter reorders", order == [10, 11, 12], str(order))
	check("jitter late packet dropped", not jb.push(11, pl(11), 30) and jb.dropped_late == 1)


func test_jitter_loss_and_wrap() -> void:
	var jb: RefCounted = JitterBuffer.new()
	for s in [65534, 65535, 1, 2]: # 0 is lost; sequence wraps
		jb.push(s, pl(s & 0xFF), 0)
	var seq: Array[int] = []
	for i in 4:
		var d: PackedByteArray = jb.pop(10)
		match jb.last:
			JitterBuffer.Result.PACKET:
				seq.append(d[0])
			JitterBuffer.Result.LOST:
				seq.append(-1)
	check("jitter wrap + loss concealment", seq == [254, 255, -1, 1], str(seq))
	check("jitter concealed counter", jb.concealed == 1)
	var jb2: RefCounted = JitterBuffer.new()
	jb2.max_packets = 6
	for s in 20:
		jb2.push(s, pl(s), 0)
	check("jitter bounded", jb2.buffered() <= 6)
	var first: PackedByteArray = jb2.pop(1)
	check("jitter overflow drops oldest", jb2.last == JitterBuffer.Result.PACKET and first[0] >= 14, str(first))


func test_jitter_idle_and_short_burst() -> void:
	var jb: RefCounted = JitterBuffer.new()
	jb.push(5, pl(5), 0)
	check("short burst waits", jb.pop(50).is_empty() and jb.last == JitterBuffer.Result.EMPTY)
	var d: PackedByteArray = jb.pop(130)
	check("short burst plays after max_wait", jb.last == JitterBuffer.Result.PACKET and d[0] == 5)
	jb.pop(140)
	check("buffer idles after sender stops", not jb.is_started() and jb.last == JitterBuffer.Result.EMPTY)
	jb.push(900, pl(1), 1000) # sender restarted with an unrelated sequence
	jb.push(901, pl(2), 1010)
	jb.push(902, pl(3), 1020)
	var d2: PackedByteArray = jb.pop(1030)
	check("new transmission restarts cleanly", jb.last == JitterBuffer.Result.PACKET and d2[0] == 1)
	var jb3: RefCounted = JitterBuffer.new()
	for s in [0, 1, 2, 3, 300, 301, 302, 303]:
		jb3.push(s, pl(s & 0xFF), 0)
	var n_lost: int = 0
	for i in 12:
		jb3.pop(10)
		if jb3.last == JitterBuffer.Result.LOST:
			n_lost += 1
	check("long gap is skipped, not concealed for seconds", n_lost == 0, "lost %d" % n_lost)


func test_radio_fx() -> void:
	var fx: RefCounted = RadioFx.new(48000.0)
	check("fx idle by default", not fx.is_active())
	fx.set_state(false, false, true)
	var buf: PackedVector2Array = fx.render(4800)
	var peak: float = 0.0
	var finite: bool = true
	for i in buf.size():
		var v: float = buf[i].x
		peak = maxf(peak, absf(v))
		finite = finite and is_finite(v)
	check("fx squeal audible, bounded and finite", finite and peak > 0.01 and peak < 0.5, "peak %.3f" % peak)
	fx.set_state(false, false, false)
	for i in 20:
		fx.render(4800)
	check("fx goes inactive after fade-out", not fx.is_active())
	fx.trigger_burst(true)
	check("fx burst activates", fx.is_active())
	fx.render(10000)
	check("fx burst finishes", not fx.is_active())
