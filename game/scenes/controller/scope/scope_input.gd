extends RefCounted
## Scope interaction in scope pixels: wheel zoom about the cursor, drag pan,
## double-click reset, right/shift-drag range-bearing line, click to select,
## Ctrl-click cycles the leader, menu bar buttons, and the keyboard shortcuts.

const Ctx := preload("res://scenes/controller/scope/scope_ctx.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")

## Numpad layout -> leader bearing (5 = automatic).
const LEADER_KEYS := {
	KEY_8: 0, KEY_9: 45, KEY_6: 90, KEY_3: 135, KEY_2: 180, KEY_1: 225, KEY_4: 270, KEY_7: 315, KEY_5: -1,
	KEY_KP_8: 0, KEY_KP_9: 45, KEY_KP_6: 90, KEY_KP_3: 135, KEY_KP_2: 180, KEY_KP_1: 225, KEY_KP_4: 270,
	KEY_KP_7: 315, KEY_KP_5: -1,
}
const LAYER_FKEYS := {KEY_F1: "rr", KEY_F2: "cl", KEY_F3: "fix", KEY_F4: "terr", KEY_F5: "msa", KEY_F6: "hold", KEY_F7: "ptl", KEY_F8: "hist"}
const DRAG_THRESHOLD := 4.0
const WHEEL_STEP := 1.15

var ctx: Ctx
var default_range_nm := 38.0
var view_changed: Callable ## the map must be redrawn
var chrome_changed: Callable ## only the chrome must be redrawn

var _drag := "" ## "", "maybe", "pan", "rbl"
var _press := Vector2.ZERO
var _last := Vector2.ZERO


func _init(c: Ctx) -> void:
	ctx = c


## Mouse event at `pos` (scope pixels). Returns true when consumed.
func pointer(e: InputEvent, pos: Vector2) -> bool:
	if e is InputEventMouseMotion:
		ctx.mouse = pos
		match _drag:
			"maybe":
				if pos.distance_to(_press) > DRAG_THRESHOLD * ctx.ui_scale:
					_drag = "pan"
			"rbl":
				ctx.rbl_b = _snap(pos)
		if _drag == "pan":
			ctx.xform.pan_pixels(pos - _last)
			view_changed.call()
		else:
			chrome_changed.call()
		_last = pos
		return true
	if not e is InputEventMouseButton:
		return false
	var mb := e as InputEventMouseButton
	ctx.mouse = pos
	if mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var f := WHEEL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_STEP
				ctx.xform.zoom_at(pos, f)
				view_changed.call()
				return true
			MOUSE_BUTTON_LEFT:
				if mb.double_click:
					_drag = ""
					reset_view()
					return true
				var id := _dcb_at(pos)
				if id != "":
					_dcb(id)
					return true
				if mb.shift_pressed:
					_start_rbl(pos)
				else:
					_drag = "maybe"
				_press = pos
				_last = pos
				return true
			MOUSE_BUTTON_RIGHT:
				if pos.y < ctx.dcb_h:
					return true
				_start_rbl(pos)
				_press = pos
				_last = pos
				return true
			MOUSE_BUTTON_MIDDLE:
				_drag = "pan"
				_press = pos
				_last = pos
				return true
		return false
	# release
	match _drag:
		"maybe":
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_click(pos, mb.ctrl_pressed)
		"rbl":
			ctx.rbl_live = false
			if pos.distance_to(_press) < DRAG_THRESHOLD * ctx.ui_scale:
				ctx.rbl_active = false
			chrome_changed.call()
	_drag = ""
	return true


func mouse_left() -> void:
	ctx.mouse = Vector2(-1, -1)
	if _drag == "rbl":
		ctx.rbl_live = false
	_drag = ""
	chrome_changed.call()


func is_dragging() -> bool:
	return _drag != ""


