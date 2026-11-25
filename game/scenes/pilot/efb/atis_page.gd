extends Control
## EFB ATIS page: the broadcast text from Session.atis, set large, with the
## key values (information letter, QNH, wind, visibility, ceiling) pulled out.
## Logical size 1440 x 840, scaled to fit.

const W := 1440.0
const H := 840.0
const BG := Color(0.07, 0.075, 0.085)
const TXT := Color(0.86, 0.9, 0.93)
const DIM := Color(0.5, 0.55, 0.6)
const ACC := Color(0.35, 0.9, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var k := minf(size.x / W, size.y / H)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	draw_rect(Rect2(0, 0, W, H), BG)
	var a: Dictionary = Session.atis
	var sans := Avionics.sans(true)
	var mono := Avionics.font(true)
	if a.is_empty():
		Avionics.text(self, Vector2(W * 0.5, H * 0.5), "NO ATIS RECEIVED", 40, DIM, 0, sans)
		return
	Avionics.text(self, Vector2(40, 50), "%s ATIS" % World.DATA["icao"], 26, DIM, -1, sans)
	Avionics.text(self, Vector2(40, 108), "INFORMATION %s" % String(a.get("letter", "?")), 54, TXT, -1, sans)
	# Key values.
	var cells := [
		["QNH", "%d hPa" % int(a.get("qnh", 0))],
		["RWY", String(a.get("runway", "27"))],
		["WIND", "%03d° / %d kt" % [int(a.get("wind_dir", 0)), int(a.get("wind_kt", 0))]],
		["VIS", "%d m" % int(a.get("visibility_m", 0))],
		["CEILING", "OVC %d ft" % int(a.get("ceiling_ft", 0))],
	]
	var cw := (W - 80.0) / cells.size()
	for i in cells.size():
		var x := 40.0 + i * cw
		draw_rect(Rect2(x, 150, cw - 14, 110), Color(0.1, 0.11, 0.13))
		Avionics.text(self, Vector2(x + 18, 180), String(cells[i][0]), 22, DIM, -1, sans)
		Avionics.text(self, Vector2(x + 18, 228), String(cells[i][1]), 40 if i == 0 else 34, ACC if i == 0 else TXT, -1, mono)
	# Full text, wrapped.
	var text := String(a.get("text", ""))
	var size_px := 30
	var y := 320.0
	var line := ""
	var maxw := W - 80.0
	for word in text.split(" ", false):
		var t := word if line == "" else line + " " + word
		if mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > maxw:
			Avionics.text(self, Vector2(40, y), line, size_px, TXT, -1, mono)
			y += size_px * 1.55
			line = word
		else:
			line = t
	if line != "":
		Avionics.text(self, Vector2(40, y), line, size_px, TXT, -1, mono)
	Avionics.text(self, Vector2(40, H - 30), "Set the QNH on the baro knob ( [ and ] keys, or scroll the knob ) before descending below transition.", 20, DIM, -1, sans)
