class_name ReadAloud
extends Node
## Reads the text radio aloud with the system's text-to-speech (DisplayServer.tts_*),
## one voice (or pitch) per sender so the two controllers sound like two people, as
## they would on a real frequency. Our own transmissions are not read back to us, and
## nothing is read while a solo round fast-forwards. Off when the platform has no
## text-to-speech or the "Read radio messages aloud" setting is off.
## (OS voices play outside Godot's audio buses: no radio filter on them.)

const RATE := 1.1
const PITCHES: Array[float] = [1.0, 0.86, 1.14, 0.93, 1.07]

var _voices: PackedStringArray = []
var _assigned: Dictionary = {} ## sender id -> [voice id, pitch]
var _next := 0


static func available() -> bool:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return false
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


func _ready() -> void:
	if available():
		_voices = DisplayServer.tts_get_voices_for_language("en")
	Sess.connect_signal(&"datalink", _on_datalink)
	Sess.connect_signal(&"round_began", func() -> void:
		_assigned.clear()
		_next = 0)
	Sess.connect_signal(&"phase_changed", func(p: String) -> void:
		if p != "playing":
			stop())


static func stop() -> void:
	if available():
		DisplayServer.tts_stop()


func _on_datalink(m: Dictionary) -> void:
	if not UiSettings.read_aloud() or not available():
		return
	if _voices.is_empty():
		# Browsers load their voices after start-up: ask again when there is something to say.
		_voices = DisplayServer.tts_get_voices_for_language("en")
		if _voices.is_empty():
			return
	if String(m.get("status", "")) != "ok" or String(m.get("text", "")) == "":
		return
	if int(m.get("from", 0)) == Sess.my_id() or bool(Sess.val(&"fast_forward", false)):
		return
	var v := _voice_for(int(m.get("from", 0)))
	var volume := clampi(int(round(UiSettings.volume() * 100.0)), 0, 100)
	DisplayServer.tts_speak(_spoken(String(m["text"])), String(v[0]), volume, float(v[1]), RATE)


func _voice_for(id: int) -> Array:
	if not _assigned.has(id):
		_assigned[id] = [_voices[_next % _voices.size()], PITCHES[_next % PITCHES.size()]]
		_next += 1
	return _assigned[id]


## Say numbers the radio way where the engine would read them as quantities.
static func _spoken(text: String) -> String:
	return text.replace("QNH", "Q N H").replace("ILS", "I L S")
