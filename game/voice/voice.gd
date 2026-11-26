extends Node
## Voice autoload: mic capture -> 8 kHz mu-law packets -> host relay -> per-sender
## jitter buffer -> clean bus (lobby/ended) or radio chain (playing).
## Talks to Session only through dynamic access, so it degrades if Session is absent.
## Capture is optional everywhere: with no input device, input disabled, a denied
## permission (Android/iOS prompt, browser prompt), a non-https web page or no signal,
## mic_ok stays false, mic_state/mic_status say why, and the player can still listen.
## On a dedicated server (Session.is_dedicated) it only relays: no capture, no playback.

signal status_changed()

const MuLaw := preload("res://voice/mulaw.gd")
const Resampler := preload("res://voice/resampler.gd")
const Logic := preload("res://voice/voice_logic.gd")
const JitterBuffer := preload("res://voice/jitter_buffer.gd")
const RadioFx := preload("res://voice/radio_fx.gd")

const VOICE_RATE: float = 8000.0
const PACKET_SAMPLES: int = 240 # 30 ms
const RX_QUEUE_S: float = 0.045 # keep this much audio queued in each generator
const GEN_BUFFER_S: float = 0.25
const GATE_OPEN_RMS: float = 0.012
const GATE_HOLD_PACKETS: int = 10
const NO_FRAMES_TIMEOUT_S: float = 1.5
const MUTED_DB: float = -80.0
const RPC_CHANNEL: int = 2
const RX_IDLE_FREE_MS: int = 10000
const PERM_ANDROID: String = "android.permission.RECORD_AUDIO"
const PERM_IOS: String = "appleembedded.permission.AUDIO_RECORD"
const MIC_TEXT: Dictionary = {
	"ok": "Microphone OK.",
	"idle": "Microphone not in use.",
	"starting": "Starting the microphone…",
	"asking": "Waiting for microphone permission…",
	"denied": "Microphone permission denied: listening only. Allow it in the system settings, then rejoin.",
	"no_signal": "No microphone signal: listening only.",
	"no_signal_web": "No microphone input: listening only. Allow microphone access for this page (address bar), then rejoin.",
	"insecure": "Browsers only allow the microphone on https:// pages: listening only.",
	"no_device": "No microphone found: listening only.",
	"disabled": "Microphone input is disabled in this build: listening only.",
	"server": "Dedicated server: no microphone.",
}

var mic_ok: bool = false
## Why the mic is (not) working: a MIC_TEXT key. mic_status is the text for the UI.
var mic_state: String = "idle"
var mic_status: String = MIC_TEXT["idle"]
## Voice packets received per sender id (diagnostics and tests/ws_net_test.sh).
var rx_counts: Dictionary = {}
var input_level: float = 0.0
## True while mic audio is actually being sent (open mode, or keyed in radio mode).
var transmitting: bool = false
## "open" (lobby/ended) or "radio" (playing).
var mode: String = "open"
## Radio mode only: frequency blocked / squelch closed, for HUD indicators.
var blocked: bool = false

var _session: Node
var _mix_rate: float = 48000.0
var _volume: float = 1.0
var _phase: String = ""
var _my_id: int = 1
var _tx: Array = []
var _sig: String = ""
var _poll_t: float = 0.0

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _capturing: bool = false
var _mic_possible: bool = false
var _mic_running: bool = false
var _mic_unavailable: String = "" # MIC_TEXT key when capture can never work here
var _perm: String = "" # "", "asking", "granted", "denied"
var _ever_frames: bool = false
var _dedicated: bool = false
var _no_frames_t: float = 0.0
var _down: RefCounted
var _mono: PackedFloat32Array = PackedFloat32Array()
var _pcm: PackedFloat32Array = PackedFloat32Array()
var _hp_x: float = 0.0
var _hp_y: float = 0.0
var _seq: int = 0
var _gate_hold: int = 0

var _rx: Dictionary = {} # id -> Rx
var _limiters: Dictionary = {} # host side: id -> TokenBucket
var _fx: RefCounted
var _fx_player: AudioStreamPlayer
var _fx_pb: AudioStreamGeneratorPlayback
var _fx_cap: int = 0
var _prev_squelch: bool = false
var _prev_mode: String = "open"


