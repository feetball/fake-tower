extends PilotInstrumentPart
## Vertical speed indicator: non-linear scale to ±6000 fpm, needle from a
## virtual pivot right of the scale, digital value above 400 fpm.


func _scale_y(fpm: float) -> float:
	var a := absf(fpm)
	var h := size.y * 0.5 - 20.0
	var k: float
	if a <= 1000.0:
		k = a / 1000.0 * 0.5
	elif a <= 2000.0:
		k = 0.5 + (a - 1000.0) / 1000.0 * 0.25
	else:
		k = 0.75 + minf(a - 2000.0, 4000.0) / 4000.0 * 0.25
	return size.y * 0.5 - signf(fpm) * k * h


func _draw() -> void:
	var c := size.y * 0.5
	var bg := PackedVector2Array([Vector2(0.0, 20.0), Vector2(40.0, 0.0), Vector2(size.x, 0.0),
		Vector2(size.x, size.y), Vector2(40.0, size.y), Vector2(0.0, size.y - 20.0)])
	draw_colored_polygon(bg, Color(0.12, 0.13, 0.15))
	for v: float in [-6000.0, -2000.0, -1000.0, -500.0, 0.0, 500.0, 1000.0, 2000.0, 6000.0]:
		var y := _scale_y(v)
		var major := absf(v) in [1000.0, 2000.0, 6000.0] or v == 0.0
		draw_line(Vector2(8.0, y), Vector2(8.0 + (22.0 if major else 12.0), y), A.WHITE, 3.0)
		if absf(v) in [1000.0, 2000.0, 6000.0]:
			A.text(self, Vector2(46.0, y), str(int(absf(v) / 1000.0)), 26, A.WHITE)
	var vs := bus.vs
	var y := _scale_y(vs)
	var pivot := Vector2(size.x + 140.0, c)
	var tip := Vector2(10.0, y)
	var dir := (tip - pivot).normalized()
	draw_line(tip, tip - dir * 60.0, A.WHITE, 5.0)
	if absf(vs) >= 400.0:
		var s := str(int(round(absf(vs) / 50.0) * 50.0))
		A.text(self, Vector2(size.x * 0.5 + 4.0, 14.0 if vs > 0.0 else size.y - 14.0), s, 26, A.WHITE)
