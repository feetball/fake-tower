extends PilotInstrumentPart
## Engine and systems display: N1 and EGT dials for both engines, fuel
## remaining in minutes (amber < 10, red < 5), landing gear (three greens,
## red in transit, blank when up), flap position, and a memo / alert area
## with the landing memo below 2000 ft.

const N1_START := 150.0 ## dial start angle, deg (0 = right, clockwise)
const N1_SWEEP := 225.0


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1000.0, 1000.0), A.BG)
	for i in 2:
		var cx := 175.0 + i * 300.0
		_dial(Vector2(cx, 190.0), 118.0, bus.n1[i] / 110.0, "%.1f" % bus.n1[i], 0.98, true)
		var egt := _egt(bus.n1[i])
		_dial(Vector2(cx, 440.0), 82.0, egt / 1000.0, str(int(egt)), 0.92, false)
	A.text(self, Vector2(325.0, 190.0), "N1", 32, A.CYAN)
	A.text(self, Vector2(325.0, 222.0), "%", 26, A.CYAN)
	A.text(self, Vector2(325.0, 440.0), "EGT", 30, A.CYAN)
	A.text(self, Vector2(325.0, 470.0), "°C", 24, A.CYAN)
	A.text(self, Vector2(325.0, 588.0), "FF", 30, A.CYAN)
	for i in 2:
		var ff := bus.n1[i] * 26.0 if bus.engines_running else 0.0
		A.text(self, Vector2(175.0 + i * 300.0, 588.0), str(int(round(ff / 10.0) * 10.0)), 34, A.GREEN)
	draw_line(Vector2(650.0, 40.0), Vector2(650.0, 640.0), A.DARK, 3.0)
	_fuel(Vector2(820.0, 70.0))
	_gear(Vector2(820.0, 270.0))
	_flaps(Vector2(820.0, 520.0))
	draw_line(Vector2(30.0, 660.0), Vector2(970.0, 660.0), A.DARK, 3.0)
	_memo(Vector2(50.0, 700.0))


func _egt(n1: float) -> float:
	return 0.0 if n1 < 5.0 else 330.0 + n1 * 5.6


func _dial(c: Vector2, r: float, frac: float, value: String, redline: float, big: bool) -> void:
	var a0 := deg_to_rad(N1_START)
	var a1 := deg_to_rad(N1_START + N1_SWEEP)
	draw_arc(c, r, a0, a1, 64, A.WHITE, 4.0, true)
	var red := a0 + (a1 - a0) * redline
	draw_arc(c, r, red, a1, 16, A.RED, 8.0, true)
	for k in 11:
		var a := a0 + (a1 - a0) * k / 10.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r, c + d * (r - (16.0 if k % 2 == 0 else 9.0)), A.WHITE, 3.0)
	var f := clampf(frac, 0.0, 1.05)
	var an := a0 + (a1 - a0) * f
	# Filled sector shows the current value, as on most engine displays.
	var pts := PackedVector2Array([c])
	var steps := 24
	for k in steps + 1:
		var a := a0 + (an - a0) * k / steps
		pts.append(c + Vector2(cos(a), sin(a)) * (r - 4.0))
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(0.18, 0.2, 0.24))
	draw_line(c, c + Vector2(cos(an), sin(an)) * (r - 2.0), A.WHITE, 5.0)
	var box := Rect2(c + Vector2(6.0, -r * 0.62), Vector2(r * 0.95, r * 0.42 if big else r * 0.5))
	draw_rect(box, Color.BLACK)
	draw_rect(box, A.WHITE, false, 2.5)
	A.text(self, box.get_center(), value, 36 if big else 28, A.WHITE)


func _fuel(p: Vector2) -> void:
	var fm := maxf(0.0, own_f("fuel_min", 0.0))
	var col := A.RED if fm < 5.0 else (A.AMBER if fm < 10.0 else A.GREEN)
	A.text(self, p, "FUEL", 30, A.CYAN)
	var s := "%d:%02d" % [int(floor(fm)), int(floor(fmod(fm, 1.0) * 60.0))]
	if fm < 5.0 and not A.flash(1.0):
		col = col.darkened(0.4)
	A.text(self, p + Vector2(0.0, 62.0), s, 60, col)
	A.text(self, p + Vector2(0.0, 112.0), "MIN REMAINING", 22, A.WHITE)


