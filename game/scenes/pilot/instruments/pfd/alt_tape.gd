extends PilotInstrumentPart
## Altitude tape: scale, selected-altitude bug, baro minimums (DA) marker,
## ground band from the radio altimeter, and the drum-style readout.

const PPF := 0.48 ## pixels per foot

var da_ft := 712.0


func _init() -> void:
	super()
	clip_contents = true


func _y(ft: float, alt: float) -> float:
	return size.y * 0.5 - (ft - alt) * PPF


func _draw() -> void:
	var alt := bus.ind_alt
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), A.TAPE)
	var lo := int(floor((alt - 600.0) / 100.0)) * 100
	for ft in range(lo, int(alt + 600.0), 100):
		var y := _y(ft, alt)
		draw_line(Vector2(0.0, y), Vector2(18.0, y), A.WHITE, 3.0)
		if ft % 200 == 0:
			var s := "%d" % ft if ft >= 0 else "-%d" % absi(ft)
			A.text(self, Vector2(26.0, y), s, 28, A.WHITE, -1)
			if ft % 1000 == 0:
				draw_line(Vector2(22.0, y - 18.0), Vector2(w, y - 18.0), A.WHITE, 2.0)
				draw_line(Vector2(22.0, y + 18.0), Vector2(w, y + 18.0), A.WHITE, 2.0)
	# Ground: the radio altimeter puts the terrain on the tape.
	if bus.rad_alt >= 0.0:
		var gy := _y(alt - bus.rad_alt, alt)
		if gy < size.y:
			draw_rect(Rect2(0.0, gy, w, size.y - gy + 10.0), Color(0.35, 0.2, 0.06))
			var x := -size.y
			while x < w:
				draw_line(Vector2(x, size.y + 10.0), Vector2(x + 40.0, gy), A.AMBER, 2.0)
				x += 22.0
			draw_line(Vector2(0.0, gy), Vector2(w, gy), A.AMBER, 4.0)
	# Baro minimums marker.
	var dy := _y(da_ft, alt)
	if dy > -20.0 and dy < size.y + 20.0:
		var col := A.AMBER if alt <= da_ft else A.GREEN
		draw_line(Vector2(0.0, dy), Vector2(w * 0.55, dy), col, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(0.0, dy), Vector2(-1.0, dy - 1.0), Vector2(16.0, dy - 14.0), Vector2(16.0, dy + 14.0)]), col)
	# Selected altitude bug (left edge).
	var sel := float(bus.sel("alt"))
	var by := clampf(_y(sel, alt), 0.0, size.y)
	draw_colored_polygon(A.bug_shape(2.0, by, 26.0, 40.0, true), A.MAGENTA)
	_readout(alt)


func _readout(alt: float) -> void:
	var cy := size.y * 0.5
	var w := size.x
	var box := PackedVector2Array([Vector2(16.0, cy - 12.0), Vector2(30.0, cy - 38.0), Vector2(w - 2.0, cy - 38.0),
		Vector2(w - 2.0, cy + 38.0), Vector2(30.0, cy + 38.0), Vector2(16.0, cy + 12.0)])
	draw_colored_polygon(box, Color.BLACK)
	A.polyline_closed(self, box, A.WHITE, 3.0)
	var a := int(round(alt))
	var neg := a < 0
	a = absi(a)
	var hundreds := a / 100
	var twenties := int(round((a % 100) / 20.0)) * 20
	if twenties == 100:
		twenties = 0
		hundreds += 1
	var big := ("-" if neg else "") + str(hundreds)
	A.text(self, Vector2(w - 56.0, cy), big, 46, A.WHITE, 1)
	A.text(self, Vector2(w - 8.0, cy + 2.0), "%02d" % twenties, 32, A.WHITE, 1)
