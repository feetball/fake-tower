extends Control
## Controller toolbar for touch devices (TouchMode), along the bottom edge
## left of the radio HUD's PTT button:
##   LAYERS (opens a grid of the eight map layers), MEASURE (one-finger drag
##   draws the range/bearing line instead of panning), ZOOM − / ZOOM +, RESET,
##   ROOM (scope / room framing, the Tab key);
##   with a target selected: LDR −45° / +45° (turn its data block), AUTO
##   (automatic placement), DESEL (deselect and clear the measuring line).
## Gestures on the scope itself are in scope_touch.gd.

const ScopeDisplay := preload("res://scenes/controller/scope/scope_display.gd")
const ScopeInput := preload("res://scenes/controller/scope/scope_input.gd")
const ScopeTouch := preload("res://scenes/controller/touch/scope_touch.gd")
const Model := preload("res://scenes/controller/scope/scope_model.gd")

const BTN_W := 130.0
const LAYER_W := 150.0

var scope: ScopeDisplay
var camera: Camera3D ## ctrl_camera.gd
var scope_touch: ScopeTouch

var _layers_btn: TouchButton
var _measure: TouchButton
var _room: TouchButton
var _main: Array[TouchButton] = []
var _sel: Array[TouchButton] = []
var _layer_panel: PanelContainer
var _layer_btns: Dictionary = {} ## key -> TouchButton
var _bar_top := 0.0


func _ready() -> void:
	name = "TouchBar"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(layout)
	layout.call_deferred()


func _build() -> void:
	_layers_btn = _button("LAYERS", "MAP")
	_layers_btn.tapped.connect(func() -> void: _layer_panel.visible = not _layer_panel.visible)
	_measure = _button("MEASURE", "RNG/BRG")
	_measure.tapped.connect(func() -> void: scope_touch.measure = not scope_touch.measure)
	var zoom_out := _button("−", "ZOOM")
	var zoom_in := _button("+", "ZOOM")
	for pair: Array in [[zoom_out, 1.0 / ScopeInput.WHEEL_STEP], [zoom_in, ScopeInput.WHEEL_STEP]]:
		var b := pair[0] as TouchButton
		var f := float(pair[1])
		b.font_size = 40
		b.fire_on_down = true
		b.repeat = true
		b.tapped.connect(func() -> void: _zoom(f))
		b.repeated.connect(func() -> void: _zoom(f))
	var reset := _button("RESET", "VIEW")
	reset.tapped.connect(func() -> void: scope.input.reset_view())
	_room = _button("ROOM", "VIEW")
	_room.tapped.connect(func() -> void: camera.call(&"toggle_framing"))
	_main.append_array([_layers_btn, _measure, zoom_out, zoom_in, reset, _room])

	var ccw := _button("−45°", "LDR")
	ccw.tapped.connect(func() -> void: _turn_leader(-45))
	var cw := _button("+45°", "LDR")
	cw.tapped.connect(func() -> void: _turn_leader(45))
	var auto := _button("AUTO", "LDR")
	auto.tapped.connect(func() -> void:
		var m := scope.ctx.model
		m.leader_dir.erase(m.selected)
		m.changed.emit())
	var desel := _button("DESEL", "TARGET")
	desel.tapped.connect(func() -> void:
		scope.ctx.rbl_active = false
		scope.ctx.model.select("")
		scope.input.chrome_changed.call())
	_sel.append_array([ccw, cw, auto, desel])

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", int(TouchMode.GAP))
	grid.add_theme_constant_override(&"v_separation", int(TouchMode.GAP))
	for key: String in Model.LAYER_KEYS:
		var lb := TouchButton.make(String(Model.LAYER_LABELS[key]), Vector2(LAYER_W, TouchMode.TARGET_PX), "LAYER")
		lb.mono = true
		lb.font_size = 26
		lb.tapped.connect(func() -> void:
			scope.ctx.model.toggle_layer(key)
			scope.redraw_all())
		_layer_btns[key] = lb
		grid.add_child(lb)
	_layer_panel = UiKit.panel(&"Glass", grid)
	_layer_panel.add_theme_stylebox_override(&"panel",
		UiTheme.flat(Color(0.02, 0.025, 0.03, 0.92), UiTheme.LINE, 1, 4, 14, 14))
	_layer_panel.visible = false
	add_child(_layer_panel)


func _button(txt: String, cap: String) -> TouchButton:
	var b := TouchButton.make(txt, Vector2(BTN_W, TouchMode.TARGET_PX), cap)
	b.font_size = 21
	add_child(b)
	return b


## Canvas units the scope layout must keep free at the bottom.
func reserved_bottom() -> float:
	var vs := get_viewport().get_visible_rect().size
	var top := _bar_top
	var ptt := _ptt_rect()
	if ptt.has_area():
		top = minf(top, ptt.position.y)
	return vs.y - top + 10.0


func _ptt_rect() -> Rect2:
	var hud := get_tree().get_first_node_in_group(&"radio_hud")
	if hud != null and hud.has_method(&"get_touch_ptt_rect"):
		return hud.call(&"get_touch_ptt_rect")
	return Rect2()


func layout() -> void:
	var vp := get_viewport()
	var safe := TouchMode.safe_rect(vp)
	var b := TouchMode.target_px(vp)
	var gap := TouchMode.GAP
	var edge := TouchMode.EDGE
	var ptt := _ptt_rect()
	var right := (ptt.position.x - gap * 2.0) if ptt.has_area() else (safe.end.x - edge)
	var left := safe.position.x + edge
	var n := _main.size() + _sel.size()
	var total := n * BTN_W + (n - 1) * gap + gap * 2.0
	var k := minf(1.0, (right - left) / total)
	_bar_top = safe.end.y - edge - b
	var x := left
	for i in n:
		var btn: TouchButton = _main[i] if i < _main.size() else _sel[i - _main.size()]
		btn.position = Vector2(x, _bar_top)
		btn.size = Vector2(BTN_W * k, b)
		x += BTN_W * k + gap * k + (gap * 2.0 * k if i == _main.size() - 1 else 0.0)
	_layer_panel.reset_size()
	_layer_panel.position = Vector2(left, _bar_top - gap - _layer_panel.size.y)


func _zoom(f: float) -> void:
	var xf := scope.ctx.xform
	xf.zoom_at(xf.plot.get_center(), f)
	scope.input.view_changed.call()


func _turn_leader(d: int) -> void:
	var m := scope.ctx.model
	if m.selected == "":
		return
	var cur := int(m.leader_dir.get(m.selected, 45))
	m.set_leader(m.selected, posmod(cur + d, 360))


func _process(_delta: float) -> void:
	if scope == null:
		return
	var has_sel := scope.ctx.model.selected != ""
	for b in _sel:
		b.visible = has_sel
	_measure.lit = scope_touch != null and scope_touch.measure
	_room.lit = bool(camera.get(&"target_room"))
	_layers_btn.lit = _layer_panel.visible
	for key: String in _layer_btns:
		(_layer_btns[key] as TouchButton).lit = bool(scope.ctx.model.layers.get(key, false))