class Rx extends RefCounted:
	var jb: RefCounted
	var player: AudioStreamPlayer
	var pb: AudioStreamGeneratorPlayback
	var up: RefCounted
	var cap: int = 0
	var gain: float = 1.0
	var last_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mix_rate = AudioServer.get_mix_rate()
	if _mix_rate <= 0.0:
		_mix_rate = 48000.0
	RadioFx.ensure_buses()
	_fx = RadioFx.new(_mix_rate)
	_setup_fx_player()
	_setup_capture()
	_down = Resampler.new(_mix_rate, VOICE_RATE)
	_find_session()
	set_volume(_volume)


func set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	var db: float = MUTED_DB if _volume <= 0.001 else linear_to_db(_volume)
	for bus in [RadioFx.BUS_CLEAN, RadioFx.BUS_RADIO]:
		var i: int = AudioServer.get_bus_index(bus)
		if i != -1:
			AudioServer.set_bus_volume_db(i, db)


# ---------------------------------------------------------------- setup

func _setup_fx_player() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _mix_rate
	gen.buffer_length = GEN_BUFFER_S
	_fx_player = AudioStreamPlayer.new()
	_fx_player.stream = gen
	_fx_player.bus = RadioFx.BUS_RADIO
	_stream_playback(_fx_player)
	add_child(_fx_player)
	_fx_player.play()
	_fx_pb = _fx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_fx_cap = int(GEN_BUFFER_S * _mix_rate)


func _setup_capture() -> void:
	var enabled: bool = bool(ProjectSettings.get_setting("audio/driver/enable_input", false))
	if not enabled:
		_mic_unavailable = "disabled"
		return
	if OS.has_feature("web") and not _web_mic_api():
		# getUserMedia exists only in secure contexts (https or localhost).
		_mic_unavailable = "insecure"
		return
	if AudioServer.get_input_device_list().is_empty():
		_mic_unavailable = "no_device"
		return
	var bus: int = AudioServer.get_bus_index(RadioFx.BUS_CAPTURE)
	if bus == -1:
		_mic_unavailable = "no_device"
		return
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	if _capture == null:
		_mic_unavailable = "no_device"
		return
	_capture.buffer_length = 0.25
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = RadioFx.BUS_CAPTURE
	_stream_playback(_mic_player)
	add_child(_mic_player)
	_mic_possible = true


## Web exports default to "sample" playback, which bypasses the bus effects (capture,
## radio DSP) and cannot play generators: force the mixer path.
static func _stream_playback(p: AudioStreamPlayer) -> void:
	p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM


static func _web_mic_api() -> bool:
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	var v: Variant = Engine.get_singleton("JavaScriptBridge").call("eval",
		"!!(window.isSecureContext && navigator.mediaDevices && navigator.mediaDevices.getUserMedia)", true)
	return v is bool and v


# ---------------------------------------------------------------- permission (Android, iOS 17+)

## The OS permission to ask for before capturing, or "" when none is needed (desktop,
## web: the browser asks by itself; iOS < 17: the system asks on first capture).
static func _permission_name() -> String:
	match OS.get_name():
		"Android":
			return PERM_ANDROID
		"iOS":
			return PERM_IOS if OS.get_version().get_slice(".", 0).to_int() >= 17 else ""
	return ""


## True when capture may start now; otherwise asks (once) and waits for the answer.
func _permission_ready() -> bool:
	if _perm == "granted":
		return true
	if _perm == "asking" or _perm == "denied":
		return false
	var perm := _permission_name()
	if perm == "" or OS.get_granted_permissions().has(perm):
		_perm = "granted"
		return true
	var tree := get_tree()
	if tree != null and not tree.on_request_permissions_result.is_connected(_on_permission_result):
		tree.on_request_permissions_result.connect(_on_permission_result)
	_perm = "asking"
	if OS.request_permission(perm):
		_perm = "granted"
		return true
	return false


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission != _permission_name() or _perm != "asking":
		return
	_perm = "granted" if granted else "denied"
	_update_mic()


