class_name PilotViewHint
extends Label
## A subtle key reminder at the bottom left: shown at the start and briefly
## after every view change, then fades away.

const TEXT := "1 PANEL   2 OUTSIDE   3 PEDESTAL   ·   hold RMB to look   ·   I ATIS   P PLATE   ·   scroll / drag knobs"
const TOUCH_TEXT := "drag to look   ·   pinch to zoom   ·   double-tap to re-centre   ·   tap or drag cockpit controls"

var _tween: Tween


func _ready() -> void:
	text = TEXT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_override(&"font", Avionics.sans(false))
	add_theme_font_size_override(&"font_size", 17)
	add_theme_color_override(&"font_color", Color(0.75, 0.8, 0.85, 0.75))
	add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override(&"shadow_offset_x", 1)
	add_theme_constant_override(&"shadow_offset_y", 1)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 24.0
	offset_top = -44.0
	offset_bottom = -18.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	flash(9.0)


func flash(hold: float = 3.0) -> void:
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(hold)
	_tween.tween_property(self, "modulate:a", 0.0, 1.5)
