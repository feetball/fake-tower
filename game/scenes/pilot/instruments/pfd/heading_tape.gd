extends PilotInstrumentPart
## Heading tape along the bottom of the PFD: 5° ticks, labels every 10°,
## the current heading index and the selected-heading bug.

const PPD := 6.5


func _init() -> void:
	super()
	clip_contents = true


func _draw() -> void:
	var hdg := bus.hdg
	var cx := size.x * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), A.TAPE)
	var start := int(floor((hdg - 40.0) / 5.0)) * 5
	for d in range(start, int(hdg + 40.0), 5):
		var x := cx + wrapf(d - hdg, -180.0, 180.0) * PPD
		var major := posmod(d, 10) == 0
		draw_line(Vector2(x, 0.0), Vector2(x, 22.0 if major else 12.0), A.WHITE, 3.0)
		if major:
			var lbl := "%02d" % (posmod(d, 360) / 10)
			A.text(self, Vector2(x, 44.0), lbl, 30 if posmod(d, 30) == 0 else 24, A.WHITE)
	var sel := float(bus.sel("hdg"))
	var off := clampf(wrapf(sel - hdg, -180.0, 180.0) * PPD, -cx + 6.0, cx - 6.0)
	var bx := cx + off
	draw_colored_polygon(PackedVector2Array([Vector2(bx - 16.0, 0.0), Vector2(bx + 16.0, 0.0), Vector2(bx + 16.0, 14.0),
		Vector2(bx + 6.0, 14.0), Vector2(bx, 4.0), Vector2(bx - 6.0, 14.0), Vector2(bx - 16.0, 14.0)]), A.MAGENTA)
	draw_line(Vector2(cx, 0.0), Vector2(cx, 30.0), A.YELLOW, 5.0)
