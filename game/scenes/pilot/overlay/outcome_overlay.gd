class_name PilotOutcomeOverlay
extends Control
## The end of the flight, kept restrained. Landed: once the aircraft has
## slowed on the runway a quiet caption fades in at the bottom. Crash: an
## abrupt cut to black and, after a beat, a short caption naming what
## happened (terrain / collision / fuel / runway). Fuel exhaustion first lets
## the engines and displays run down for a moment.

const CAPTIONS := {
	"terrain": ["CONTROLLED FLIGHT INTO TERRAIN", "The aircraft struck the ground."],
	"collision": ["MID-AIR COLLISION", "Another aircraft was in the same airspace."],
	"fuel": ["FUEL EXHAUSTION", "Both engines flamed out."],
	"runway": ["RUNWAY ACCIDENT", "The approach was not stabilised at the threshold."],
}

var _black: ColorRect
var _title: Label
var _sub: Label
var _landed_shown := false
var _crashed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_title = _label(40, Color(0.92, 0.93, 0.94))
	_sub = _label(22, Color(0.6, 0.64, 0.68))
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0


func _label(size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var f := FontVariation.new()
	f.base_font = Avionics.sans(size_px > 30)
	f.spacing_glyph = 6 if size_px > 30 else 1
	l.add_theme_font_override(&"font", f)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func is_crashed() -> bool:
	return _crashed


## Abrupt cut (or, for fuel, a short run-down first) then the caption.
func show_crash(outcome: String, callsign: String, delay: float = 0.0) -> void:
	if _crashed:
		return
	_crashed = true
	var cap: Array = CAPTIONS.get(outcome, [UiText.outcome_text(outcome).to_upper(), ""])
	_title.text = String(cap[0])
	_sub.text = "%s\n%s" % [String(cap[1]), callsign]
	_title.offset_top = -40.0
	_title.offset_bottom = -40.0
	_sub.offset_top = 60.0
	_sub.offset_bottom = 60.0
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_property(_black, "color:a", 0.0, delay)
	tw.tween_property(_black, "color:a", 1.0, 0.04)
	tw.tween_interval(1.6)
	tw.tween_property(_title, "modulate:a", 1.0, 1.2)
	tw.tween_property(_sub, "modulate:a", 1.0, 1.0)


func show_landed(callsign: String) -> void:
	if _landed_shown or _crashed:
		return
	_landed_shown = true
	_title.text = "LANDED"
	_sub.text = "%s · runway 27 · %s" % [callsign, UiText.mmss(Session.round_time)]
	_title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_title.offset_bottom = -110.0
	_sub.offset_bottom = -70.0
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 0.25, 2.5)
	tw.parallel().tween_property(_title, "modulate:a", 0.85, 2.5)
	tw.parallel().tween_property(_sub, "modulate:a", 0.8, 3.0)


## Instant state for screenshots.
func force_crash(outcome: String, callsign: String) -> void:
	show_crash(outcome, callsign)
	_black.color.a = 1.0