func _find_session() -> void:
	_session = get_node_or_null("/root/Session")
	if _session == null:
		return
	if _session.has_signal("radio_changed"):
		_session.connect("radio_changed", _on_radio_changed)
	if _session.has_signal("phase_changed"):
		_session.connect("phase_changed", _on_phase_changed)
	if _session.has_signal("lobby_changed"):
		_session.connect("lobby_changed", _refresh)
	_refresh()


func _on_radio_changed(_tx_ids: Array) -> void:
	_refresh()


func _on_phase_changed(_p: String) -> void:
	_refresh()


# ---------------------------------------------------------------- session state

func _read_session() -> void:
	_phase = ""
	_tx = []
	if _session == null:
		return
	var ph: Variant = _session.get("phase")
	if ph is String:
		_phase = ph
	var me: Variant = _session.get("my_id")
	if me is int:
		_my_id = me
	var tx: Variant = _session.get("radio_tx")
	if tx is Array:
		_tx = tx


func _refresh() -> void:
	_read_session()
	var ded: Variant = _session.get("is_dedicated") if _session != null else false
	var was_dedicated := _dedicated
	_dedicated = ded is bool and ded
	var old_mode: String = mode
	var old_tx: bool = transmitting
	var old_blocked: bool = blocked
	mode = "radio" if _phase == "playing" else "open"
	var keyed: bool = _tx.has(_my_id)
	var active_phase: bool = _phase == "lobby" or _phase == "playing" or _phase == "ended"
	transmitting = active_phase and Logic.mic_enabled(mode, keyed)
	_set_capturing(active_phase)
	if was_dedicated != _dedicated:
		_update_mic()

	var aud: Dictionary = Logic.compute_audibility(mode, _my_id, _tx, _rx.keys())
	var gains: Dictionary = aud["gains"]
	var bus: String = RadioFx.BUS_RADIO if aud["radio"] else RadioFx.BUS_CLEAN
	for id: int in _rx:
		var r: Rx = _rx[id]
		r.gain = float(gains.get(id, 0.0))
		r.player.bus = bus
		r.player.volume_db = linear_to_db(r.gain) if r.gain > 0.0 else MUTED_DB
	if aud["radio"] and _active_phase_playing():
		_fx.set_state(aud["static_noise"], aud["bed"], aud["squeal"])
		var open_now: bool = aud["squelch_open"]
		if _prev_mode == "radio" and open_now != _prev_squelch:
			_fx.trigger_burst(open_now)
		_prev_squelch = open_now
	else:
		_fx.set_state(false, false, false)
		_prev_squelch = false
	blocked = aud["squeal"]
	_prev_mode = mode
	if old_mode != mode or old_tx != transmitting or old_blocked != blocked:
		status_changed.emit()


func _active_phase_playing() -> bool:
	return _phase == "playing"


func _set_capturing(on: bool) -> void:
	if on == _capturing:
		return
	_capturing = on
	_update_mic()


## Start or stop the mic player to match _capturing, the permission and the platform,
## and keep mic_state current. Never throws: anything missing means listen-only.
func _update_mic() -> void:
	var want := _capturing and not _dedicated
	if _dedicated:
		_set_mic_state("server")
	elif not want:
		_set_mic_state("idle")
	elif _mic_unavailable != "":
		_set_mic_state(_mic_unavailable)
	elif not _permission_ready():
		_set_mic_state("asking" if _perm == "asking" else "denied")
		want = false
	elif not _mic_running:
		_set_mic_state("starting")
	if not _mic_possible:
		want = false
	if want == _mic_running:
		return
	_mic_running = want
	if want:
		_no_frames_t = 0.0
		_ever_frames = false
		_mic_player.play()
	else:
		_mic_player.stop()
		_capture.clear_buffer()
		_set_mic_ok(false)
		input_level = 0.0


func _set_mic_ok(v: bool) -> void:
	if v:
		_set_mic_state("ok")
	if v != mic_ok:
		mic_ok = v
		status_changed.emit()


