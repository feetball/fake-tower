class_name UiTheme
extends RefCounted
## Shared look for the shell: dark smoked glass, hairline borders, a phosphor
## green accent, Inter-like sans and a monospace for avionics-style text.
## Fonts are SystemFonts with fallbacks; Inter and JetBrains Mono are bundled for
## systems that lack them (BundledFonts).
##
## Theme type variations (set Control.theme_type_variation):
##   Label:  Title, Tagline, Heading, Dim, Small, Mono, MonoSmall, MonoLarge
##   Button: MenuItem, Primary, Danger, Ghost
##   PanelContainer: Glass, Inset, Strip

const TEXT := Color(0.87, 0.89, 0.9)
const DIM := Color(0.58, 0.62, 0.65)
const FAINT := Color(0.38, 0.41, 0.44)
const ACCENT := Color(0.56, 0.93, 0.76)
const AMBER := Color(1.0, 0.74, 0.34)
const RED := Color(1.0, 0.4, 0.34)
const BLUE := Color(0.55, 0.78, 1.0)
const GLASS := Color(0.022, 0.027, 0.034, 0.84)
const LINE := Color(1.0, 1.0, 1.0, 0.1)

const SANS_NAMES: PackedStringArray = ["Inter", "Segoe UI", "Helvetica Neue", "SF Pro Text",
	"Noto Sans", "Roboto", "Ubuntu", "DejaVu Sans", "Liberation Sans", "Arial", "sans-serif"]
const DISPLAY_NAMES: PackedStringArray = ["Inter Display", "Inter", "Segoe UI Variable Display",
	"Segoe UI", "Helvetica Neue", "SF Pro Display", "Noto Sans", "DejaVu Sans", "Arial", "sans-serif"]
