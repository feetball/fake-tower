class_name PilotTouchControls
extends Control
## On-screen controls for the pilot on touch devices (TouchMode). Everything
## in HOW_TO_PLAY.md section 4 without a keyboard:
##   left column   PANEL / OUTSIDE / PEDESTAL view, ATIS, PLATE, MASTER WARN
##   right column  GEAR, FLAPS UP, FLAPS DN, stacked up from the PTT button so
##                 the glareshield's ALT window above them stays visible
##   bottom strip  autopilot: HDG / ALT / SPD / BARO tabs showing the selected
##                 values; tap one to focus it, then − / + (hold to repeat in
##                 big steps), ×10 toggles big steps for taps, STD = baro STD,
##                 APPR arms / disarms the approach (caption: lateral mode).
## The big PTT button belongs to the radio HUD (bottom-right); this layout keeps
## clear of it and of the HUD strip, inside the display's safe area.
## All commands go through PilotAutopilot (the same path as the keys and the
## cockpit knobs, i.e. Session.send_ap), and the values shown are the
## autopilot's display values (Session.own after reconciliation).

const COL_W := 150.0
const TAB_W := 170.0
const STEP_W := 140.0
const SMALL_W := 120.0
const KNOBS := ["hdg", "alt", "spd", "baro"]
const KNOB_LABEL := {"hdg": "HDG", "alt": "ALT", "spd": "SPD", "baro": "BARO"}
const VIEWS := [["panel", "PANEL"], ["outside", "OUTSIDE"], ["pedestal", "PEDESTAL"]]

var autopilot: PilotAutopilot
var rig: PilotCameraRig
var efb: PilotEfb
var bus: PilotAvionicsBus
var annunciators: CockpitAnnunciators
var hint: Label

var focus_knob := "hdg"
var big_steps := false

var _view_btns: Dictionary = {} ## view -> TouchButton
var _atis: TouchButton
var _plate: TouchButton
var _mw: TouchButton
var _app: TouchButton
var _gear: TouchButton
var _flaps_up: TouchButton
var _flaps_dn: TouchButton
var _tabs: Dictionary = {} ## knob -> TouchButton
var _minus: TouchButton
var _plus: TouchButton
var _big: TouchButton
var _std: TouchButton
var _left: Array[TouchButton] = []
var _right: Array[TouchButton] = []
var _strip: Array[TouchButton] = []
var _strip_rect := Rect2()


func _ready() -> void:
	name = "TouchControls"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _build() -> void:
	for v: Array in VIEWS:
		var view := String(v[0])
		var b := _button(String(v[1]), "VIEW")
		b.tapped.connect(func() -> void: rig.set_view(view))
		_view_btns[view] = b
		_left.append(b)
	_atis = _button("ATIS", "EFB")
	_atis.tapped.connect(func() -> void: efb.toggle("atis"))
	_plate = _button("PLATE", "EFB")
	_plate.tapped.connect(func() -> void: efb.toggle("plate"))
	_mw = _button("MASTER\nWARN", "")
	_mw.tint = UiTheme.RED
	_mw.font_size = 18
	_mw.tapped.connect(_ack_master)
	_left.append_array([_atis, _plate, _mw])

	_app = _button("APPR", "MODE")
	_app.tapped.connect(func() -> void: autopilot.toggle_app())
	_gear = _button("UP", "GEAR")
	_gear.tapped.connect(func() -> void: autopilot.toggle_gear())
	_flaps_up = _button("UP", "FLAPS")
	_flaps_up.tapped.connect(func() -> void: autopilot.set_flaps(int(autopilot.own.get("flaps", 0)) - 1))
	_flaps_dn = _button("DN", "FLAPS")
	_flaps_dn.tapped.connect(func() -> void: autopilot.set_flaps(int(autopilot.own.get("flaps", 0)) + 1))
	_right.append_array([_gear, _flaps_up, _flaps_dn])

	for k: String in KNOBS:
		var t := _button("", KNOB_LABEL[k])
		t.mono = true
		t.font_size = 30
		t.tapped.connect(func() -> void: focus_knob = k)
		_tabs[k] = t
		_strip.append(t)
	_minus = _button("−", "")
	_plus = _button("+", "")
	for pair: Array in [[_minus, -1], [_plus, 1]]:
		var b := pair[0] as TouchButton
		var dir := int(pair[1])
		b.font_size = 46
		b.fire_on_down = true
		b.repeat = true
		b.tapped.connect(func() -> void: autopilot.nudge(focus_knob, dir, big_steps))
		b.repeated.connect(func() -> void: autopilot.nudge(focus_knob, dir, true))
	_big = _button("×10", "STEP")
	_big.tapped.connect(func() -> void: big_steps = not big_steps)
	_std = _button("STD", "BARO")
	_std.tapped.connect(func() -> void: autopilot.toggle_std())
	_strip.append_array([_minus, _plus, _big, _std, _app])


func _button(txt: String, cap: String) -> TouchButton:
	var b := TouchButton.make(txt, Vector2(COL_W, TouchMode.TARGET_PX), cap)
	b.glass_alpha = 1.0 # opaque: the HDR glareshield digits bleed through any transparency
	add_child(b)
	return b


