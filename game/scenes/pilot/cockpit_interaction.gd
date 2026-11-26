class_name PilotInteraction
extends Node
## Mouse operation of the cockpit: a ray from the camera through the cursor
## picks the nearest CockpitControl; hover highlights it and shows a small
## tooltip; the wheel turns knobs (Shift = big steps); left-drag turns them
## continuously; a click without drag pushes buttons and moves levers.
##
## Touch (TouchMode): handled per finger from InputEventScreenTouch/Drag, never
## the emulated mouse, so it works while another finger holds PTT. A finger
## that lands on a control taps it (button, lever, baro STD) or turns it by
## dragging (knobs); a finger on empty space looks around, two pinch-zoom, and
## a double tap re-centres the view (rig.look_by / zoom_by / reset_look).

const TOUCH_DRAG_PX := 26.0 ## finger travel per knob step (fingers are coarser than a mouse)
const TOUCH_LOOK_DEG_PER_PX := 0.085
const TAP_SLOP := 14.0
const DOUBLE_TAP_S := 0.32
const DOUBLE_TAP_PX := 80.0

var camera: Camera3D
var rig: PilotCameraRig
var controls: Array[CockpitControl] = []
var tooltip: Label
var enabled := true

var _hover: CockpitControl
var _pressed: CockpitControl
var _press_pos := Vector2.ZERO
var _drag_acc := 0.0
var _dragged := false
## Touch: finger index -> {pos, start, ctl: CockpitControl or null, acc, dragged}
var _fingers: Dictionary = {}
var _pinch_d := 0.0
var _last_tap_ms := -100000
var _last_tap_pos := Vector2.ZERO
var _mouse_real := false ## last pointer event came from a real mouse (desktop --touch)


func _process(_delta: float) -> void:
	if TouchMode.active() and not _mouse_real:
		_touch_tooltip()
		return
	if not enabled or camera == null:
		_set_hover(null)
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_set_hover(null)
		return
	var mp := camera.get_viewport().get_mouse_position()
	if _pressed == null:
		_set_hover(_pick(mp))
	if tooltip != null:
		var c := _pressed if _pressed != null else _hover
		tooltip.visible = c != null
		if c != null:
			tooltip.text = c.tooltip_text()
			var canvas_pos := tooltip.get_viewport().get_mouse_position()
			tooltip.reset_size()
			var vs := tooltip.get_viewport_rect().size
			tooltip.position = Vector2(
				clampf(canvas_pos.x + 18.0, 8.0, vs.x - tooltip.size.x - 8.0),
				clampf(canvas_pos.y + 22.0, 80.0, vs.y - tooltip.size.y - 8.0))


