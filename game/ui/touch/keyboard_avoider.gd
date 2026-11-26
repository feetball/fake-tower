class_name TouchKeyboardAvoider
extends Node
## Keeps the focused text field visible above the on-screen keyboard on
## phones and tablets. When a LineEdit/TextEdit has focus and the virtual
## keyboard covers it, the canvas layer that holds the field (or the root
## canvas) is slid up just enough; it slides back when the keyboard closes or
## focus moves away. Godot opens the keyboard itself on focus
## (LineEdit.virtual_keyboard_enabled); this only fixes the overlap.
##
## Mobile browsers do not report the keyboard height, so there an estimate
## (KEYBOARD_GUESS of the screen height) is used while a field has focus.

const MARGIN := 24.0
const KEYBOARD_GUESS := 0.5
const SPEED := 14.0

var _shifted: Object = null ## CanvasLayer or Viewport currently moved
var _offset := 0.0
var _target := 0.0


func _process(delta: float) -> void:
	var vp := get_viewport()
	var focus := vp.gui_get_focus_owner()
	var field: Control = focus if (focus is LineEdit or focus is TextEdit) else null
	var holder: Object = null
	_target = 0.0
	if field != null and field.is_visible_in_tree():
		holder = _holder_of(field)
		var kb := _keyboard_top(vp)
		if kb > 0.0:
			var bottom := field.get_global_rect().end.y
			var need := bottom + MARGIN - kb
			_target = maxf(0.0, need)
	if holder != _shifted and _shifted != null:
		_apply(_shifted, 0.0)
		_offset = 0.0
		_shifted = null
	if holder != null:
		_shifted = holder
	if _shifted == null:
		return
	_offset = lerpf(_offset, _target, 1.0 - exp(-delta * SPEED))
	if absf(_offset - _target) < 0.5:
		_offset = _target
	_apply(_shifted, _offset)
	if _offset == 0.0 and _target == 0.0 and field == null:
		_shifted = null


## Top edge of the keyboard in canvas units, or -1 when no keyboard is up.
func _keyboard_top(vp: Viewport) -> float:
	var vis := vp.get_visible_rect().size
	var h_px := 0.0
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		h_px = float(DisplayServer.virtual_keyboard_get_height())
	if h_px > 0.0:
		var win_h := float(DisplayServer.window_get_size().y)
		if win_h <= 0.0:
			return -1.0
		return vis.y - h_px * vis.y / win_h
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return vis.y * (1.0 - KEYBOARD_GUESS)
	return -1.0


func _holder_of(c: Node) -> Object:
	var n := c.get_parent()
	while n != null:
		if n is CanvasLayer:
			return n
		if n is Viewport:
			return n
		n = n.get_parent()
	return get_viewport()


## Control rects are canvas-local (they do not include the layer offset or the
## canvas transform), so the shift never feeds back into the target.
func _apply(holder: Object, off: float) -> void:
	if holder is CanvasLayer:
		(holder as CanvasLayer).offset.y = -off
	elif holder is Viewport:
		var vp := holder as Viewport
		var xf := vp.canvas_transform
		xf.origin.y = -off
		vp.canvas_transform = xf
