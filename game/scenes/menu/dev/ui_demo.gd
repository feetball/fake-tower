extends Node
## Development-only fake Session/Voice that fills the shell with sample data,
## for screenshots: run with user arg --ui-demo=<screen>, where <screen> is
##   menu | join | howto | settings | lobby | lobby_client |
##   hud_pilot | hud_controller | hud_impostor | end | end_client
## Optional --ui-radio=idle|rx|tx|blocked picks the HUD radio state.
## Never used in normal play.

signal lobby_changed()
signal round_began()
signal own_updated(ac: Dictionary)
signal radar_swept(targets: Array)
signal radio_changed(tx: Array)
signal round_event(event: Dictionary)
signal round_ended(result: Dictionary)
signal phase_changed(phase: String)
signal error(msg: String)
signal connection_lost()

const DEFAULT_PORT := 27270

var phase := "menu"
var my_id := 1
var my_name := "Mara"
var is_host := true
var players: Array[Dictionary] = []
var round_players: Array[Dictionary] = []
var my_role := ""
var i_am_impostor := false
var my_callsign := ""
var world: Dictionary = {}
var atis: Dictionary = {}
var own: Dictionary = {}
var radar: Array[Dictionary] = []
var radio_tx: Array[int] = []
var events: Array[Dictionary] = []
var result: Dictionary = {}
var round_time := 0.0
var min_players := 4

var _screen := ""
var _voice: FakeVoice


class FakeVoice:
	extends Node
	signal status_changed()
	var mic_ok := true
	var input_level := 0.0
	var _t := 0.0

	func set_volume(_v: float) -> void:
		pass

	func _process(delta: float) -> void:
		_t += delta
		input_level = clampf(0.45 + 0.3 * sin(_t * 9.0) * sin(_t * 2.3), 0.0, 1.0)


func setup(screen: String, _main: Node) -> void:
	_screen = screen
	_voice = FakeVoice.new()
	add_child(_voice)
	Sess.session_override = self
	Sess.voice_override = _voice
	players = [
		{"id": 1, "name": "Mara", "host": true, "connected": true},
		{"id": 2, "name": "Joost", "host": false, "connected": true},
		{"id": 3, "name": "Ines", "host": false, "connected": true},
		{"id": 4, "name": "Theo", "host": false, "connected": true},
		{"id": 5, "name": "Kasia", "host": false, "connected": false},
	]
	round_players = [
		{"id": 1, "name": "Mara", "role": "pilot", "callsign": "SKW412"},
		{"id": 2, "name": "Joost", "role": "controller", "callsign": ""},
		{"id": 3, "name": "Ines", "role": "controller", "callsign": ""},
		{"id": 4, "name": "Theo", "role": "pilot", "callsign": "DLH9KT"},
		{"id": 5, "name": "Kasia", "role": "pilot", "callsign": "EZY27F"},
	]
	match screen:
		"lobby":
			phase = "lobby"
		"lobby_client":
			phase = "lobby"
			is_host = false
			my_id = 3
			players[3]["connected"] = false
		"hud_pilot", "hud_controller", "hud_impostor", "end", "end_client":
			phase = "playing"
			round_time = 437.0
			if screen == "hud_pilot" or screen == "end" or screen == "end_client":
				my_role = "pilot"
				my_callsign = "SKW412"
				own = {"callsign": "SKW412", "status": "flying"}
				radio_tx = [2]
			elif screen == "hud_controller":
				my_id = 2
				my_role = "controller"
				radio_tx = [2]
			else:
				my_id = 3
				my_role = "controller"
				i_am_impostor = true
				radio_tx = [2, 4]
			if screen == "end_client":
				is_host = false
			_apply_radio_arg()
	if screen.begins_with("end"):
		events = [
			{"time": 212.0, "kind": "fuel", "callsigns": ["EZY27F"]},
			{"time": 655.0, "kind": "landed", "callsigns": ["SKW412"]},
			{"time": 702.0, "kind": "terrain", "callsigns": ["DLH9KT"]},
		]
		result = {
			"winner": "impostor", "real_controller_id": 2, "impostor_id": 3,
			"outcomes": [
				{"callsign": "SKW412", "player_id": 1, "outcome": "landed"},
				{"callsign": "DLH9KT", "player_id": 4, "outcome": "terrain"},
				{"callsign": "EZY27F", "player_id": 5, "outcome": "fuel"},
			],
			"duration_sec": 702.0,
		}
		_end_later.call_deferred()


func _end_later() -> void:
	await get_tree().create_timer(0.2).timeout
	phase = "ended"
	round_ended.emit(result)
	phase_changed.emit(phase)


func _apply_radio_arg() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-radio="):
			match a.trim_prefix("--ui-radio="):
				"idle":
					radio_tx = []
				"rx":
					radio_tx = [2]
				"tx":
					radio_tx = [my_id]
				"blocked":
					radio_tx = [2, 4]


func _process(delta: float) -> void:
	if phase == "playing":
		round_time += delta


## Called by main.gd once the menu exists, to open sub-panels for a screenshot.
func on_menu_ready(menu: MenuScreen, settings: SettingsPanel) -> void:
	await get_tree().process_frame
	match _screen:
		"join":
			menu.main_panel().open_join_form()
			menu.show_message("Could not connect to 192.168.1.40:27270 (timed out).")
		"howto":
			menu.open_how_to_play()
		"settings":
			settings.open(false)


## Stand-in for the pilot/controller views: the backdrop from a cockpit-like
## camera, so the HUD can be judged over a real 3D frame.
func make_view(_role: String) -> Node:
	var bd := (load("res://scenes/menu/backdrop/approach_backdrop.tscn") as PackedScene).instantiate() as ApproachBackdrop
	bd.ready.connect(func() -> void: bd.set_framing("cockpit", 0.0))
	return bd


# --- Session API (no-ops for the demo) ------------------------------------

func host_game(_n: String, _p: int = DEFAULT_PORT) -> Error:
	phase = "lobby"
	phase_changed.emit(phase)
	return OK


func join_game(_n: String, _a: String, _p: int = DEFAULT_PORT) -> Error:
	return OK


func leave() -> void:
	phase = "menu"
	phase_changed.emit(phase)


func start_round() -> void:
	pass


func return_to_lobby() -> void:
	phase = "lobby"
	phase_changed.emit(phase)


func set_ptt(on: bool) -> void:
	radio_tx = [my_id] if on else []
	radio_changed.emit(radio_tx)


func start_demo(_role: String) -> void:
	pass


func player_name(id: int) -> String:
	for p in players:
		if int(p["id"]) == id:
			return p["name"]
	return "?"
