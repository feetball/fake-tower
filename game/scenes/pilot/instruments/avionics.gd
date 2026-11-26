class_name Avionics
extends RefCounted
## Shared look of the glass displays: colour coding, fonts and small drawing
## helpers for CanvasItem instruments drawn in a 1000 x 1000 logical space.
## Colours: magenta = selected/commanded (bugs, needles), green = engaged,
## white = armed/scales, amber = caution, red = warning, cyan = selected values.

const BG := Color(0.012, 0.014, 0.02)
const WHITE := Color(0.94, 0.95, 0.96)
const GREY := Color(0.42, 0.45, 0.5)
const DARK := Color(0.16, 0.17, 0.2)
const GREEN := Color(0.26, 0.95, 0.42)
const MAGENTA := Color(1.0, 0.33, 0.9)
const CYAN := Color(0.25, 0.9, 1.0)
const AMBER := Color(1.0, 0.7, 0.1)
const RED := Color(1.0, 0.18, 0.15)
const YELLOW := Color(1.0, 0.9, 0.2)
const SKY := Color(0.11, 0.42, 0.78)
const GROUND := Color(0.5, 0.3, 0.13)
const TAPE := Color(0.24, 0.26, 0.3)

static var _fonts: Dictionary = {}


## Monospaced display font (B612-like look from system mono fonts).
static func font(bold: bool = true) -> Font:
	var key := "b" if bold else "r"
	if not _fonts.has(key):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["B612 Mono", "JetBrains Mono", "DejaVu Sans Mono", "Consolas", "monospace"])
		f.font_weight = 700 if bold else 500
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = true
		_fonts[key] = BundledFonts.or_system(f)
	return _fonts[key]


static func sans(bold: bool = true) -> Font:
	var key := "s" if bold else "sr"
	if not _fonts.has(key):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Inter", "DejaVu Sans", "Arial", "sans-serif"])
		f.font_weight = 650 if bold else 450
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.generate_mipmaps = true
		_fonts[key] = BundledFonts.or_system(f)
	return _fonts[key]


## Draw text with its anchor at `pos`: align -1 left, 0 centre, 1 right;
## vertically centred on pos.y.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align: int = 0, f: Font = null) -> void:
	if f == null:
		f = font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == 0:
		x -= w * 0.5
	elif align > 0:
		x -= w
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	ci.draw_string(f, Vector2(x, pos.y + (asc - desc) * 0.5 - size * 0.04), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_width(s: String, size: int, f: Font = null) -> float:
	if f == null:
		f = font()
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func rect_outline(ci: CanvasItem, r: Rect2, col: Color, w: float = 3.0) -> void:
	ci.draw_rect(r, col, false, w)


static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(pts, col)


static func polyline_closed(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	var p := pts.duplicate()
	p.append(pts[0])
	ci.draw_polyline(p, col, w, true)


## Speed/altitude bug shape: a notched box pointing at x0, height h.
static func bug_shape(x0: float, y: float, w: float, h: float, facing_right: bool) -> PackedVector2Array:
	var s := 1.0 if facing_right else -1.0
	return PackedVector2Array([
		Vector2(x0, y - h * 0.5), Vector2(x0 + s * w, y - h * 0.5), Vector2(x0 + s * w, y + h * 0.5),
		Vector2(x0, y + h * 0.5), Vector2(x0, y + h * 0.2), Vector2(x0 + s * w * 0.4, y),
		Vector2(x0, y - h * 0.2)])


static func flash(period: float = 0.8) -> bool:
	return fmod(Time.get_ticks_msec() / 1000.0, period) < period * 0.6
