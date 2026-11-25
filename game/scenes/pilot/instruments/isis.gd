extends PilotInstrumentPart
## Integrated standby instrument: small attitude ball with speed and altitude
## strips, baro setting below. Drawn in a 1000 x 1000 logical square.

const PPD := 12.0


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1000.0, 1000.0), A.BG)
	var c := Vector2(500.0, 470.0)
	# Attitude.
	draw_set_transform(c, -deg_to_rad(bus.bank), Vector2.ONE)
	var hy := bus.pitch * PPD
	draw_rect(Rect2(-330.0, hy - 900.0, 660.0, 900.0), A.SKY)
	draw_rect(Rect2(-330.0, hy, 660.0, 900.0), A.GROUND)
	draw_line(Vector2(-330.0, hy), Vector2(330.0, hy), A.WHITE, 5.0)
	for p: float in [-20.0, -10.0, 10.0, 20.0]:
		var y := (bus.pitch - p) * PPD
		draw_line(Vector2(-60.0, y), Vector2(60.0, y), A.WHITE, 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Mask the corners with the speed / altitude strips.
	draw_rect(Rect2(0.0, 0.0, 230.0, 1000.0), Color(0.14, 0.15, 0.17))
	draw_rect(Rect2(770.0, 0.0, 230.0, 1000.0), Color(0.14, 0.15, 0.17))
	draw_rect(Rect2(0.0, 0.0, 1000.0, 120.0), A.BG)
	draw_rect(Rect2(0.0, 820.0, 1000.0, 180.0), A.BG)
	for s: float in [-1.0, 1.0]:
		draw_line(c + Vector2(s * 150.0, 0.0), c + Vector2(s * 60.0, 0.0), A.YELLOW, 14.0)
	draw_rect(Rect2(c - Vector2(12, 12), Vector2(24, 24)), A.YELLOW)
	_strip(Vector2(115.0, 470.0), bus.ias, 10.0, 4.0, "%d" % int(round(bus.ias)))
	_strip(Vector2(885.0, 470.0), bus.ind_alt, 100.0, 0.5, "%d" % int(round(bus.ind_alt / 10.0) * 10.0))
	var baro := bus.sel("baro")
	A.text(self, Vector2(500.0, 900.0), "STD" if baro == 1013 else "%d HPA" % baro, 70, A.CYAN)
	A.text(self, Vector2(500.0, 60.0), "ISIS", 54, A.GREY)


func _strip(c: Vector2, v: float, step: float, ppu: float, label: String) -> void:
	var lo := int(floor((v - 300.0 / ppu) / step))
	var hi := int(ceil((v + 300.0 / ppu) / step))
	for k in range(lo, hi + 1):
		var y := c.y - (k * step - v) * ppu
		if y > 130.0 and y < 810.0:
			draw_line(Vector2(c.x - 40.0, y), Vector2(c.x + 40.0, y), A.WHITE, 4.0)
	var r := Rect2(c - Vector2(110.0, 50.0), Vector2(220.0, 100.0))
	draw_rect(r, Color.BLACK)
	draw_rect(r, A.WHITE, false, 5.0)
	A.text(self, c, label, 70, A.WHITE)
