class_name SettingsPanel
extends Control
## Esc panel: volume (master, ambient noise, radio / ATC voice), fullscreen,
## reading the text radio aloud, leave game, quit. Owned by main.gd and also
## opened from the main menu's Settings item. Does not pause the tree (the round
## is networked and keeps running), so the sliders take effect as they move.

signal closed
signal leave_requested

var _volume: HSlider
var _ambient: HSlider
var _radio: HSlider
var _fullscreen: CheckButton
var _read_aloud: CheckButton
var _leave: Button
var _title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var body := UiKit.vbox(18)
	body.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(UiKit.panel(&"Glass", body))

	_title = UiKit.label("Settings", &"Big")
	body.add_child(_title)
	body.add_child(UiKit.hsep())

	body.add_child(UiKit.heading("Volume"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 10)
	body.add_child(grid)
	_volume = _slider_row(grid, "Master", "Everything the game plays.",
		func(v: float) -> void: UiSettings.apply_volume(v))
	_ambient = _slider_row(grid, "Ambient noise",
		"Flight-deck sound: engines, slipstream, rain, gear and flaps. Warnings stay at full volume.",
		func(v: float) -> void: UiSettings.set_ambient_volume(v))
	_radio = _slider_row(grid, "Radio / ATC voice",
		"Everything on the frequency: the voices, radio static, and the text radio read aloud.",
		func(v: float) -> void: UiSettings.apply_radio_volume(v))

	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.toggled.connect(func(on: bool) -> void: UiSettings.apply_fullscreen(on))
	body.add_child(_fullscreen)
	_read_aloud = CheckButton.new()
	_read_aloud.text = "Read text-radio messages aloud"
	_read_aloud.toggled.connect(func(on: bool) -> void:
		UiSettings.set_read_aloud(on)
		if not on:
			ReadAloud.stop())
	body.add_child(_read_aloud)
	if not ReadAloud.available():
		_read_aloud.disabled = true
		_read_aloud.tooltip_text = "No text-to-speech on this system."
	var ptt_help := "Push-to-talk: hold Space, or hold the PTT button in the radio strip."
	if TouchMode.active():
		ptt_help = "Push-to-talk: hold the PTT button at the bottom right of the screen."
	ptt_help += " No microphone? Use the text radio: pilots reply with W / U / S / R, controllers type or click instructions beside the scope."
	body.add_child(UiKit.label(ptt_help, &"Small", true))

	body.add_child(UiKit.hsep())
	_leave = UiKit.button("Leave game", &"Danger", func() -> void:
		close()
		leave_requested.emit())
	var quit := UiKit.button("Quit to desktop", &"Danger", func() -> void: get_tree().quit())
	var resume := UiKit.button("Resume", &"Primary", close)
	var row := UiKit.hbox(12, [_leave, quit, UiKit.spacer(0.0, true), resume])
	body.add_child(row)
	visible = false


func open(in_game: bool) -> void:
	_title.text = "Paused" if in_game else "Settings"
	_leave.visible = in_game
	_show(_volume, UiSettings.volume())
	_show(_ambient, UiSettings.ambient_volume())
	_show(_radio, UiSettings.radio_volume())
	_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		or UiSettings.fullscreen())
	_read_aloud.set_pressed_no_signal(UiSettings.read_aloud() and ReadAloud.available())
	visible = true
	if is_inside_tree():
		_volume.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## One "name | slider | 80%" row of the volume grid; `apply` gets 0..1 as it moves.
func _slider_row(grid: GridContainer, title: String, tip: String, apply: Callable) -> HSlider:
	var name_label := UiKit.label(title, &"")
	name_label.tooltip_text = tip
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.tooltip_text = tip
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(slider)
	var value := UiKit.label("", &"Mono")
	value.custom_minimum_size = Vector2(64.0, 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)
	slider.set_meta(&"value_label", value)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = _pct(v)
		apply.call(v))
	return slider


func _show(slider: HSlider, v: float) -> void:
	slider.set_value_no_signal(v)
	(slider.get_meta(&"value_label") as Label).text = _pct(v)


static func _pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))
