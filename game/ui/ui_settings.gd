class_name UiSettings
extends RefCounted
## Persistent per-user shell settings (user://settings.cfg): player name, last
## join address/port, master / ambient / radio volume, fullscreen, reading the
## text radio aloud.

const PATH := "user://settings.cfg"
const SECTION := "shell"

static var _cfg: ConfigFile


static func _file() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH) # missing file is fine
	return _cfg


static func get_value(key: String, fallback: Variant) -> Variant:
	var v: Variant = _file().get_value(SECTION, key, fallback)
	return fallback if typeof(v) != typeof(fallback) else v


static func set_value(key: String, value: Variant) -> void:
	_file().set_value(SECTION, key, value)
	_file().save(PATH)


static func volume() -> float:
	return clampf(get_value("volume", 0.8), 0.0, 1.0)


## Master volume: the Master bus, which every other bus (the radio ones too) feeds.
## The read-aloud voices play outside Godot's buses and apply it themselves.
static func apply_volume(v: float, persist: bool = true) -> void:
	v = clampf(v, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(&"Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(bus, v <= 0.001)
	if persist:
		set_value("volume", v)


## Flight-deck ambience (engines, slipstream, rain, ground roll, gear and flap
## motors), read by the cockpit audio as it mixes. Aural warnings are not scaled,
## so turning the ambience down never silences a terrain or stall warning.
static func ambient_volume() -> float:
	return clampf(get_value("ambient_volume", 1.0), 0.0, 1.0)


static func set_ambient_volume(v: float) -> void:
	set_value("ambient_volume", clampf(v, 0.0, 1.0))


## The radio: voices on the frequency (the Voice buses, static and squeal included)
## and the text radio read aloud.
static func radio_volume() -> float:
	return clampf(get_value("radio_volume", 1.0), 0.0, 1.0)


static func apply_radio_volume(v: float, persist: bool = true) -> void:
	v = clampf(v, 0.0, 1.0)
	Sess.set_voice_volume(v)
	if persist:
		set_value("radio_volume", v)


## Volume (0..100) for the read-aloud voices, which bypass the audio buses.
static func read_aloud_volume() -> int:
	return clampi(int(round(volume() * radio_volume() * 100.0)), 0, 100)


static func fullscreen() -> bool:
	return get_value("fullscreen", false)


static func apply_fullscreen(on: bool, persist: bool = true) -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	if persist:
		set_value("fullscreen", on)


## Read text-radio messages aloud (ui/read_aloud.gd). On unless turned off.
static func read_aloud() -> bool:
	return get_value("read_aloud", true)


static func set_read_aloud(on: bool) -> void:
	set_value("read_aloud", on)


static func apply_all() -> void:
	apply_volume(volume(), false)
	apply_radio_volume(radio_volume(), false)
	if fullscreen():
		apply_fullscreen(true, false)