func _pick(mp: Vector2) -> CockpitControl:
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var best: CockpitControl = null
	var best_d := INF
	for c in controls:
		if not c.is_visible_in_tree():
			continue
		var d := c.ray_hit(origin, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = c
	return best


func _set_hover(c: CockpitControl) -> void:
	if c == _hover:
		return
	if _hover != null and is_instance_valid(_hover):
		_hover.set_hover(false)
	_hover = c
	if c != null:
		c.set_hover(true)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if tooltip != null:
			tooltip.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if TouchMode.active():
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			_touch(event)
			return
		if event is InputEventMouse:
			_mouse_real = not TouchMode.is_emulated(event)
			if not _mouse_real:
				return
	if not enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _hover == null and _pressed == null:
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and _hover != null:
					_hover.scroll(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mb.shift_pressed)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				if mb.pressed and _hover != null:
					_pressed = _hover
					_press_pos = mb.position
					_drag_acc = 0.0
					_dragged = false
					get_viewport().set_input_as_handled()
				elif not mb.pressed and _pressed != null:
					if not _dragged:
						_pressed.click()
					_pressed = null
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressed != null and _pressed.drag_px > 0.0:
		var mm := event as InputEventMouseMotion
		# Right or up turns clockwise / increases.
		_drag_acc += mm.relative.x - mm.relative.y
		var steps := int(_drag_acc / _pressed.drag_px)
		if steps != 0:
			_dragged = true
			_drag_acc -= steps * _pressed.drag_px
			for i in absi(steps):
				_pressed.scroll(signi(steps), mm.shift_pressed)
		get_viewport().set_input_as_handled()


# --- touch -------------------------------------------------------------------

func _touch(e: InputEvent) -> void:
	var idx: int = e.get(&"index")
	var pos: Vector2 = e.get(&"position")
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			var ctl: CockpitControl = _pick(pos) if enabled and camera != null else null
			_fingers[idx] = {"pos": pos, "start": pos, "ctl": ctl, "acc": 0.0, "dragged": false}
			if ctl != null:
				ctl.set_hover(true)
			_pinch_d = _look_spread()
		else:
			_touch_up(idx, pos, st.canceled)
		get_viewport().set_input_as_handled()
		return
	var f: Dictionary = _fingers.get(idx, {})
	if f.is_empty():
		return
	var rel: Vector2 = (e as InputEventScreenDrag).relative
	f["pos"] = pos
	if pos.distance_to(f["start"]) > TAP_SLOP:
		f["dragged"] = true
	var ctl := f["ctl"] as CockpitControl
	if ctl != null:
		if ctl.drag_px > 0.0:
			f["acc"] = float(f["acc"]) + rel.x - rel.y # right or up increases
			var step := maxf(ctl.drag_px, TOUCH_DRAG_PX)
			var steps := int(float(f["acc"]) / step)
			if steps != 0:
				f["acc"] = float(f["acc"]) - steps * step
				for i in absi(steps):
					ctl.scroll(signi(steps), false)
	elif rig != null:
		var look := _look_fingers()
		if look.size() >= 2:
			var d := _look_spread()
			if _pinch_d > 1.0 and d > 1.0:
				rig.zoom_by(_pinch_d / d)
			_pinch_d = d
			for i: int in look:
				_fingers[i]["dragged"] = true
		else:
			# The view follows the finger (drag right = look left).
			rig.look_by(-rel * TOUCH_LOOK_DEG_PER_PX)
	get_viewport().set_input_as_handled()


func _touch_up(idx: int, pos: Vector2, canceled: bool) -> void:
	var f: Dictionary = _fingers.get(idx, {})
	_fingers.erase(idx)
	_pinch_d = _look_spread()
	if f.is_empty():
		return
	var ctl := f["ctl"] as CockpitControl
	if ctl != null:
		if is_instance_valid(ctl):
			if not canceled and not bool(f["dragged"]):
				ctl.click()
			ctl.set_hover(false)
		return
	if canceled or bool(f["dragged"]) or not _fingers.is_empty() or rig == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < int(DOUBLE_TAP_S * 1000.0) and pos.distance_to(_last_tap_pos) < DOUBLE_TAP_PX:
		rig.reset_look()
		_last_tap_ms = -100000
	else:
		_last_tap_ms = now
		_last_tap_pos = pos


func _look_fingers() -> Array:
	var out := []
	for i: int in _fingers:
		if _fingers[i]["ctl"] == null:
			out.append(i)
	return out


## Distance between the first two look fingers (0 with fewer than two).
func _look_spread() -> float:
	var look := _look_fingers()
	if look.size() < 2:
		return 0.0
	return (_fingers[look[0]]["pos"] as Vector2).distance_to(_fingers[look[1]]["pos"])


## While a finger holds a control, show its tooltip above the finger.
func _touch_tooltip() -> void:
	if tooltip == null:
		return
	var held: CockpitControl = null
	var at := Vector2.ZERO
	for i: int in _fingers:
		var c: Variant = _fingers[i]["ctl"]
		if c != null and is_instance_valid(c):
			held = c
			at = _fingers[i]["pos"]
	tooltip.visible = held != null
	if held == null:
		return
	tooltip.text = held.tooltip_text()
	tooltip.reset_size()
	var vs := tooltip.get_viewport_rect().size
	tooltip.position = Vector2(
		clampf(at.x - tooltip.size.x * 0.5, 8.0, vs.x - tooltip.size.x - 8.0),
		clampf(at.y - tooltip.size.y - 90.0, 80.0, vs.y - tooltip.size.y - 8.0))
