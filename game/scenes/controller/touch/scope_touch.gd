extends RefCounted
## Touch gestures on the radar scope, per finger (InputEventScreenTouch/Drag
## by index, never the emulated mouse, so they work while another finger holds
## PTT). One finger is translated into the scope's own mouse handling
## (scope_input.pointer), so it behaves exactly like the mouse:
##   drag = pan, tap = select (empty scope = deselect, tap on the menu bar
##   toggles that button), double tap = reset the view, and with `measure` on a
##   drag draws the range/bearing line (Shift+drag / right-drag on desktop).
## Two fingers pinch-zoom about their midpoint and pan with it.

const ScopeInput := preload("res://scenes/controller/scope/scope_input.gd")

const DOUBLE_TAP_MS := 350
const DOUBLE_TAP_PX := 48.0 ## canvas units, scaled by ctx.ui_scale

var input: ScopeInput
## Measure mode (the touch stand-in for right-drag).
var measure := false

var _fingers: Dictionary = {} ## index -> Vector2 (scope pixels)
var _primary := -1
var _gesture := "" ## "", "one", "pinch"
var _pinch_d := 0.0
var _pinch_c := Vector2.ZERO
var _last_tap_ms := -100000
var _last_tap_pos := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _was_double := false


func _init(i: ScopeInput) -> void:
	input = i


## `pos` and the event's relative motion are in scope pixels.
func handle(e: InputEvent, pos: Vector2) -> void:
	var idx: int = e.get(&"index")
	if e is InputEventScreenTouch:
		if (e as InputEventScreenTouch).pressed:
			_down(idx, pos)
		else:
			_up(idx, pos, (e as InputEventScreenTouch).canceled)
	elif e is InputEventScreenDrag and _fingers.has(idx):
		_move(idx, pos)


func _down(idx: int, pos: Vector2) -> void:
	_fingers[idx] = pos
	if _fingers.size() == 1:
		_primary = idx
		_gesture = "one"
		_press_pos = pos
		var mb := _button(pos, true)
		mb.shift_pressed = measure
		mb.double_click = Time.get_ticks_msec() - _last_tap_ms < DOUBLE_TAP_MS \
			and pos.distance_to(_last_tap_pos) < DOUBLE_TAP_PX * input.ctx.ui_scale
		_was_double = mb.double_click
		input.pointer(mb, pos)
	elif _fingers.size() == 2:
		if _gesture == "one":
			input.mouse_left() # drop the one-finger pan / pending tap
		_gesture = "pinch"
		_pinch_d = _spread()
		_pinch_c = _centre()


func _move(idx: int, pos: Vector2) -> void:
	_fingers[idx] = pos
	if _gesture == "one" and idx == _primary:
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		input.pointer(mm, pos)
	elif _gesture == "pinch" and _fingers.size() >= 2:
		var d := _spread()
		var c := _centre()
		var xf := input.ctx.xform
		if _pinch_d > 1.0 and d > 1.0:
			xf.zoom_at(c, d / _pinch_d)
		xf.pan_pixels(c - _pinch_c)
		input.view_changed.call()
		_pinch_d = d
		_pinch_c = c


func _up(idx: int, pos: Vector2, canceled: bool) -> void:
	if not _fingers.has(idx):
		return
	_fingers.erase(idx)
	if _gesture == "one" and idx == _primary:
		if canceled:
			input.mouse_left()
		else:
			input.pointer(_button(pos, false), pos)
			# A tap arms the double tap; the release of a double tap does not.
			if _was_double or pos.distance_to(_press_pos) >= 12.0 * input.ctx.ui_scale:
				_last_tap_ms = -100000
			else:
				_last_tap_ms = Time.get_ticks_msec()
				_last_tap_pos = pos
		_gesture = ""
	elif _gesture == "pinch":
		_pinch_d = _spread()
		_pinch_c = _centre()
		if _fingers.is_empty():
			_gesture = ""
	if _fingers.is_empty():
		_primary = -1


func _button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	return mb


func _two() -> Array:
	var keys := _fingers.keys()
	return [_fingers[keys[0]], _fingers[keys[1]]] if keys.size() >= 2 else []


func _spread() -> float:
	var t := _two()
	return (t[0] as Vector2).distance_to(t[1]) if not t.is_empty() else 0.0


func _centre() -> Vector2:
	var t := _two()
	return ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5 if not t.is_empty() else Vector2.ZERO
