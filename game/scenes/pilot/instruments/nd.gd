extends PilotInstrumentPart
## Navigation display in heading-up ROSE mode. Shows only what the radios
## give: the compass rose, selected heading bug, a bearing pointer with DME to
## the FTW station, and the ILS course with its deviation bar when the
## localizer is received. Deliberately no map, no traffic, no terrain.

const CENTRE := Vector2(500.0, 540.0)
const R := 360.0
const COURSE := 270.0
const DOT := 62.0


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1000.0, 1000.0), A.BG)
	var hdg := bus.hdg
	_header(hdg)
	_rose(hdg)
	_course(hdg)
	_bearing(hdg)
	_selected_heading(hdg)
	_aircraft()
	_footer()


func _rel(brg: float, hdg: float) -> float:
	# Screen angle (0 = up, clockwise) for a bearing seen from heading-up.
	return deg_to_rad(brg - hdg)


func _pt(angle: float, r: float) -> Vector2:
	return CENTRE + Vector2(sin(angle), -cos(angle)) * r


func _header(hdg: float) -> void:
	A.text(self, Vector2(30.0, 40.0), "GS", 28, A.WHITE, -1)
	A.text(self, Vector2(80.0, 40.0), str(int(round(own_f("gs")))), 34, A.WHITE, -1)
	A.text(self, Vector2(200.0, 40.0), "TAS", 28, A.WHITE, -1)
	A.text(self, Vector2(268.0, 40.0), str(int(round(own_f("gs")))), 34, A.WHITE, -1)
	var h := int(round(hdg)) % 360
	A.text(self, Vector2(500.0, 42.0), "HDG", 26, A.GREEN, 1)
	var r := Rect2(512.0, 18.0, 92.0, 50.0)
	draw_rect(r, A.WHITE, false, 3.0)
	A.text(self, r.get_center(), "%03d" % (360 if h == 0 else h), 36, A.WHITE)
	A.text(self, Vector2(620.0, 42.0), "MAG", 26, A.GREEN, -1)
	A.text(self, Vector2(970.0, 40.0), "ILS", 28, A.MAGENTA, 1)
	A.text(self, Vector2(970.0, 78.0), "IFTW 109.90", 26, A.WHITE, 1)
	A.text(self, Vector2(970.0, 112.0), "CRS %03d" % int(COURSE), 26, A.WHITE, 1)


func _rose(hdg: float) -> void:
	draw_arc(CENTRE, R, 0.0, TAU, 128, A.WHITE, 3.0, true)
	for d in range(0, 360, 5):
		var a := _rel(d, hdg)
		var long := d % 10 == 0
		draw_line(_pt(a, R), _pt(a, R - (30.0 if long else 16.0)), A.WHITE, 3.0)
		if d % 30 == 0:
			var lbl := str(d / 10)
			draw_set_transform(_pt(a, R - 58.0), a, Vector2.ONE)
			A.text(self, Vector2.ZERO, lbl, 38 if d % 90 == 0 else 32, A.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Inner half-range ring, dashed.
	var n := 48
	for i in n:
		if i % 2 == 0:
			draw_arc(CENTRE, R * 0.5, TAU * i / n, TAU * (i + 1) / n, 4, A.GREY, 2.0, true)
	# Lubber line at the top.
	draw_colored_polygon(PackedVector2Array([CENTRE + Vector2(-14, -R - 30), CENTRE + Vector2(14, -R - 30), CENTRE + Vector2(0, -R - 4)]), A.YELLOW)


func _course(hdg: float) -> void:
	var a := _rel(COURSE, hdg)
	var loc: Variant = bus.own.get("loc_dev", null)
	var col := A.MAGENTA
	var dir := Vector2(sin(a), -cos(a))
	var perp := Vector2(cos(a), sin(a))
	# Course arrow head and tail through the rose.
	var head := CENTRE + dir * (R - 40.0)
	var tail := CENTRE - dir * (R - 40.0)
	draw_line(head, CENTRE + dir * 150.0, col, 5.0)
	draw_line(tail, CENTRE - dir * 150.0, col, 5.0)
	draw_colored_polygon(PackedVector2Array([head + dir * 24.0, head - perp * 16.0, head + perp * 16.0]), col)
	if loc == null:
		A.text(self, CENTRE + Vector2(0.0, 220.0), "LOC", 30, A.AMBER)
		return
	for k: int in [-2, -1, 1, 2]:
		draw_arc(CENTRE + perp * k * DOT, 9.0, 0.0, TAU, 16, A.WHITE, 3.0)
	var off := perp * clampf(float(loc), -2.4, 2.4) * DOT
	draw_line(CENTRE + dir * 140.0 + off, CENTRE - dir * 140.0 + off, col, 6.0)


func _bearing(hdg: float) -> void:
	var b: Variant = bus.own.get("bearing_to_station", null)
	if b == null:
		return
	var a := _rel(float(b), hdg)
	var dir := Vector2(sin(a), -cos(a))
	var perp := Vector2(cos(a), sin(a))
	var col := A.CYAN
	var tip := CENTRE + dir * (R + 6.0)
	var tail := CENTRE - dir * (R + 6.0)
	# Double-line pointer: head outside the rose, tail on the other side.
	for s: float in [-1.0, 1.0]:
		draw_line(CENTRE + dir * (R - 70.0) + perp * s * 7.0, tip - dir * 30.0 + perp * s * 7.0, col, 3.0)
		draw_line(CENTRE - dir * (R - 70.0) + perp * s * 7.0, tail + perp * s * 7.0, col, 3.0)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 34.0 - perp * 16.0, tip - dir * 34.0 + perp * 16.0]), col)
	draw_line(tail - perp * 14.0, tail + perp * 14.0, col, 3.0)
	A.text(self, Vector2(40.0, 900.0), "FTW", 32, col, -1)
	A.text(self, Vector2(40.0, 942.0), "DME %.1f" % own_f("dme"), 32, A.WHITE, -1)


func _selected_heading(hdg: float) -> void:
	var sel := float(bus.sel("hdg"))
	var a := _rel(sel, hdg)
	var p := _pt(a, R)
	draw_set_transform(p, a, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-18, 0), Vector2(-18, -22), Vector2(-6, -22), Vector2(0, -6),
		Vector2(6, -22), Vector2(18, -22), Vector2(18, 0)]), A.MAGENTA)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	A.text(self, Vector2(970.0, 942.0), "HDG %03d" % int(sel), 32, A.CYAN, 1)


func _aircraft() -> void:
	var c := CENTRE
	draw_line(c + Vector2(0, -36), c + Vector2(0, 50), A.YELLOW, 6.0)
	draw_line(c + Vector2(-34, 0), c + Vector2(34, 0), A.YELLOW, 6.0)
	draw_line(c + Vector2(-14, 40), c + Vector2(14, 40), A.YELLOW, 5.0)


func _footer() -> void:
	A.text(self, Vector2(500.0, 965.0), "ROSE  NAV RAD", 24, A.GREY)
