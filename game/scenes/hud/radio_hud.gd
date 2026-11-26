class_name RadioHud
extends Control
## In-round comms strip across the top edge, shown over both views: role line,
## frequency, radio state (IDLE / RX / TX / BLOCKED), round clock and a PTT
## button. Owns push-to-talk: hold the `ptt` action (Space) or the button.
## Views call get_reserved_top_px() (or find the node in group "radio_hud")
## to lay their content out below the strip.
## On touch devices (TouchMode) the strip's PTT button becomes a MENU button
## (settings_requested) and a large hold-to-talk button sits in the bottom-right
## corner of the safe area; views keep clear of get_touch_ptt_rect().

signal settings_requested

const STRIP_H := 58.0
const FREQ := "119.850"
const TOUCH_PTT_SIZE := 184.0

const RADIO_COLORS := {
	"idle": UiTheme.FAINT,
	"rx": UiTheme.ACCENT,
	"tx": UiTheme.AMBER,
	"blocked": UiTheme.RED,
	"dead": UiTheme.FAINT,
}
const ROLE_COLORS := {
	"pilot": UiTheme.BLUE,
	"real": UiTheme.ACCENT,
	"impostor": UiTheme.RED,
	"none": UiTheme.DIM,
}
const ROLE_TAGS := {"pilot": "PILOT", "real": "TOWER", "impostor": "IMPOSTOR", "none": "—"}

var _strip: PanelContainer
var _role_tag: Label
var _role_tag_box: PanelContainer
var _role_text: Label
var _radio_box: PanelContainer
var _radio_label: Label
var _clock: Label
var _ptt: Button
var _touch_ptt: TouchButton
var _menu_btn: TouchButton
var _key_held := false
var _mouse_held := false
var _touch_held := false
var _sent_ptt := false
var _blink := 0.0
var _radio_kind := ""


func _ready() -> void:
	add_to_group(&"radio_hud")
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Sess.connect_signal(&"radio_changed", func(_tx: Array) -> void: _refresh_radio())
	Sess.connect_signal(&"round_began", refresh)
	Sess.connect_signal(&"lobby_changed", refresh)
	refresh()


## Height of the strip in this viewport's canvas units (the units Controls use).
func get_reserved_top_px() -> float:
	if not visible:
		return 0.0
	return maxf(_strip.size.y, STRIP_H) if _strip else STRIP_H


## The big touch PTT button's rect in canvas units (empty when not on touch or hidden).
func get_touch_ptt_rect() -> Rect2:
	if _touch_ptt == null or not is_visible_in_tree():
		return Rect2()
	return Rect2(_touch_ptt.position, _touch_ptt.size)


func _build() -> void:
	_strip = PanelContainer.new()
	_strip.theme_type_variation = &"Strip"
	_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_strip.custom_minimum_size = Vector2(0.0, STRIP_H)
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_strip)
	var row := UiKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_strip.add_child(row)

	_role_tag = UiKit.label("", &"MonoSmall")
	_role_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_tag_box = UiKit.panel(&"Inset", _role_tag)
	_role_tag_box.custom_minimum_size = Vector2(118.0, 0.0)
	_role_tag_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_role_tag_box)

	_role_text = UiKit.label("", &"")
	_role_text.add_theme_font_size_override(&"font_size", 18)
	_role_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_role_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_text.clip_text = true
	_role_text.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_role_text)

	var freq := UiKit.hbox(8, [UiKit.label("APP", &"MonoSmall"), UiKit.label(FREQ, &"Mono")])
	row.add_child(freq)

	_radio_label = UiKit.label("IDLE", &"Mono")
	_radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_radio_label.clip_text = true
	_radio_box = UiKit.panel(&"Inset", _radio_label)
	_radio_box.custom_minimum_size = Vector2(260.0, 0.0)
	_radio_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_radio_box)

	_clock = UiKit.label("00:00", &"Mono")
	_clock.add_theme_font_size_override(&"font_size", 22)
	_clock.tooltip_text = "Round time"
	_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_clock)

	_ptt = UiKit.button("PTT", &"")
	_ptt.focus_mode = Control.FOCUS_NONE
	_ptt.tooltip_text = "Hold to transmit (or hold Space)"
	_ptt.custom_minimum_size = Vector2(150.0, 0.0)
	_ptt.add_theme_font_override(&"font", UiTheme.mono(600))
	_ptt.button_down.connect(func() -> void:
		_mouse_held = true
		_apply_ptt())
	_ptt.button_up.connect(func() -> void:
		_mouse_held = false
		_apply_ptt())
	row.add_child(_ptt)
	if TouchMode.active():
		_build_touch(row)


func _build_touch(row: HBoxContainer) -> void:
	_ptt.visible = false
	_menu_btn = TouchButton.make("MENU", Vector2(128.0, 44.0))
	_menu_btn.font_size = 18
	_menu_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_menu_btn.tapped.connect(func() -> void:
		release_ptt()
		settings_requested.emit())
	row.add_child(_menu_btn)
	_touch_ptt = TouchButton.make("PTT", Vector2(TOUCH_PTT_SIZE, TOUCH_PTT_SIZE), "HOLD TO TALK")
	_touch_ptt.name = "TouchPtt"
	_touch_ptt.tint = UiTheme.AMBER
	_touch_ptt.mono = true
	_touch_ptt.font_size = 40
	_touch_ptt.caption_size = 16
	_touch_ptt.corner = 18
	_touch_ptt.down.connect(func() -> void:
		_touch_held = true
		_apply_ptt())
	_touch_ptt.up.connect(func() -> void:
		_touch_held = false
		_apply_ptt())
	add_child(_touch_ptt)
	_layout_touch()
	get_viewport().size_changed.connect(_layout_touch)


