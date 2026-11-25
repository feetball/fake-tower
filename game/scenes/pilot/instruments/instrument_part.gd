class_name PilotInstrumentPart
extends Control
## Base for everything drawn on a display: holds the data bus, ignores the
## mouse, and redraws itself and its children when the display unit asks.

const A := preload("res://scenes/pilot/instruments/avionics.gd")

var bus: PilotAvionicsBus


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Place at (x, y) with size (w, h) in the parent's logical space.
func place(x: float, y: float, w: float, h: float) -> PilotInstrumentPart:
	position = Vector2(x, y)
	size = Vector2(w, h)
	return self


func add_part(p: PilotInstrumentPart) -> PilotInstrumentPart:
	p.bus = bus
	add_child(p)
	return p


func refresh() -> void:
	queue_redraw()
	for c in get_children():
		if c is PilotInstrumentPart:
			(c as PilotInstrumentPart).bus = bus
			(c as PilotInstrumentPart).refresh()


func own_f(key: String, fallback: float = 0.0) -> float:
	var v: Variant = bus.own.get(key, null)
	return fallback if v == null else float(v)