func _gear(p: Vector2) -> void:
	A.text(self, p, "GEAR", 30, A.CYAN)
	var g := bus.gear_pos
	var target := bus.gear_target
	var offs: Array[Vector2] = [Vector2(0.0, 58.0), Vector2(-80.0, 130.0), Vector2(80.0, 130.0)]
	for i in 3:
		var c := p + offs[i]
		var r := Rect2(c - Vector2(50.0, 26.0), Vector2(100.0, 52.0))
		# Legs lock at slightly different moments.
		var lag := float(i) * 0.04
		var leg := clampf((g - lag) / 0.92, 0.0, 1.0) if target > 0.5 else clampf((g - 0.08 + lag) / 0.92, 0.0, 1.0)
		if leg >= 0.999:
			draw_rect(r, Color(0.02, 0.15, 0.04))
			draw_rect(r, A.GREEN, false, 3.0)
			A.text(self, c, "DN", 32, A.GREEN)
		elif leg <= 0.001:
			draw_rect(r, A.DARK, false, 2.0)
			A.text(self, c, "UP", 26, A.GREY)
		else:
			draw_rect(r, Color(0.25, 0.02, 0.02))
			draw_rect(r, A.RED, false, 3.0)
			A.text(self, c, "TRANS", 24, A.RED)


func _flaps(p: Vector2) -> void:
	A.text(self, p, "FLAPS", 30, A.CYAN)
	var target := int(own_f("flaps", 0.0))
	var labels: Array[String] = ["0", "1", "2", "3"]
	var x0 := p.x - 120.0
	var y := p.y + 60.0
	for k in 4:
		var x := x0 + k * 80.0
		draw_line(Vector2(x, y - 10.0), Vector2(x, y + 10.0), A.WHITE, 3.0)
		A.text(self, Vector2(x, y + 34.0), labels[k], 26, A.CYAN if k == target else A.WHITE)
	draw_line(Vector2(x0, y), Vector2(x0 + 240.0, y), A.GREY, 3.0)
	var xa := x0 + bus.flap_pos * 80.0
	draw_colored_polygon(PackedVector2Array([Vector2(xa, y - 6.0), Vector2(xa - 14.0, y - 30.0), Vector2(xa + 14.0, y - 30.0)]), A.GREEN)
	var moving := absf(bus.flap_pos - target) > 0.01
	A.text(self, p + Vector2(0.0, 128.0), "IN TRANSIT" if moving else "MIN SPD %d" % bus.flap_min(), 24,
		A.CYAN if moving else A.WHITE)


func _memo(p: Vector2) -> void:
	var lines: Array = []
	for w: Variant in bus.warnings:
		var s := String(w)
		match s:
			"PULL UP":
				lines.append(["GPWS PULL UP", A.RED])
			"TERRAIN":
				lines.append(["GPWS TERRAIN", A.AMBER])
			"TOO LOW GEAR":
				lines.append(["L/G GEAR NOT DOWN", A.RED])
			"LOW FUEL":
				lines.append(["FUEL LO LEVEL", A.RED if own_f("fuel_min", 9.0) < 5.0 else A.AMBER])
			_:
				lines.append([s, A.AMBER])
	if String(bus.own.get("status", "flying")) == "flying" and bus.ind_alt < 2500.0 + 512.0:
		var gear := bool(bus.own.get("gear_down", false)) and bus.gear_pos >= 0.999
		var flaps := int(own_f("flaps")) == 3
		var spd := bus.ias <= 155.0
		lines.append(["LDG  GEAR DN" if gear else "LDG  GEAR ........ DN", A.GREEN if gear else A.CYAN])
		lines.append(["     FLAPS 3" if flaps else "     FLAPS ........ 3", A.GREEN if flaps else A.CYAN])
		lines.append(["     SPD ≤ 155" if spd else "     SPD ...... ≤ 155", A.GREEN if spd else A.CYAN])
	for i in mini(lines.size(), 7):
		var l: Array = lines[i]
		A.text(self, p + Vector2(0.0, i * 40.0), String(l[0]), 32, l[1], -1)