func _layout_touch() -> void:
	if _touch_ptt == null:
		return
	var safe := TouchMode.safe_rect(get_viewport())
	var s := Vector2(TOUCH_PTT_SIZE, TOUCH_PTT_SIZE)
	_touch_ptt.size = s
	_touch_ptt.position = safe.end - s - Vector2(TouchMode.EDGE, TouchMode.EDGE)


func refresh() -> void:
	var r := UiText.role_line()
	var col: Color = ROLE_COLORS.get(r["kind"], UiTheme.DIM)
	_role_tag.text = ROLE_TAGS.get(r["kind"], "—")
	_role_tag.add_theme_color_override(&"font_color", col)
	var sb := UiTheme.flat(Color(col, 0.1), Color(col, 0.55), 1, 2, 10, 4)
	_role_tag_box.add_theme_stylebox_override(&"panel", sb)
	_role_text.text = r["text"]
	_role_text.tooltip_text = r["text"]
	_role_text.add_theme_color_override(&"font_color",
		UiTheme.TEXT if r["kind"] == "pilot" else col.lerp(Color.WHITE, 0.25))
	_refresh_radio()


func _process(delta: float) -> void:
	_clock.text = UiText.mmss(Sess.round_time())
	_blink += delta
	if _radio_kind == "blocked":
		_radio_label.modulate.a = 0.55 + 0.45 * absf(sin(_blink * 7.0))
	else:
		_radio_label.modulate.a = 1.0
	# Session may update radio_tx without a signal in a minimal implementation.
	if Engine.get_process_frames() % 6 == 0:
		_refresh_radio()


func _refresh_radio() -> void:
	var own: Dictionary = Sess.val(&"own", {})
	var dead := str(own.get("status", "")) == "crashed"
	var st := UiText.radio_state(Sess.radio_tx(), Sess.my_id(), _sent_ptt, dead)
	_radio_kind = st["kind"]
	var col: Color = RADIO_COLORS.get(_radio_kind, UiTheme.DIM)
	_radio_label.text = st["text"]
	_radio_label.add_theme_color_override(&"font_color", col if _radio_kind != "idle" else UiTheme.DIM)
	var active := _radio_kind in ["rx", "tx", "blocked"]
	_radio_box.add_theme_stylebox_override(&"panel",
		UiTheme.flat(Color(col, 0.14 if active else 0.03), Color(col, 0.7 if active else 0.25), 1, 2, 12, 5))
	var ptt_col := UiTheme.AMBER if _sent_ptt else UiTheme.TEXT
	_ptt.add_theme_color_override(&"font_color", ptt_col)
	_ptt.add_theme_color_override(&"font_hover_color", ptt_col)
	_ptt.add_theme_color_override(&"font_pressed_color", UiTheme.AMBER)
	_ptt.text = "● TX" if _sent_ptt else "PTT · SPACE"
	if _touch_ptt != null:
		_touch_ptt.lit = _sent_ptt
		_touch_ptt.text = "TX" if _sent_ptt else "PTT"
		_touch_ptt.caption = {"blocked": "BLOCKED", "dead": "RADIO DEAD", "rx": "RECEIVING"}.get(
			_radio_kind, "TRANSMITTING" if _sent_ptt else "HOLD TO TALK")
		_touch_ptt.tint = UiTheme.RED if _radio_kind in ["blocked", "dead"] else UiTheme.AMBER
		_touch_ptt.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not _is_ptt_event(event):
		return
	if event.is_pressed():
		if UiKit.is_text_input_focused(get_viewport()):
			return
		if event.is_echo():
			get_viewport().set_input_as_handled()
			return
		_key_held = true
	else:
		if not _key_held:
			return
		_key_held = false
	get_viewport().set_input_as_handled()
	_apply_ptt()


func _is_ptt_event(event: InputEvent) -> bool:
	if InputMap.has_action(&"ptt"):
		return event.is_action(&"ptt", true)
	return event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SPACE


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_VISIBILITY_CHANGED:
			if what != NOTIFICATION_VISIBILITY_CHANGED or not is_visible_in_tree():
				release_ptt()
		NOTIFICATION_EXIT_TREE:
			release_ptt()


func release_ptt() -> void:
	_key_held = false
	_mouse_held = false
	_touch_held = false
	if _touch_ptt != null:
		_touch_ptt.cancel()
	_apply_ptt()


func _apply_ptt() -> void:
	var on := (_key_held or _mouse_held or _touch_held) and is_inside_tree() and is_visible_in_tree()
	if on == _sent_ptt:
		return
	_sent_ptt = on
	Sess.invoke(&"set_ptt", [on])
	if is_inside_tree():
		_refresh_radio()
