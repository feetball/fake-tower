extends PilotInstrumentPart
## Attitude indicator: sky/ground, pitch ladder, bank scale and pointer,
## aircraft symbol, ILS localizer and glideslope scales, radio altitude,
## MINIMUMS and GPWS PULL UP / TERRAIN messages. Clipped to its rect.

const PPD := 8.0 ## pixels per degree of pitch
const DOT_LOC := 62.0
const DOT_GS := 56.0

var da_ft := 712.0


func _init() -> void:
	super()
	clip_contents = true


func _draw() -> void:
	var c := size * 0.5 + Vector2(0.0, -10.0)
	var pitch := bus.pitch
	var bank := bus.bank
	draw_rect(Rect2(Vector2.ZERO, size), A.BG)
	# Horizon and ladder in the rotated frame.
	draw_set_transform(c, -deg_to_rad(bank), Vector2.ONE)
	var hy := pitch * PPD
	draw_rect(Rect2(-1200.0, hy - 2400.0, 2400.0, 2400.0), A.SKY)
	draw_rect(Rect2(-1200.0, hy, 2400.0, 2400.0), A.GROUND)
	draw_line(Vector2(-1200.0, hy), Vector2(1200.0, hy), A.WHITE, 3.0)
	_ladder(pitch)
	_bank_pointer()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_bank_scale(c)
	_aircraft_symbol(c)
	_ils_scales(c)
	_radio_alt(c)
	_alerts(c)


func _ladder(pitch: float) -> void:
	var p := -90.0
	while p <= 90.0:
		if absf(p) > 0.01:
			var y := (pitch - p) * PPD
			if absf(y) < 165.0:
				var major := is_equal_approx(fmod(absf(p), 10.0), 0.0)
				var mid := is_equal_approx(fmod(absf(p), 5.0), 0.0)
				var half := 80.0 if major else (45.0 if mid else 20.0)
				draw_line(Vector2(-half, y), Vector2(half, y), A.WHITE, 3.0)
				if major:
					var s := str(int(absf(p)))
					A.text(self, Vector2(-half - 30.0, y), s, 26, A.WHITE)
					A.text(self, Vector2(half + 30.0, y), s, 26, A.WHITE)
		p += 2.5


func _bank_pointer() -> void:
	# Sky pointer: rotates with the horizon, points at the bank scale.
	var r := 190.0
	var pts := PackedVector2Array([Vector2(0.0, -r + 2.0), Vector2(-13.0, -r + 24.0), Vector2(13.0, -r + 24.0)])
	draw_colored_polygon(pts, A.WHITE)
	if absf(bus.bank) > 35.0:
		draw_colored_polygon(pts, A.AMBER)


func _bank_scale(c: Vector2) -> void:
	var r := 190.0
	draw_arc(c, r, deg_to_rad(-90.0 - 60.0), deg_to_rad(-90.0 + 60.0), 48, A.WHITE, 3.0, true)
	for a: float in [-60.0, -45.0, -30.0, -20.0, -10.0, 10.0, 20.0, 30.0, 45.0, 60.0]:
		var ang := deg_to_rad(-90.0 + a)
		var long := absf(a) == 30.0 or absf(a) == 60.0
		var l := 26.0 if long else 14.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * r, c + d * (r + l), A.WHITE, 3.0)
	# Zero index: fixed yellow triangle pointing down.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -r - 2.0), c + Vector2(-13.0, -r - 24.0), c + Vector2(13.0, -r - 24.0)]), A.YELLOW)


func _aircraft_symbol(c: Vector2) -> void:
	var edge := A.YELLOW
	for s: float in [-1.0, 1.0]:
		var w := PackedVector2Array([
			c + Vector2(s * 150.0, -6.0), c + Vector2(s * 50.0, -6.0), c + Vector2(s * 50.0, 26.0),
			c + Vector2(s * 62.0, 26.0), c + Vector2(s * 62.0, 6.0), c + Vector2(s * 150.0, 6.0)])
		draw_colored_polygon(w, Color.BLACK)
		A.polyline_closed(self, w, edge, 3.5)
	var sq := Rect2(c - Vector2(7.0, 7.0), Vector2(14.0, 14.0))
	draw_rect(sq, Color.BLACK)
	draw_rect(sq, edge, false, 3.5)


func _ils_scales(c: Vector2) -> void:
	var loc: Variant = bus.own.get("loc_dev", null)
	var gs: Variant = bus.own.get("gs_dev", null)
	# Localizer: horizontal scale near the bottom.
	var ly := size.y - 40.0
	if loc != null:
		for k: int in [-2, -1, 1, 2]:
			draw_arc(Vector2(c.x + k * DOT_LOC, ly), 8.0, 0.0, TAU, 16, A.WHITE, 3.0)
		draw_line(Vector2(c.x, ly - 16.0), Vector2(c.x, ly + 16.0), A.YELLOW, 4.0)
		_diamond(Vector2(c.x + clampf(float(loc), -2.4, 2.4) * DOT_LOC, ly), absf(float(loc)) <= 2.3)
	# Glideslope: vertical scale on the right edge.
	var gx := size.x - 32.0
	if gs != null:
		for k: int in [-2, -1, 1, 2]:
			draw_arc(Vector2(gx, c.y + k * DOT_GS), 8.0, 0.0, TAU, 16, A.WHITE, 3.0)
		draw_line(Vector2(gx - 16.0, c.y), Vector2(gx + 16.0, c.y), A.YELLOW, 4.0)
		_diamond(Vector2(gx, c.y - clampf(float(gs), -2.4, 2.4) * DOT_GS), absf(float(gs)) <= 2.3, true)


func _diamond(p: Vector2, filled: bool, vertical: bool = false) -> void:
	var a := 18.0 if not vertical else 12.0
	var b := 12.0 if not vertical else 18.0
	var pts := PackedVector2Array([p + Vector2(0, -b), p + Vector2(a, 0), p + Vector2(0, b), p + Vector2(-a, 0)])
	if filled:
		draw_colored_polygon(pts, A.MAGENTA)
	else:
		A.polyline_closed(self, pts, A.MAGENTA, 3.0)


func _radio_alt(c: Vector2) -> void:
	if bus.rad_alt < 0.0:
		return
	var ra := bus.rad_alt
	var shown := int(round(ra / 10.0) * 10.0) if ra > 50.0 else int(round(ra))
	var col := A.AMBER if bus.ind_alt <= da_ft and not bus.own.get("on_ground", false) else A.WHITE
	var p := c + Vector2(0.0, 112.0)
	draw_rect(Rect2(p - Vector2(64.0, 26.0), Vector2(128.0, 52.0)), Color(0, 0, 0, 0.55))
	A.text(self, p, str(shown), 44, col)


func _alerts(c: Vector2) -> void:
	var airborne := not bool(bus.own.get("on_ground", false)) and String(bus.own.get("status", "")) == "flying"
	if airborne and bus.ind_alt <= da_ft + 4.0 and bus.rad_alt >= 0.0 and bus.rad_alt < 400.0:
		A.text(self, c + Vector2(0.0, -120.0), "MINIMUMS", 34, A.AMBER)
	if bus.has_warning("PULL UP"):
		if A.flash(0.7):
			var r := Rect2(c + Vector2(-125.0, -118.0), Vector2(250.0, 58.0))
			draw_rect(r, Color(0, 0, 0, 0.7))
			draw_rect(r, A.RED, false, 4.0)
			A.text(self, r.get_center(), "PULL UP", 46, A.RED)
	elif bus.has_warning("TERRAIN"):
		A.text(self, c + Vector2(0.0, -90.0), "TERRAIN", 40, A.AMBER)
