extends RefCounted
## Widgets and style boxes for the flight-data display: a dark avionics-style
## panel with hairline rules, small-caps headings and monospaced values.

const Look := preload("res://scenes/controller/scope/scope_theme.gd")


static func box(bg: Color, border: Color = Color.TRANSPARENT, bw: int = 0, mh: float = 8.0, mv: float = 6.0,
		radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mh
	sb.content_margin_right = mh
	sb.content_margin_top = mv
	sb.content_margin_bottom = mv
	sb.anti_aliasing = false
	return sb


static func label(text: String, size: int, col: Color, font: Font = null, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override(&"font", font if font != null else Look.mono(500))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func heading(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = Look.sans(600)
	fv.spacing_glyph = 2
	var l := label(text.to_upper(), 12, Look.FDD_HEAD, fv)
	row.add_child(l)
	var rule := ColorRect.new()
	rule.color = Look.FDD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row


static func vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## Flat clickable row/button styled for the display.
static func flat_button(text: String, size: int, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override(&"font", Look.mono(600))
	b.add_theme_font_size_override(&"font_size", size)
	for s: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(s, col)
	b.add_theme_stylebox_override(&"normal", box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 6, 3))
	b.add_theme_stylebox_override(&"hover", box(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 0, 6, 3))
	b.add_theme_stylebox_override(&"pressed", box(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 6, 3))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	return b
