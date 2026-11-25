class_name SettingsPanel
extends Control
## Esc panel: master volume, fullscreen, leave game, quit. Owned by main.gd and
## also opened from the main menu's Settings item. Does not pause the tree
## (the round is networked and keeps running).

signal closed
signal leave_requested

var _volume: HSlider
var _volume_value: Label
var _fullscreen: CheckButton
var _leave: Button
var _title: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var body := UiKit.vbox(18)
	body.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(UiKit.panel(&"Glass", body))

	_title = UiKit.label("Settings", &"Big")
	body.add_child(_title)
	body.add_child(UiKit.hsep())

	body.add_child(UiKit.heading("Master volume"))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.value_changed.connect(_on_volume)
	_volume_value = UiKit.label("", &"Mono")
	_volume_value.custom_minimum_size = Vector2(64.0, 0.0)
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(UiKit.hbox(16, [_volume, _volume_value]))

	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.toggled.connect(func(on: bool) -> void: UiSettings.apply_fullscreen(on))
	body.add_child(_fullscreen)
	body.add_child(UiKit.label("Push-to-talk: hold Space, or hold the PTT button in the radio strip.", &"Small", true))

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
	_volume.set_value_no_signal(UiSettings.volume())
	_volume_value.text = "%d%%" % int(round(UiSettings.volume() * 100.0))
	_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		or UiSettings.fullscreen())
	visible = true
	_volume.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_volume(v: float) -> void:
	_volume_value.text = "%d%%" % int(round(v * 100.0))
	UiSettings.apply_volume(v)
