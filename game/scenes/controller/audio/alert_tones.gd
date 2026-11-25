extends AudioStreamPlayer
## Procedural aural alerts (no asset files): conflict alert = fast two-tone
## warble, MSAW = falling beeps. Samples are generated only while a pattern
## plays, so the idle cost is zero.

const RATE := 22050.0
const CA_LEN := 2.2
const LA_LEN := 1.9

var _playback: AudioStreamGeneratorPlayback
var _kind := ""
var _t := 0.0
var _phase := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.2
	stream = gen
	volume_db = -10.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## Starts the pattern for "CA" or "LA"; a conflict alert is never cut short by MSAW.
func alert(kind: String) -> void:
	if _kind == "CA" and kind == "LA":
		return
	_kind = kind
	_t = 0.0


func _process(_delta: float) -> void:
	if _kind == "" or _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var length := CA_LEN if _kind == "CA" else LA_LEN
	for i in n:
		var s := 0.0
		if _t < length:
			s = _ca(_t) if _kind == "CA" else _la(_t)
		buf[i] = Vector2(s, s)
		_t += 1.0 / RATE
	_playback.push_buffer(buf)
	if _t >= length:
		_kind = ""


## Warble: 1050/1500 Hz alternating every 0.13 s, two bursts.
func _ca(t: float) -> float:
	var burst := fmod(t, 1.1)
	if burst > 0.9:
		return 0.0
	var f := 1050.0 if int(burst / 0.13) % 2 == 0 else 1500.0
	return _tone(f) * _env(fmod(burst, 0.13), 0.13) * 0.5


## Four falling beeps, repeated.
func _la(t: float) -> float:
	var cycle := fmod(t, 0.95)
	var beep := int(cycle / 0.22)
	var bt := fmod(cycle, 0.22)
	if beep > 3 or bt > 0.15:
		return 0.0
	var f := 880.0 - beep * 60.0 - bt * 400.0
	return _tone(f) * _env(bt, 0.15) * 0.5


func _tone(f: float) -> float:
	_phase = fmod(_phase + f / RATE, 1.0)
	var x := TAU * _phase
	return sin(x) + 0.25 * sin(3.0 * x) + 0.1 * sin(5.0 * x)


## 4 ms attack/release so segments do not click.
func _env(t: float, length: float) -> float:
	return clampf(minf(t, length - t) / 0.004, 0.0, 1.0)


func _exit_tree() -> void:
	stop()
	_playback = null
