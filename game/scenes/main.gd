extends Node
## Application root. Swaps screens on Session.phase / my_role with fades:
##   menu / lobby  -> scenes/menu/menu.tscn (backdrop + main menu or lobby)
##   playing       -> pilot or controller view under View, radio HUD on top
##   ended         -> end screen over the frozen view
## Esc opens the settings / pause panel. No gameplay logic lives here.
## Touch devices (TouchMode): a MENU button opens the same panel (top right
## outside a round, in the HUD strip during one), bigger buttons in the
## dialogs, and TouchKeyboardAvoider keeps text fields above the on-screen keyboard.
## User arg --ui-demo=<screen> drives the UI from a local fake Session
## (scenes/menu/dev/ui_demo.gd) for screenshots.

const VIEW_PATHS := {
	"pilot": "res://scenes/pilot/pilot_view.tscn",
	"controller": "res://scenes/controller/controller_view.tscn",
}
const MENU_SCENE: PackedScene = preload("res://scenes/menu/menu.tscn")
const UI_DEMO_SCRIPT := "res://scenes/menu/dev/ui_demo.gd"

@onready var _screen_root: Node = $Screen
@onready var _view_root: Node = $View
@onready var _hud: RadioHud = $HudLayer/Hud
@onready var _end: EndScreen = $EndLayer/End
@onready var _overlay: Control = $OverlayLayer/Overlay
@onready var _fade: ColorRect = $FadeLayer/Fade

var _settings: SettingsPanel
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _menu: MenuScreen
var _view: Node
var _view_role := ""
var _mode := ""
var _busy := false
var _dirty := false
var _round_over := false
var _pending_message := ""
var _demo: Node
var _touch_menu: TouchButton


func _ready() -> void:
	UiSettings.apply_all()
	_overlay.theme = UiTheme.get_theme()
	_settings = SettingsPanel.new()
	_settings.name = "Settings"
	_settings.leave_requested.connect(func() -> void: Sess.invoke(&"leave"))
	_settings.closed.connect(_restore_focus)
	_overlay.add_child(_settings)
	_hud.settings_requested.connect(func() -> void: _settings.open(Sess.phase() != "menu"))
	if TouchMode.active():
		_build_touch()
	_build_toast()
	_hud.visible = false
	_end.visible = false
	_fade.color = Color(0, 0, 0, 1)

	var demo_screen := _user_arg("--ui-demo=")
	if demo_screen != "":
		_start_ui_demo(demo_screen)

	Sess.connect_signal(&"phase_changed", func(_p: String) -> void: _sync())
	Sess.connect_signal(&"round_began", _on_round_began)
	Sess.connect_signal(&"round_ended", _on_round_ended)
	Sess.connect_signal(&"connection_lost", _on_connection_lost)
	# In the menu the panel shows errors inline; elsewhere they become a toast.
	Sess.connect_signal(&"error", func(msg: String) -> void:
		if _mode != "menu":
			show_toast(msg))
	_sync()


func _user_arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


# --- phase handling ----------------------------------------------------------

func _desired_mode() -> String:
	match Sess.phase():
		"playing":
			return "end" if _round_over else "round"
		"ended":
			return "end"
	return "menu"


func _sync() -> void:
	if _busy:
		_dirty = true
		return
	var want := _desired_mode()
	var role := Sess.my_role()
	if want == _mode and (want == "menu" or _view_role == role):
		return
	if want == "end" and _mode == "round" and _view_role == role:
		_enter_end()
		return
	_busy = true
	await _fade_to(1.0, 0.0 if _mode == "" else 0.35)
	match want:
		"menu":
			_enter_menu()
		"round":
			_enter_round()
		"end":
			_enter_round()
			_enter_end()
	# Let the new scene build and render a frame before revealing it.
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_to(0.0, 0.9 if want == "menu" else 0.6)
	_busy = false
	if _dirty:
		_dirty = false
		_sync()


func _enter_menu() -> void:
	_mode = "menu"
	_round_over = false
	_free_view()
	_hud.visible = false
	_end.visible = false
	if _menu == null:
		_menu = MENU_SCENE.instantiate() as MenuScreen
		_menu.settings_requested.connect(func() -> void: _settings.open(false))
		_screen_root.add_child(_menu)
	if _pending_message != "":
		_menu.show_message(_pending_message)
		_pending_message = ""
	if _demo != null and _demo.has_method(&"on_menu_ready"):
		_demo.call(&"on_menu_ready", _menu, _settings)