func _ack_master() -> void:
	# Same as clicking MASTER WARN / MASTER CAUT on the glareshield.
	if annunciators != null and not annunciators.controls.is_empty():
		annunciators.controls[0].click()


## Bottom strip rect (canvas units), for the EFB and anything else to keep clear of.
func strip_rect() -> Rect2:
	return _strip_rect


func _layout() -> void:
	var vp := get_viewport()
	var safe := TouchMode.safe_rect(vp)
	var b := TouchMode.target_px(vp)
	var gap := TouchMode.GAP
	var edge := TouchMode.EDGE
	var hud := get_tree().get_first_node_in_group(&"radio_hud")
	var top := safe.position.y + edge
	var ptt := Rect2()
	if hud != null and hud.has_method(&"get_reserved_top_px"):
		top = maxf(top, float(hud.call(&"get_reserved_top_px")) + 12.0)
		if hud.has_method(&"get_touch_ptt_rect"):
			ptt = hud.call(&"get_touch_ptt_rect")
	else:
		top = maxf(top, 70.0)
	var bottom := safe.end.y - edge

	# Left column: shrink rows only if a short screen cannot fit them.
	var h := minf(b, (bottom - top - gap * (_left.size() - 1)) / _left.size())
	var x := safe.position.x + edge
	for i in _left.size():
		_place(_left[i], Vector2(x, top + i * (h + gap)), Vector2(COL_W, h))
	var left_end := x + COL_W

	# Right column, stacked upwards from just above the PTT button.
	var rx := safe.end.x - edge - COL_W
	var right_bottom := (ptt.position.y - gap) if ptt.has_area() else bottom
	var n := _right.size()
	var rh := minf(b, (right_bottom - top - gap * (n - 1)) / n)
	for i in n:
		_place(_right[i], Vector2(rx, right_bottom - (n - i) * rh - (n - 1 - i) * gap), Vector2(COL_W, rh))

	# Bottom strip between the left column and the PTT button.
	var span_l := left_end + gap * 2.0
	var span_r := (ptt.position.x - gap * 2.0) if ptt.has_area() else (rx - gap * 2.0)
	var widths: Array[float] = [TAB_W, TAB_W, TAB_W, TAB_W, STEP_W, STEP_W, SMALL_W, SMALL_W, SMALL_W]
	var total := gap * (widths.size() - 1) + gap * 4.0 # extra gaps after the tabs and before APPR
	for w in widths:
		total += w
	var k := minf(1.0, (span_r - span_l) / total)
	var sx := span_l + maxf(0.0, (span_r - span_l - total * k) * 0.5)
	var sy := bottom - b
	_strip_rect = Rect2(sx, sy, total * k, b)
	for i in _strip.size():
		_place(_strip[i], Vector2(sx, sy), Vector2(widths[i] * k, b))
		sx += widths[i] * k + gap * k + (gap * 2.0 * k if i == 3 or i == 7 else 0.0)

	if efb != null:
		efb.bottom_reserved = vp.get_visible_rect().size.y - sy + 6.0
	if hint != null:
		hint.offset_left = span_l
		hint.offset_bottom = sy - vp.get_visible_rect().size.y - 10.0
		hint.offset_top = hint.offset_bottom - 26.0


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.custom_minimum_size = sz
	c.size = sz


func _process(_delta: float) -> void:
	if autopilot == null:
		return
	if Engine.get_process_frames() % 60 == 0:
		_layout() # cheap; follows HUD / safe-area changes
	var own := autopilot.own
	for v: String in _view_btns:
		(_view_btns[v] as TouchButton).lit = rig != null and rig.view_name == v
	_atis.lit = efb != null and efb.is_open and efb.page == "atis"
	_plate.lit = efb != null and efb.is_open and efb.page == "plate"
	var warn := bus != null and not bus.warnings.is_empty()
	_mw.lit = warn
	_mw.caption = String(bus.warnings[0]) if warn else ""

	_app.lit = bool(own.get("app_armed", false))
	_app.caption = String(own.get("ap_mode", "HDG"))
	var gear_down := bool(own.get("gear_down", false))
	var gear_pos := bus.gear_pos if bus != null else (1.0 if gear_down else 0.0)
	_gear.text = "DOWN" if gear_down else "UP"
	if gear_pos > 0.02 and gear_pos < 0.98:
		_gear.text = "TRANS"
	_gear.lit = gear_down
	var flaps := int(own.get("flaps", 0))
	for f: TouchButton in [_flaps_up, _flaps_dn]:
		f.caption = "FLAPS %d" % flaps
	_flaps_up.disabled = own.is_empty() or flaps <= 0
	_flaps_dn.disabled = own.is_empty() or flaps >= 3

	for kn: String in KNOBS:
		var t := _tabs[kn] as TouchButton
		var v := autopilot.display_value(kn)
		match kn:
			"hdg":
				t.text = "%03d" % v
			"baro":
				t.text = "STD" if v == 1013 else str(v)
			_:
				t.text = str(v)
		t.lit = kn == focus_knob
		t.lit_text_color = UiTheme.AMBER if autopilot.is_pending(kn) else Color(0, 0, 0, 0)
	_big.lit = big_steps
	_big.text = "×5" if focus_knob == "baro" else "×10"
	_std.lit = autopilot.display_value("baro") == 1013