const MONO_NAMES: PackedStringArray = ["JetBrains Mono", "SF Mono", "Cascadia Mono", "Consolas",
	"Menlo", "Ubuntu Mono", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"]

static var _theme: Theme
static var _fonts: Dictionary = {}


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func sans(weight: int = 400) -> Font:
	return _system_font("sans", SANS_NAMES, weight)


static func mono(weight: int = 400) -> Font:
	return _system_font("mono", MONO_NAMES, weight)


static func display(weight: int = 200, spacing: int = 0) -> Font:
	var key := "display-%d-%d" % [weight, spacing]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = _system_font("display", DISPLAY_NAMES, weight)
		fv.spacing_glyph = spacing
		_fonts[key] = fv
	return _fonts[key]


static func spaced(base: Font, spacing: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing
	return fv


static func _system_font(kind: String, names: PackedStringArray, weight: int) -> Font:
	var key := "%s-%d" % [kind, weight]
	if not _fonts.has(key):
		var f := SystemFont.new()
		f.font_names = names
		f.font_weight = weight
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		f.allow_system_fallback = true
		_fonts[key] = BundledFonts.or_system(f)
	return _fonts[key]


static func flat(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0,
		radius: int = 2, margin_h: float = 16.0, margin_v: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = true
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = sans(400)
	t.default_font_size = 20

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 3)
	_label_var(t, "Title", display(200, 22), 104, Color(0.95, 0.96, 0.96))
	_label_var(t, "Tagline", sans(300), 24, Color(0.78, 0.8, 0.82))
	_label_var(t, "Heading", spaced(sans(600), 3), 14, DIM)
	_label_var(t, "Dim", sans(400), 18, DIM)
	_label_var(t, "Small", sans(400), 17, DIM)
	_label_var(t, "Mono", mono(400), 18, TEXT)
	_label_var(t, "MonoSmall", mono(400), 15, DIM)
	_label_var(t, "MonoLarge", mono(500), 30, TEXT)
	_label_var(t, "Big", sans(300), 30, TEXT)

	# Buttons
	var btn_font := spaced(sans(500), 1)
	t.set_font("font", "Button", btn_font)
	t.set_font_size("font_size", "Button", 19)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_stylebox("normal", "Button", flat(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.16), 1, 2, 20, 11))
	t.set_stylebox("hover", "Button", flat(Color(1, 1, 1, 0.08), Color(ACCENT, 0.6), 1, 2, 20, 11))
	t.set_stylebox("pressed", "Button", flat(Color(ACCENT, 0.16), ACCENT, 1, 2, 20, 11))
	t.set_stylebox("disabled", "Button", flat(Color(1, 1, 1, 0.015), Color(1, 1, 1, 0.07), 1, 2, 20, 11))
	t.set_stylebox("focus", "Button", _focus_box())

	t.set_type_variation("Primary", "Button")
	t.set_color("font_color", "Primary", ACCENT)
	t.set_color("font_hover_color", "Primary", Color(0.85, 1.0, 0.93))
	t.set_stylebox("normal", "Primary", flat(Color(ACCENT, 0.12), Color(ACCENT, 0.75), 1, 2, 26, 13))
	t.set_stylebox("hover", "Primary", flat(Color(ACCENT, 0.22), ACCENT, 1, 2, 26, 13))
	t.set_stylebox("pressed", "Primary", flat(Color(ACCENT, 0.32), ACCENT, 1, 2, 26, 13))
	t.set_stylebox("disabled", "Primary", flat(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.08), 1, 2, 26, 13))

	t.set_type_variation("Danger", "Button")
	t.set_color("font_color", "Danger", Color(1.0, 0.7, 0.66))
	t.set_stylebox("hover", "Danger", flat(Color(RED, 0.14), Color(RED, 0.7), 1, 2, 20, 11))

	t.set_type_variation("Ghost", "Button")
	t.set_color("font_color", "Ghost", DIM)
	var ghost := flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 10, 6)
	t.set_stylebox("normal", "Ghost", ghost)
	t.set_stylebox("hover", "Ghost", flat(Color(1, 1, 1, 0.06), Color.TRANSPARENT, 0, 2, 10, 6))
	t.set_stylebox("pressed", "Ghost", flat(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0, 2, 10, 6))
	t.set_stylebox("disabled", "Ghost", ghost)

	# Main-menu items: text only, an accent rule on the left when hovered/focused.
	t.set_type_variation("MenuItem", "Button")
	t.set_font("font", "MenuItem", spaced(sans(300), 2))
	t.set_font_size("font_size", "MenuItem", 27)
	t.set_color("font_color", "MenuItem", Color(0.8, 0.83, 0.85))
	t.set_color("font_hover_color", "MenuItem", Color.WHITE)
	t.set_color("font_focus_color", "MenuItem", Color.WHITE)
	t.set_color("font_pressed_color", "MenuItem", ACCENT)
	t.set_constant("align_to_largest_stylebox", "MenuItem", 1)
	var mi_normal := flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 22, 9)
	mi_normal.border_width_left = 2
	var mi_hover := flat(Color(1, 1, 1, 0.045), ACCENT, 0, 0, 22, 9)
	mi_hover.border_width_left = 2
	t.set_stylebox("normal", "MenuItem", mi_normal)
	t.set_stylebox("hover", "MenuItem", mi_hover)
	t.set_stylebox("pressed", "MenuItem", mi_hover)
	t.set_stylebox("focus", "MenuItem", mi_hover)
	t.set_stylebox("disabled", "MenuItem", mi_normal)

	# Line edits
	t.set_font("font", "LineEdit", sans(400))
	t.set_font_size("font_size", "LineEdit", 21)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.3))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.3))
	var le := flat(Color(0, 0, 0, 0.38), Color(1, 1, 1, 0.16), 1, 2, 14, 10)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", flat(Color.TRANSPARENT, Color(ACCENT, 0.85), 1, 2, 14, 10))
	t.set_stylebox("read_only", "LineEdit", flat(Color(0, 0, 0, 0.2), Color(1, 1, 1, 0.08), 1, 2, 14, 10))

	# Panels
	t.set_stylebox("panel", "PanelContainer", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0, 0))
	t.set_type_variation("Glass", "PanelContainer")
	var glass := flat(GLASS, LINE, 1, 3, 34, 30)
	glass.shadow_color = Color(0, 0, 0, 0.35)
	glass.shadow_size = 24
	t.set_stylebox("panel", "Glass", glass)
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", flat(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 1, 2, 16, 12))
	t.set_type_variation("Strip", "PanelContainer")
	var strip := flat(Color(0.015, 0.018, 0.022, 0.9), Color(1, 1, 1, 0.09), 0, 0, 18, 8)
	strip.border_width_bottom = 1
	t.set_stylebox("panel", "Strip", strip)
	t.set_stylebox("panel", "Panel", flat(GLASS, LINE, 1, 3))

	# Sliders and toggles
	t.set_stylebox("slider", "HSlider", flat(Color(1, 1, 1, 0.14), Color.TRANSPARENT, 0, 2, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", flat(Color(ACCENT, 0.8), Color.TRANSPARENT, 0, 2, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT, Color.TRANSPARENT, 0, 2, 0, 2))
	t.set_icon("grabber", "HSlider", _dot(18, Color(0.92, 0.95, 0.94)))
	t.set_icon("grabber_highlight", "HSlider", _dot(18, Color.WHITE))
	t.set_stylebox("focus", "HSlider", _focus_box())
	t.set_font("font", "CheckButton", sans(400))
	t.set_font_size("font_size", "CheckButton", 19)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	t.set_color("font_focus_color", "CheckButton", Color.WHITE)
	t.set_icon("checked", "CheckButton", _switch(true))
	t.set_icon("unchecked", "CheckButton", _switch(false))
	t.set_icon("checked_disabled", "CheckButton", _switch(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch(false))
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(s, "CheckButton", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 0, 6))
	t.set_stylebox("focus", "CheckButton", _focus_box())

	# Scrollbars: hairline
	t.set_stylebox("scroll", "VScrollBar", flat(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0, 2, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(1, 1, 1, 0.18), Color.TRANSPARENT, 0, 2, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(1, 1, 1, 0.3), Color.TRANSPARENT, 0, 2, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(Color(ACCENT, 0.5), Color.TRANSPARENT, 0, 2, 3, 0))

	t.set_stylebox("panel", "TooltipPanel", flat(Color(0.02, 0.025, 0.03, 0.95), LINE, 1, 2, 10, 6))
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("separator", "HSeparator", _hairline())
	t.set_constant("separation", "HSeparator", 1)
	return t


static func _label_var(t: Theme, n: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(n, "Label")
	t.set_font("font", n, font)
	t.set_font_size("font_size", n, size)
	t.set_color("font_color", n, color)


static func _focus_box() -> StyleBoxFlat:
	var sb := flat(Color.TRANSPARENT, Color(ACCENT, 0.7), 1, 2, 0, 0)
	sb.draw_center = false
	sb.set_expand_margin_all(2)
	return sb


static func _hairline() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(1, 1, 1, 0.09)
	l.thickness = 1
	return l


static func _dot(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


## On/off switch icon: a rounded track with a knob, drawn with 2x supersampling.
static func _switch(on: bool) -> ImageTexture:
	var w := 46
	var h := 24
	var ss := 2
	var img := Image.create(w * ss, h * ss, false, Image.FORMAT_RGBA8)
	var track := Color(ACCENT, 0.35) if on else Color(1, 1, 1, 0.12)
	var border := Color(ACCENT, 0.9) if on else Color(1, 1, 1, 0.3)
	var knob := Color(0.92, 1.0, 0.96) if on else Color(0.7, 0.73, 0.75)
	var r := h * ss * 0.5
	var knob_c := Vector2((w * ss - r) if on else r, r)
	for y in h * ss:
		for x in w * ss:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, w * ss - r)
			var d := p.distance_to(Vector2(cx, r))
			var c := Color(0, 0, 0, 0)
			if d <= r:
				c = border if d > r - 2.0 * ss else track
			if p.distance_to(knob_c) <= r - 4.0 * ss:
				c = knob
			img.set_pixel(x, y, c)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)