func _enter_round() -> void:
	_mode = "round"
	_round_over = false
	_end.visible = false
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_free_view()
	_view_role = Sess.my_role()
	_view = _make_view(_view_role)
	_view_root.add_child(_view)
	_hud.visible = true
	_hud.refresh()


func _enter_end() -> void:
	_mode = "end"
	_hud.release_ptt()
	_hud.visible = false
	if _view != null:
		_view.process_mode = Node.PROCESS_MODE_DISABLED
	_end.refresh()
	_end.visible = true
	_end.modulate.a = 0.0
	create_tween().tween_property(_end, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


func _make_view(role: String) -> Node:
	if _demo != null and _demo.has_method(&"make_view"):
		return _demo.call(&"make_view", role)
	var path: String = VIEW_PATHS.get(role, "")
	if path != "" and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			return ps.instantiate()
	var ph := ViewPlaceholder.new()
	ph.role = role
	return ph


func _free_view() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	_view_role = ""


func _on_round_began() -> void:
	_round_over = false
	_sync()


func _on_round_ended(_result: Dictionary) -> void:
	_round_over = true
	_sync()


func _on_connection_lost() -> void:
	_pending_message = "Connection to the host was lost."
	_round_over = false
	if _menu != null:
		_menu.show_message(_pending_message)
		_pending_message = ""
	_sync()


# --- touch -------------------------------------------------------------------

func _build_touch() -> void:
	TouchMode.enlarge_targets(_settings, TouchMode.TARGET_PX * 0.62)
	var avoider := TouchKeyboardAvoider.new()
	avoider.name = "KeyboardAvoider"
	add_child(avoider)
	_touch_menu = TouchButton.make("MENU", Vector2(150.0, 84.0))
	_touch_menu.name = "TouchMenu"
	_touch_menu.font_size = 20
	_touch_menu.tapped.connect(func() -> void:
		if _menu != null:
			_menu.close_overlay()
		_settings.open(Sess.phase() != "menu"))
	_overlay.add_child(_touch_menu)
	_overlay.move_child(_touch_menu, 0) # under the settings panel


func _process(_delta: float) -> void:
	if _touch_menu == null:
		return
	# Outside a round (menu, lobby, end screen); the HUD strip has its own.
	_touch_menu.visible = not _hud.visible and not _settings.visible and _fade.color.a < 0.5 \
		and not (_menu != null and _menu.is_overlay_open())
	var safe := TouchMode.safe_rect(get_viewport())
	_touch_menu.position = Vector2(safe.end.x - _touch_menu.size.x - TouchMode.EDGE * 2.0,
		safe.position.y + TouchMode.EDGE * 2.0)


# --- fades, toast, Esc -------------------------------------------------------

func _fade_to(alpha: float, seconds: float) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.5 else Control.MOUSE_FILTER_IGNORE
	if seconds <= 0.0:
		_fade.color.a = alpha
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _build_toast() -> void:
	_toast_label = UiKit.label("", &"", true)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = UiKit.panel(&"Glass", _toast_label)
	_toast.add_theme_stylebox_override(&"panel", UiTheme.flat(Color(0.02, 0.025, 0.03, 0.92), Color(UiTheme.AMBER, 0.5), 1, 3, 22, 12))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -60.0
	_toast.custom_minimum_size = Vector2(560.0, 0.0)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_overlay.add_child(_toast)


func show_toast(msg: String) -> void:
	if msg == "":
		return
	_toast_label.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(4.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return
	if (event as InputEventKey).keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _settings.visible:
		_settings.close()
	elif _menu != null and _menu.close_overlay():
		pass
	else:
		_hud.release_ptt()
		_settings.open(Sess.phase() != "menu")


func _restore_focus() -> void:
	if _menu != null:
		_menu.refocus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_hud.release_ptt()


# --- UI demo -----------------------------------------------------------------

func _start_ui_demo(screen: String) -> void:
	var script := load(UI_DEMO_SCRIPT) as Script
	if script == null:
		push_error("UI demo script missing")
		return
	_demo = script.new() as Node
	_demo.name = "UiDemo"
	add_child(_demo)
	_demo.call(&"setup", screen, self)