func _set_mic_state(st: String) -> void:
	if st == mic_state:
		return
	mic_state = st
	mic_status = MIC_TEXT.get(st, st)
	status_changed.emit()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if _session == null:
		_poll_t += delta
		if _poll_t > 0.5:
			_poll_t = 0.0
			_find_session()
	else:
		# Cheap fallback in case a Session signal is missed.
		_poll_t += delta
		if _poll_t > 0.25:
			_poll_t = 0.0
			var ph: Variant = _session.get("phase")
			var tx: Variant = _session.get("radio_tx")
			var sig: String = "%s|%s" % [ph, tx]
			if sig != _sig:
				_sig = sig
				_refresh()
	_pump_capture(delta)
	_pump_rx()
	_pump_fx()


func _pump_capture(delta: float) -> void:
	if not _mic_running or _capture == null:
		input_level = maxf(0.0, input_level - delta * 2.0)
		return
	var avail: int = _capture.get_frames_available()
	if avail <= 0:
		_no_frames_t += delta
		if _no_frames_t > NO_FRAMES_TIMEOUT_S:
			_set_mic_ok(false)
			# Never any frames: no device, denied (the browser gives no callback) or a
			# suspended audio context. Frames arriving later still flip back to "ok".
			if not _ever_frames:
				_set_mic_state("no_signal_web" if OS.has_feature("web") else "no_signal")
		input_level = maxf(0.0, input_level - delta * 2.0)
		return
	_no_frames_t = 0.0
	_ever_frames = true
	_set_mic_ok(true)
	var frames: PackedVector2Array = _capture.get_buffer(avail)
	var peak: float = 0.0
	var i: int = 0
	while i < avail:
		var f: Vector2 = frames[i]
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		i += 8
	var target: float = clampf(peak * 2.5, 0.0, 1.0)
	var k: float = 1.0 - exp(-delta * (40.0 if target > input_level else 6.0))
	input_level += (target - input_level) * k
	if not transmitting or not _has_audience():
		_down.reset()
		_pcm.clear()
		_hp_x = 0.0
		_hp_y = 0.0
		_gate_hold = 0
		return
	_mono.resize(avail)
	for j in avail:
		var v: Vector2 = frames[j]
		_mono[j] = (v.x + v.y) * 0.5
	var low: PackedFloat32Array = _down.process(_mono)
	# DC blocker at 8 kHz so mic offset doesn't open the gate or waste mu-law range.
	var x1: float = _hp_x
	var y1: float = _hp_y
	for j in low.size():
		var x: float = low[j]
		y1 = x - x1 + 0.995 * y1
		x1 = x
		low[j] = y1
	_hp_x = x1
	_hp_y = y1
	_pcm.append_array(low)
	var off: int = 0
	while _pcm.size() - off >= PACKET_SAMPLES:
		_emit_packet(_pcm.slice(off, off + PACKET_SAMPLES))
		off += PACKET_SAMPLES
	if off > 0:
		_pcm = _pcm.slice(off)


func _has_audience() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty()


func _emit_packet(chunk: PackedFloat32Array) -> void:
	var seq: int = _seq
	_seq = (_seq + 1) & 0xFFFF # gated packets still consume a number so gaps stay timed
	if mode == "open":
		var e: float = 0.0
		for s in chunk:
			e += s * s
		if sqrt(e / chunk.size()) > GATE_OPEN_RMS:
			_gate_hold = GATE_HOLD_PACKETS
		elif _gate_hold > 0:
			_gate_hold -= 1
		else:
			return
	_send_packet(Logic.build_packet(seq, MuLaw.encode(chunk)))


func _send_packet(packet: PackedByteArray) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_relay(_my_id, packet)
	else:
		_rx_to_host.rpc_id(1, packet)


## Test hook (tests/ws_net_test.sh): send `n` packets of a 400 Hz tone through the
## normal path, bypassing the mic, the gate and local keying (the host still applies
## its relay rule and rate limit).
func debug_send_tone(n: int) -> void:
	var chunk := PackedFloat32Array()
	chunk.resize(PACKET_SAMPLES)
	for j in PACKET_SAMPLES:
		chunk[j] = 0.3 * sin(TAU * 400.0 * j / VOICE_RATE)
	var enc := MuLaw.encode(chunk)
	for i in n:
		_send_packet(Logic.build_packet(_seq, enc))
		_seq = (_seq + 1) & 0xFFFF


# ---------------------------------------------------------------- transport

