class_name MenuScreen
extends Node
## Main menu + lobby over the live airport backdrop. Shows the lobby panel in
## phase "lobby", the main menu otherwise. main.gd owns the settings panel.

signal settings_requested

@onready var _ui: Control = %UI
var _main: MainMenuPanel
var _lobby: LobbyPanel
var _howto: Control
var _shown := ""


func _ready() -> void:
	_ui.theme = UiTheme.get_theme()
	_main = MainMenuPanel.new()
	_main.name = "MainMenu"
	_main.settings_requested.connect(func() -> void: settings_requested.emit())
	_main.how_to_play_requested.connect(open_how_to_play)
	_ui.add_child(_main)
	_lobby = LobbyPanel.new()
	_lobby.name = "Lobby"
	_ui.add_child(_lobby)
	_howto = _build_how_to_play()
	_ui.add_child(_howto)
	Sess.connect_signal(&"phase_changed", func(_p: String) -> void: sync())
	Sess.connect_signal(&"lobby_changed", sync)
	sync()


func sync() -> void:
	var want := "lobby" if Sess.phase() == "lobby" else "main"
	_main.visible = want == "main"
	_lobby.visible = want == "lobby"
	if want == "lobby":
		_howto.visible = false
	if want != _shown:
		var backdrop := get_node_or_null(^"Backdrop") as ApproachBackdrop
		if backdrop != null and backdrop.camera != null:
			backdrop.set_framing(want if want == "lobby" else "menu", 0.0 if _shown == "" else 3.5)
		_shown = want
		_fade_in(_lobby if want == "lobby" else _main)
		if want == "lobby":
			_lobby.focus_default.call_deferred()
		else:
			_main.focus_default.call_deferred()


func refocus() -> void:
	if _lobby.visible:
		_lobby.focus_default()
	else:
		_main.focus_default()


func show_message(msg: String) -> void:
	_main.show_message(msg)


func main_panel() -> MainMenuPanel:
	return _main


## True when Esc was consumed by closing an overlay inside the menu.
func close_overlay() -> bool:
	if _howto.visible:
		_howto.visible = false
		_main.focus_default()
		return true
	return false


func open_how_to_play() -> void:
	_howto.visible = true
	_fade_in(_howto)


func _fade_in(c: CanvasItem) -> void:
	c.modulate.a = 0.0
	create_tween().tween_property(c, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)


func _build_how_to_play() -> Control:
	var root := Control.new()
	root.name = "HowToPlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := UiKit.vbox(20)
	var head := UiKit.hbox(12, [UiKit.label("How to play", &"Big"), UiKit.spacer(0.0, true),
		UiKit.button("Close", &"Ghost", close_overlay)])
	body.add_child(head)
	body.add_child(UiKit.hsep())
	var win := UiKit.label("The round ends when no aircraft is still flying. The tower (real controller and pilots) wins if more than half the aircraft land; otherwise the impostor wins.", &"", true)
	body.add_child(win)
	body.add_child(HowToPlay.build(false))
	var panel := UiKit.panel(&"Glass", body)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -930.0
	panel.offset_right = -110.0
	panel.offset_top = 150.0
	panel.offset_bottom = 150.0
	root.add_child(panel)
	root.visible = false
	return root
