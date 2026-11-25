class_name PilotInteraction
extends Node
## Mouse operation of the cockpit: a ray from the camera through the cursor
## picks the nearest CockpitControl; hover highlights it and shows a small
## tooltip; the wheel turns knobs (Shift = big steps); left-drag turns them
## continuously; a click without drag pushes buttons and moves levers.

var camera: Camera3D
var controls: Array[CockpitControl] = []
var tooltip: Label
var enabled := true

var _hover: CockpitControl
var _pressed: CockpitControl
var _press_pos := Vector2.ZERO
var _drag_acc := 0.0
var _dragged := false


func _process(_delta: float) -> void:
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
