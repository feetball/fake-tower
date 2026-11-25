extends PilotInstrumentPart
## Primary flight display (1000 x 1000 logical): FMA row, attitude, speed
## and altitude tapes, vertical speed, heading tape, and the selected-value
## readouts (cyan) around them.

const AdiPart := preload("res://scenes/pilot/instruments/pfd/adi.gd")
const SpeedPart := preload("res://scenes/pilot/instruments/pfd/speed_tape.gd")
const AltPart := preload("res://scenes/pilot/instruments/pfd/alt_tape.gd")
const VsiPart := preload("res://scenes/pilot/instruments/pfd/vsi.gd")
const HdgPart := preload("res://scenes/pilot/instruments/pfd/heading_tape.gd")
const FmaPart := preload("res://scenes/pilot/instruments/pfd/fma.gd")

const MID_Y := 455.0


func setup(b: PilotAvionicsBus) -> void:
	bus = b
	add_part(FmaPart.new().place(0.0, 0.0, 1000.0, 108.0))
	add_part(AdiPart.new().place(222.0, 140.0, 516.0, 650.0))
	add_part(SpeedPart.new().place(40.0, MID_Y - 260.0, 165.0, 520.0))
	add_part(AltPart.new().place(762.0, MID_Y - 260.0, 150.0, 520.0))
	add_part(VsiPart.new().place(920.0, MID_Y - 230.0, 76.0, 460.0))
	add_part(HdgPart.new().place(250.0, 880.0, 460.0, 100.0))


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1000.0, 1000.0), A.BG)
	# Selected speed / altitude above the tapes.
	A.text(self, Vector2(122.0, MID_Y - 292.0), str(bus.sel("spd")), 40, A.CYAN)
	A.text(self, Vector2(837.0, MID_Y - 292.0), str(bus.sel("alt")), 40, A.CYAN)
	# Altimeter setting below the altitude tape.
	var baro := bus.sel("baro")
	if baro == 1013:
		var r := Rect2(785.0, MID_Y + 274.0, 104.0, 48.0)
		draw_rect(r, A.CYAN, false, 3.0)
		A.text(self, r.get_center(), "STD", 36, A.CYAN)
	else:
		A.text(self, Vector2(800.0, MID_Y + 298.0), "QNH", 26, A.WHITE)
		A.text(self, Vector2(880.0, MID_Y + 298.0), str(baro), 36, A.CYAN)
	# Selected heading readout next to the heading tape.
	A.text(self, Vector2(130.0, 905.0), "HDG", 26, A.WHITE)
	A.text(self, Vector2(130.0, 948.0), "%03d" % bus.sel("hdg"), 38, A.CYAN)
	# Current heading digits above the tape index.
	var h := int(round(bus.hdg)) % 360
	if h == 0:
		h = 360
	var hb := Rect2(436.0, 826.0, 88.0, 48.0)
	draw_rect(hb, Color.BLACK)
	draw_rect(hb, A.WHITE, false, 3.0)
	A.text(self, hb.get_center(), "%03d" % h, 36, A.WHITE)
	# Ground speed and ILS identification at the lower left.
	A.text(self, Vector2(40.0, MID_Y + 298.0), "GS", 24, A.WHITE, -1)
	A.text(self, Vector2(80.0, MID_Y + 298.0), str(int(round(own_f("gs")))), 30, A.GREEN, -1)
	if bus.own.get("loc_dev", null) != null:
		A.text(self, Vector2(40.0, 830.0), "IFTW", 28, A.WHITE, -1)
		A.text(self, Vector2(40.0, 866.0), "109.90", 26, A.MAGENTA, -1)
	A.text(self, Vector2(850.0, 905.0), "DME", 26, A.WHITE)
	A.text(self, Vector2(850.0, 948.0), "%.1f" % own_f("dme"), 34, A.WHITE)
