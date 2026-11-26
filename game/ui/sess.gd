class_name Sess
extends RefCounted
## Defensive access to the Session and Voice autoloads for the UI shell.
## Either may be missing or incomplete while the project is assembled, so every
## read has a fallback and every call is checked. --ui-demo installs a fake via
## session_override / voice_override (see scenes/menu/dev/ui_demo.gd).

const DEFAULT_PORT := 27270

static var session_override: Object = null
static var voice_override: Object = null


static func session() -> Object:
	if session_override != null:
		return session_override
	return _autoload(^"/root/Session")


static func voice() -> Object:
	if voice_override != null:
		return voice_override
	return _autoload(^"/root/Voice")


static func _autoload(path: NodePath) -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path)


static func val(key: StringName, fallback: Variant) -> Variant:
	return _read(session(), key, fallback)


static func voice_val(key: StringName, fallback: Variant) -> Variant:
	return _read(voice(), key, fallback)


static func _read(obj: Object, key: StringName, fallback: Variant) -> Variant:
	if obj == null:
		return fallback
	var v: Variant = obj.get(key)
	if v == null:
		return fallback
	if fallback != null and typeof(v) != typeof(fallback):
		var numeric := [TYPE_INT, TYPE_FLOAT]
		if typeof(v) in numeric and typeof(fallback) in numeric:
			return float(v) if typeof(fallback) == TYPE_FLOAT else int(v)
		return fallback
	return v


static func invoke(method: StringName, args: Array = []) -> Variant:
	var s := session()
	if s == null or not s.has_method(method):
		push_warning("Session.%s is not available" % method)
		return null
	return s.callv(method, args)


static func connect_signal(sig: StringName, c: Callable) -> void:
	var s := session()
	if s != null and s.has_signal(sig) and not s.is_connected(sig, c):
		s.connect(sig, c)


static func disconnect_signal(sig: StringName, c: Callable) -> void:
	var s := session()
	if s != null and s.has_signal(sig) and s.is_connected(sig, c):
		s.disconnect(sig, c)


static func connect_voice_signal(sig: StringName, c: Callable) -> void:
	var v := voice()
	if v != null and v.has_signal(sig) and not v.is_connected(sig, c):
		v.connect(sig, c)


# --- typed shortcuts -------------------------------------------------------

static func phase() -> String:
	return val(&"phase", "menu")


static func my_id() -> int:
	return val(&"my_id", 0)


static func is_host() -> bool:
	return val(&"is_host", false)


## May start the round / return to the lobby: the player-host, or a dedicated
## server's lobby leader. Falls back to is_host for sessions without is_leader.
static func can_lead() -> bool:
	return val(&"is_leader", is_host())


## The host we joined is a dedicated server (no host player; a leader instead).
static func server_dedicated() -> bool:
	return val(&"server_dedicated", false)


static func my_role() -> String:
	return val(&"my_role", "")


static func i_am_impostor() -> bool:
	return val(&"i_am_impostor", false)


static func my_callsign() -> String:
	return val(&"my_callsign", "")


static func players() -> Array:
	return val(&"players", [])


static func round_players() -> Array:
	return val(&"round_players", [])


static func radio_tx() -> Array:
	return val(&"radio_tx", [])


static func round_time() -> float:
	return float(val(&"round_time", 0.0))


static func min_players() -> int:
	return val(&"min_players", 4)


static func result() -> Dictionary:
	return val(&"result", {})


static func events() -> Array:
	return val(&"events", [])


static func default_port() -> int:
	var s := session()
	if s != null and s.get_script() is Script:
		var consts: Dictionary = (s.get_script() as Script).get_script_constant_map()
		if consts.get("DEFAULT_PORT") is int:
			return consts["DEFAULT_PORT"]
	return DEFAULT_PORT


static func player_name(id: int) -> String:
	if id == 0:
		return "—"
	var s := session()
	if s != null and s.has_method(&"player_name"):
		var n: Variant = s.call(&"player_name", id)
		if n is String and n != "":
			return n
	for list: Array in [round_players(), players()]:
		for p: Variant in list:
			if p is Dictionary and int(p.get("id", -1)) == id:
				return str(p.get("name", ""))
	return "Player %d" % id


static func round_player(id: int) -> Dictionary:
	for p: Variant in round_players():
		if p is Dictionary and int(p.get("id", -1)) == id:
			return p
	return {}


# --- voice -----------------------------------------------------------------

static func mic_ok() -> bool:
	return voice_val(&"mic_ok", false)


## Why the microphone is or is not working, for the UI ("" if Voice does not say).
static func mic_status() -> String:
	return voice_val(&"mic_status", "")


static func input_level() -> float:
	return float(voice_val(&"input_level", 0.0))


static func has_voice() -> bool:
	return voice() != null


static func set_voice_volume(v: float) -> void:
	var vo := voice()
	if vo != null and vo.has_method(&"set_volume"):
		vo.call(&"set_volume", v)