## Host only: apply the relay rule, forward to everyone but the sender, play locally.
func _relay(sender: int, packet: PackedByteArray) -> void:
	_read_session()
	if not Logic.should_forward(_phase, _tx, sender):
		return
	for peer in multiplayer.get_peers():
		if peer != sender:
			_rx_from_host.rpc_id(peer, sender, packet)
	if sender != _my_id and not _dedicated:
		_receive(sender, packet)


@rpc("any_peer", "call_remote", "unreliable_ordered", RPC_CHANNEL)
func _rx_to_host(packet: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0 or sender == _my_id or not Logic.valid_packet(packet):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var lim: Logic.TokenBucket = _limiters.get(sender)
	if lim == null:
		# Nominal 8000 B/s; allow 25% over for clock skew/bursts and 0.5 s of slack.
		lim = Logic.TokenBucket.new(VOICE_RATE * 1.25, VOICE_RATE * 0.5)
		_limiters[sender] = lim
	if not lim.try_take(now, packet.size() - Logic.HEADER_BYTES):
		return
	_relay(sender, packet)


@rpc("any_peer", "call_remote", "unreliable_ordered", RPC_CHANNEL)
func _rx_from_host(sender: int, packet: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != 1 or sender == _my_id:
		return
	if not Logic.valid_packet(packet):
		return
	_receive(sender, packet)


# ---------------------------------------------------------------- playback

func _receive(sender: int, packet: PackedByteArray) -> void:
	rx_counts[sender] = int(rx_counts.get(sender, 0)) + 1
	var r: Rx = _rx.get(sender)
	if r == null:
		r = _make_rx(sender)
	var now: int = Time.get_ticks_msec()
	r.last_ms = now
	r.jb.push(Logic.packet_seq(packet), Logic.packet_payload(packet), now)


func _make_rx(sender: int) -> Rx:
	var r := Rx.new()
	r.jb = JitterBuffer.new()
	r.up = Resampler.new(VOICE_RATE, _mix_rate, 3700.0, 5)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _mix_rate
	gen.buffer_length = GEN_BUFFER_S
	r.player = AudioStreamPlayer.new()
	r.player.stream = gen
	r.player.bus = RadioFx.BUS_CLEAN
	_stream_playback(r.player)
	add_child(r.player)
	r.player.play()
	r.pb = r.player.get_stream_playback() as AudioStreamGeneratorPlayback
	r.cap = int(GEN_BUFFER_S * _mix_rate)
	_rx[sender] = r
	_refresh() # applies bus/gain for the new sender
	return r


func _pump_rx() -> void:
	if _rx.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var want: int = int(RX_QUEUE_S * _mix_rate)
	var stale: Array[int] = []
	for id: int in _rx:
		var r: Rx = _rx[id]
		if now - r.last_ms > RX_IDLE_FREE_MS and r.jb.buffered() == 0:
			stale.append(id)
			continue
		if r.pb == null:
			continue
		var queued: int = r.cap - r.pb.get_frames_available()
		while queued < want:
			var data: PackedByteArray = r.jb.pop(now)
			var res: int = r.jb.last
			if res == JitterBuffer.Result.EMPTY:
				break
			if r.gain <= 0.0:
				continue # drain: keeps sequencing without decoding inaudible audio
			var mono: PackedFloat32Array
			if res == JitterBuffer.Result.PACKET:
				mono = MuLaw.decode(data)
			else:
				mono = PackedFloat32Array()
				mono.resize(PACKET_SAMPLES)
			var up: PackedFloat32Array = r.up.process(mono)
			var stereo := PackedVector2Array()
			stereo.resize(up.size())
			for j in up.size():
				stereo[j] = Vector2(up[j], up[j])
			if r.pb.can_push_buffer(stereo.size()):
				r.pb.push_buffer(stereo)
			queued += stereo.size()
	for id in stale:
		var r2: Rx = _rx[id]
		r2.player.queue_free()
		_rx.erase(id)


func _pump_fx() -> void:
	if _fx_pb == null or not _fx.is_active():
		return
	var queued: int = _fx_cap - _fx_pb.get_frames_available()
	var n: int = int(RX_QUEUE_S * 1.5 * _mix_rate) - queued
	if n > 0 and _fx_pb.can_push_buffer(n):
		_fx_pb.push_buffer(_fx.render(n))
