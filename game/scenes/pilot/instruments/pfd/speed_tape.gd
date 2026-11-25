extends PilotInstrumentPart
## Airspeed tape: scale, flap-minimum band (amber) with the low-speed barber
## pole below it, the 250 kt limit, selected-speed bug, 10 s trend vector and
## the current-speed readout box.

const PPK := 4.2 ## pixels per knot

var vmax := 250.0


func _init() -> void:
	super()
	clip_contents = true


func _y(kt: float, ias: float) -> float:
	return size.y * 0.5 - (kt - ias) * PPK


func _draw() -> void:
	var ias := bus.ias
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), A.TAPE)
	var lo := int(floor((ias - 70.0) / 5.0)) * 5
	for kt in range(maxi(lo, 30), int(ias + 70.0), 5):
		var y := _y(kt, ias)
		var major := kt % 10 == 0
		draw_line(Vector2(w - (22.0 if major else 12.0), y), Vector2(w, y), A.WHITE, 3.0)
		if kt % 20 == 0:
			A.text(self, Vector2(w - 30.0, y), str(kt), 32, A.WHITE, 1)
	# Minimum speed for the flap setting: amber strip, then the stall barber pole.
	var fmin := float(bus.flap_min())
	var strip_x := w - 10.0
	var y_min := _y(fmin, ias)
	var y_low := _y(fmin - 8.0, ias)
	draw_rect(Rect2(strip_x, y_min, 10.0, y_low - y_min), A.AMBER)
	_barber(strip_x, y_low, size.y + 10.0)
	# Maximum speed: barber pole from vmax upwards.
	_barber(strip_x, -10.0, _y(vmax, ias))
	# Selected speed bug.
	var sel := float(bus.sel("spd"))
	var by := clampf(_y(sel, ias), 0.0, size.y)
	draw_colored_polygon(A.bug_shape(w - 2.0, by, -26.0, 34.0, true), A.MAGENTA)
	# Trend vector.
	var tr := bus.ias_trend
	if absf(tr) > 2.0:
		var y0 := size.y * 0.5
		var y1 := _y(ias + tr, ias)
		var x := w - 38.0
		draw_line(Vector2(x, y0), Vector2(x, y1), A.GREEN, 3.0)
		var s := signf(y1 - y0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y1), Vector2(x - 8.0, y1 - s * 14.0), Vector2(x + 8.0, y1 - s * 14.0)]), A.GREEN)
	# Readout box.
	var cy := size.y * 0.5
	var box := PackedVector2Array([Vector2(4.0, cy - 34.0), Vector2(w - 40.0, cy - 34.0), Vector2(w - 40.0, cy - 12.0),
		Vector2(w - 24.0, cy), Vector2(w - 40.0, cy + 12.0), Vector2(w - 40.0, cy + 34.0), Vector2(4.0, cy + 34.0)])
	draw_colored_polygon(box, Color.BLACK)
	A.polyline_closed(self, box, A.WHITE, 3.0)
	var low := ias < fmin - 0.5
	A.text(self, Vector2(w - 48.0, cy), "%d" % int(round(ias)), 50, A.AMBER if low else A.WHITE, 1)


func _barber(x: float, y0: float, y1: float) -> void:
	if y1 <= y0:
		return
	draw_rect(Rect2(x, y0, 10.0, y1 - y0), Color.BLACK)
	var y := y0
	while y < y1:
		draw_rect(Rect2(x, y, 10.0, minf(10.0, y1 - y)), A.RED)
		y += 20.0
