extends PilotInstrumentPart
## Flight mode annunciator row: speed | lateral | vertical | approach | AP.
## Engaged modes green, armed modes white below them, a white box around a
## mode for 10 s after it changes.

const COLS := 5


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var cw := size.x / COLS
	for i in range(1, COLS):
		draw_line(Vector2(i * cw, 8.0), Vector2(i * cw, size.y - 8.0), A.DARK, 3.0)
	var own := bus.own
	var armed := bool(own.get("app_armed", false))
	var mode := String(own.get("ap_mode", "HDG"))
	var gs := bool(own.get("gs_captured", false))
	var top: Array[String] = [bus.fma[0], bus.fma[1], bus.fma[2], "", "AP1"]
	var bottom: Array[String] = ["", "", "", "", "A/THR"]
	if armed and mode == "HDG":
		bottom[1] = "LOC"
	if armed and not gs:
		bottom[2] = "G/S"
	if armed:
		top[3] = "CAT 1"
		bottom[3] = "DA 712"
	var y1 := size.y * 0.3
	var y2 := size.y * 0.74
	for i in COLS:
		var x := (i + 0.5) * cw
		if top[i] != "":
			var col := A.WHITE if i >= 3 else A.GREEN
			A.text(self, Vector2(x, y1), top[i], 34, col)
			if i < 3 and bus.now - bus.fma_changed[i] < 10.0:
				var tw := A.text_width(top[i], 34) + 18.0
				draw_rect(Rect2(x - tw * 0.5, y1 - 24.0, tw, 48.0), A.WHITE, false, 3.0)
		if bottom[i] != "":
			var colb := A.CYAN if bottom[i].begins_with("DA") else A.WHITE
			A.text(self, Vector2(x, y2), bottom[i], 30, colb)