## Scope keyboard shortcuts. Returns true when consumed.
func key(e: InputEventKey) -> bool:
	if not e.pressed:
		return false
	if e.echo and not (e.keycode in [KEY_EQUAL, KEY_MINUS, KEY_KP_ADD, KEY_KP_SUBTRACT]):
		return false
	if e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		return false
	var kc := e.keycode
	if LEADER_KEYS.has(kc) and ctx.model.selected != "":
		var dir := int(LEADER_KEYS[kc])
		if dir < 0:
			ctx.model.leader_dir.erase(ctx.model.selected)
			ctx.model.changed.emit()
		else:
			ctx.model.set_leader(ctx.model.selected, dir)
		return true
	if LAYER_FKEYS.has(kc):
		ctx.model.toggle_layer(String(LAYER_FKEYS[kc]))
		view_changed.call()
		return true
	match kc:
		KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
			ctx.xform.zoom_at(ctx.xform.plot.get_center(), WHEEL_STEP)
			view_changed.call()
			return true
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
			ctx.xform.zoom_at(ctx.xform.plot.get_center(), 1.0 / WHEEL_STEP)
			view_changed.call()
			return true
		KEY_HOME:
			reset_view()
			return true
		KEY_DELETE, KEY_BACKSPACE:
			ctx.rbl_active = false
			ctx.model.select("")
			chrome_changed.call()
			return true
	return false


func reset_view() -> void:
	ctx.xform.reset(default_range_nm)
	view_changed.call()


func _start_rbl(pos: Vector2) -> void:
	_drag = "rbl"
	ctx.rbl_active = true
	ctx.rbl_live = true
	ctx.rbl_a = _snap(pos)
	ctx.rbl_b = ctx.rbl_a
	chrome_changed.call()


func _click(pos: Vector2, ctrl: bool) -> void:
	var cs := hit_target(pos)
	if cs != "" and ctrl:
		var cur := int(ctx.model.leader_dir.get(cs, 45))
		ctx.model.set_leader(cs, (cur + 45) % 360)
	if not ctx.rbl_live:
		ctx.rbl_active = false
	ctx.model.select(cs)
	chrome_changed.call()


## Callsign of the target (symbol or data block) under `pos`, or "".
func hit_target(pos: Vector2) -> String:
	var best := ""
	var best_d := 16.0 * ctx.ui_scale
	for cs in ctx.model.visible_callsigns(ctx.now_ms):
		var t: Dictionary = ctx.model.targets[cs]
		if String(t["status"]) == "landed":
			continue
		var d := ctx.xform.to_screen(Fmt.target_pos(t)).distance_to(pos)
		if d < best_d:
			best_d = d
			best = cs
	if best != "":
		return best
	for cs: String in ctx.block_rects:
		var r: Rect2 = ctx.block_rects[cs]
		if r.grow(3.0 * ctx.ui_scale).has_point(pos) and ctx.model.targets.has(cs):
			return cs
	return ""


func _snap(pos: Vector2) -> Vector2:
	var cs := hit_target(pos)
	if cs != "":
		return Fmt.target_pos(ctx.model.targets[cs])
	return ctx.xform.to_world(pos)


func _dcb_at(pos: Vector2) -> String:
	if pos.y > ctx.dcb_h:
		return ""
	for b: Dictionary in ctx.dcb_rects:
		if (b["rect"] as Rect2).has_point(pos):
			return String(b["id"])
	return ""


func _dcb(id: String) -> void:
	if id.begins_with("layer:"):
		ctx.model.toggle_layer(id.trim_prefix("layer:"))
		view_changed.call()
		return
	match id:
		"rng_in":
			ctx.xform.zoom_at(ctx.xform.plot.get_center(), WHEEL_STEP)
		"rng_out":
			ctx.xform.zoom_at(ctx.xform.plot.get_center(), 1.0 / WHEEL_STEP)
		"reset":
			ctx.xform.reset(default_range_nm)
		"ldr_auto":
			ctx.model.leader_dir.clear()
			ctx.model.changed.emit()
	view_changed.call()
