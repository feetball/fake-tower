extends RefCounted
## Small CanvasItem drawing helpers: aligned text, dashed polylines and circles.

## Draws `s` with its box aligned at `pos`: hx/vy are -1 (left/top), 0 (centre),
## 1 (right/bottom). Returns the text's bounding rect.
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color,
		hx: int = -1, vy: int = -1, outline: float = 0.0, outline_col: Color = Color.BLACK) -> Rect2:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := font.get_height(size)
	var x := pos.x - (0.0 if hx < 0 else (w * 0.5 if hx == 0 else w))
	var y := pos.y - (0.0 if vy < 0 else (h * 0.5 if vy == 0 else h))
	var base := Vector2(round(x), round(y + font.get_ascent(size)))
	if outline >= 1.0:
		ci.draw_string_outline(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(round(outline)), outline_col)
	ci.draw_string(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return Rect2(x, y, w, h)


static func text_width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Dashed polyline with the dash pattern continuing across vertices, drawn
## as one multiline command.
static func dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float,
		dash: float, gap: float) -> void:
	var segs := PackedVector2Array()
	var on := true
	var left := dash
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 0.0001)
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			if on:
				segs.append(a + dir * t)
				segs.append(a + dir * (t + step))
			t += step
			left -= step
			if left <= 0.0001:
				on = not on
				left = dash if on else gap
	if not segs.is_empty():
		ci.draw_multiline(segs, col, width, true)


static func circle_points(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, width: float,
		dash: float, gap: float) -> void:
	var n := clampi(int(r * TAU / maxf(dash + gap, 1.0)) * 2, 24, 720)
	dashed_polyline(ci, circle_points(c, r, n), col, width, dash, gap)


static func circle_outline(ci: CanvasItem, c: Vector2, r: float, col: Color, width: float) -> void:
	var n := clampi(int(r * 0.6), 32, 256)
	ci.draw_arc(c, r, 0.0, TAU, n, col, width, true)


## Rough visibility test so off-screen map items are skipped.
static func near_rect(r: Rect2, p: Vector2, margin: float) -> bool:
	return r.grow(margin).has_point(p)
