class_name CockpitControl
extends Node3D
## A mouse-operable cockpit control (knob, button, lever) picked by the
## view's ray test against its box (no physics needed). Behaviour comes from callables so one class serves all:
##   on_scroll(dir: int, big: bool)   wheel over it (or drag steps)
##   on_click()                        left click
##   tooltip() -> String               hover text
## Hovering highlights the visuals with a soft rim.

const HIGHLIGHT_SHADER: Shader = preload("res://shaders/pilot_highlight.gdshader")

static var _highlight: ShaderMaterial

var on_scroll: Callable
var on_click: Callable
var tooltip: Callable
## Pixels of horizontal/vertical mouse drag per scroll step (0 = not draggable).
var drag_px := 14.0
var visuals: Array[GeometryInstance3D] = []
var extents := Vector3(0.04, 0.04, 0.04)


## Build with a box-shaped pick volume of `size` (full size, metres).
func setup(size: Vector3) -> CockpitControl:
	extents = size
	return self


## Distance along the ray to this control's box, or -1 when missed.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	var h := extents * 0.5
	var t0 := -INF
	var t1 := INF
	for a in 3:
		if absf(d[a]) < 1e-9:
			if absf(o[a]) > h[a]:
				return -1.0
			continue
		var ta := (-h[a] - o[a]) / d[a]
		var tb := (h[a] - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 < maxf(t0, 0.0):
		return -1.0
	# Scale back to world distance (the basis may be scaled).
	return (global_transform * (o + d * maxf(t0, 0.0))).distance_to(origin)


func set_hover(on: bool) -> void:
	if _highlight == null:
		_highlight = ShaderMaterial.new()
		_highlight.shader = HIGHLIGHT_SHADER
	for v in visuals:
		if is_instance_valid(v):
			v.material_overlay = _highlight if on else null


func tooltip_text() -> String:
	return String(tooltip.call()) if tooltip.is_valid() else ""


func scroll(dir: int, big: bool) -> void:
	if on_scroll.is_valid():
		on_scroll.call(dir, big)


func click() -> void:
	if on_click.is_valid():
		on_click.call()
