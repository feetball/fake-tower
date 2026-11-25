class_name PilotEfb
extends Control
## Electronic flight bag: a tablet that slides up in front of the pilot with
## two pages, ATIS (Session.atis.text) and the ILS RWY 27 approach plate.
## I / P open the page (press again to close); the tabs and the close button
## work with the mouse. Drawn on screen, not in 3D, so the chart stays sharp
## at 720p. Keeps clear of the HUD strip at the top.

signal visibility_changed_to(open: bool)

const PlateChart := preload("res://scenes/pilot/efb/plate_chart.gd")
const ATIS_PAGE := preload("res://scenes/pilot/efb/atis_page.gd")
const BEZEL := Color(0.045, 0.047, 0.052)
const SCREEN := Color(0.07, 0.075, 0.085)
const TOP_RESERVED := 70.0

var page := ""
var is_open := false
var top_reserved := TOP_RESERVED

var _tablet: Panel
var _plate: Control
var _atis: Control
var _tabs: Array[Button] = []
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tablet = Panel.new()
	_tablet.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = BEZEL
	sb.set_corner_radius_all(26)
	sb.border_color = Color(0.16, 0.17, 0.19)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 30
	_tablet.add_theme_stylebox_override(&"panel", sb)
	add_child(_tablet)
	var bar := HBoxContainer.new()
	bar.name = "Tabs"
	bar.add_theme_constant_override(&"separation", 10)
	_tablet.add_child(bar)
	for spec: Array in [["ATIS  (I)", "atis"], ["ILS 27 PLATE  (P)", "plate"]]:
		var b := _tab_button(String(spec[0]))
		var pg := String(spec[1])
		b.pressed.connect(func() -> void: show_page(pg))
		bar.add_child(b)
		_tabs.append(b)
	var close := _tab_button("CLOSE  ✕")
	close.pressed.connect(close_efb)
	bar.add_child(close)
	_plate = PlateChart.new()
	_tablet.add_child(_plate)
	_atis = ATIS_PAGE.new()
	_tablet.add_child(_atis)
	_tablet.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _tab_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override(&"font", Avionics.sans(true))
	b.add_theme_font_size_override(&"font_size", 20)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.13, 0.14, 0.16) if st != "hover" else Color(0.2, 0.22, 0.25)
		s.set_corner_radius_all(8)
		s.content_margin_left = 18
		s.content_margin_right = 18
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override(&"font_color", Color(0.8, 0.84, 0.88))
	return b


func _layout() -> void:
	var vs := get_viewport_rect().size
	var avail := Vector2(vs.x - 80.0, vs.y - top_reserved - 30.0)
	# Landscape tablet sized to the chart's aspect plus the tab bar.
	var inner := Vector2(1440.0, 840.0)
	var k := minf((avail.x - 48.0) / inner.x, (avail.y - 48.0 - 56.0) / inner.y)
	var screen := inner * k
	var size_t := screen + Vector2(48.0, 48.0 + 56.0)
	_tablet.size = size_t
	_tablet.position = Vector2((vs.x - size_t.x) * 0.5, top_reserved + 14.0 + (0.0 if is_open else vs.y))
	var bar := _tablet.get_node("Tabs") as HBoxContainer
	bar.position = Vector2(24.0, 14.0)
	bar.size = Vector2(screen.x, 40.0)
	for c: Control in [_plate, _atis]:
		c.position = Vector2(24.0, 70.0)
		c.size = screen
		c.queue_redraw()


func toggle(p: String) -> void:
	if is_open and page == p:
		close_efb()
	else:
		show_page(p)


func show_page(p: String) -> void:
	page = p
	_plate.visible = p == "plate"
	_atis.visible = p == "atis"
	_plate.set("qnh", int(Session.atis.get("qnh", 0)))
	_plate.queue_redraw()
	_atis.queue_redraw()
	for i in _tabs.size():
		_tabs[i].modulate = Color(1.3, 1.3, 1.3) if (i == 0) == (p == "atis") else Color(0.75, 0.75, 0.75)
	if not is_open:
		is_open = true
		_tablet.visible = true
		_slide(true)
		visibility_changed_to.emit(true)


func close_efb() -> void:
	if not is_open:
		return
	is_open = false
	_slide(false)
	visibility_changed_to.emit(false)


func _slide(up: bool) -> void:
	var vs := get_viewport_rect().size
	var y_open := top_reserved + 14.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if up else Tween.EASE_IN)
	_tween.tween_property(_tablet, "position:y", y_open if up else vs.y + 20.0, 0.35)
	if not up:
		_tween.tween_callback(func() -> void: _tablet.visible = false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("show_atis"):
		toggle("atis")
		get_viewport().set_input_as_handled()
	elif event.is_action("show_plate"):
		toggle("plate")
		get_viewport().set_input_as_handled()
