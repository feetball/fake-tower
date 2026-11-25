extends Control
## ILS RWY 27 approach chart drawn from World.DATA in the style of a real
## plate, laid out landscape for the EFB: header, briefing strip with MSA
## inset, plan view (terrain with elevations, fixes, final course, FAF, hold,
## missed approach, DME rings), profile view (platform, FAF, 3.00° glidepath,
## DA), minimums box and missed-approach / notes. Logical size 1440 x 840.

const W := 1440.0
const H := 840.0
const INK := Color(0.08, 0.08, 0.09)
const PAPER := Color(0.985, 0.98, 0.955)
const GREY := Color(0.4, 0.4, 0.42)
const TERR := Color(0.86, 0.77, 0.6)
const TERR_HI := Color(0.78, 0.64, 0.42)
const TERR_INK := Color(0.45, 0.32, 0.12)
const ILS_IDENT := "IFTW"
const ILS_FREQ := "109.90"

var qnh := 0
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _f(bold: bool = false) -> Font:
	return Avionics.sans(bold)


func _t(pos: Vector2, s: String, size: int, col: Color = INK, align: int = -1, bold: bool = false) -> void:
	Avionics.text(self, pos, s, size, col, align, _f(bold))


func _draw() -> void:
	_scale = minf(size.x / W, size.y / H)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_scale, _scale))
	draw_rect(Rect2(0, 0, W, H), PAPER)
	var d: Dictionary = World.DATA
	_header(d)
	_briefing(d)
	_plan(d, Rect2(16, 196, 800, 628))
	_profile(d, Rect2(830, 196, 594, 330))
	_minimums(d, Rect2(830, 536, 594, 132))
	_notes(d, Rect2(830, 676, 594, 148))


func _box(r: Rect2, w: float = 1.6) -> void:
	draw_rect(r, INK, false, w)


func _header(d: Dictionary) -> void:
	_t(Vector2(18, 30), String(d["icao"]), 30, INK, -1, true)
	_t(Vector2(112, 30), String(d["name"]).to_upper(), 20)
	_t(Vector2(W - 18, 30), "ILS RWY %s" % d["runway"]["name"], 32, INK, 1, true)
	_t(Vector2(18, 58), "FAKE TOWER APPROACH CHART", 14, GREY)
	_t(Vector2(W - 18, 58), "AMDT 1   25 NOV 26", 14, GREY, 1)
	draw_line(Vector2(16, 72), Vector2(W - 16, 72), INK, 2.5)


func _briefing(d: Dictionary) -> void:
	var ils: Dictionary = d["ils"]
	var field := float(d["field_elev_ft"])
	var cells := [
		["LOC", "%s  %s" % [ILS_IDENT, ILS_FREQ]],
		["Final Apch Crs", "%03d°" % int(ils["course_deg"])],
		["GS  %s" % ils["faf"]["name"], "%d'" % int(ils["platform_alt_ft"])],
		["ILS DA(H)", "%d' (%d')" % [int(ils["da_ft"]), int(ils["da_ft"]) - int(field)]],
		["Apt Elev / TDZE", "%d' / %d'" % [int(field), int(field)]],
	]
	var x0 := 16.0
	var cw := (W - 32.0 - 250.0) / cells.size()
	for i in cells.size():
		var r := Rect2(x0 + i * cw, 80, cw, 56)
		_box(r)
		_t(r.position + Vector2(8, 15), String(cells[i][0]), 14, GREY)
		_t(r.position + Vector2(8, 40), String(cells[i][1]), 22, INK, -1, true)
	var mr := Rect2(W - 16.0 - 246.0, 80, 246, 110)
	_box(mr)
	_msa(d, mr)
	var ma := Rect2(16, 142, W - 32.0 - 254.0, 48)
	_box(ma)
	_t(ma.position + Vector2(8, 15), "MISSED APPROACH:", 13, INK, -1, true)
	_t(ma.position + Vector2(140, 15), String(d["missed_approach"]), 14)
	var q := "  (QNH %d from ATIS)" % qnh if qnh > 0 else ""
	_t(ma.position + Vector2(8, 36), "Alt set: hPa%s.   Trans alt: %d'.   Radar required.   DME from FTW." % [q, int(d["transition_alt_ft"])], 13, GREY)


func _msa(d: Dictionary, r: Rect2) -> void:
	var c := r.position + Vector2(r.size.x - 62, r.size.y * 0.5)
	var rad := 46.0
	_t(r.position + Vector2(8, 18), "MSA", 15, INK, -1, true)
	_t(r.position + Vector2(8, 38), "FTW DME", 13)
	_t(r.position + Vector2(8, 56), "25 NM", 13)
	draw_arc(c, rad, 0, TAU, 64, INK, 1.6, true)
	for s: Dictionary in d["msa"]:
		var a := deg_to_rad(float(s["from_deg"]))
		draw_line(c, c + Vector2(sin(a), -cos(a)) * rad, INK, 1.4)
	for s: Dictionary in d["msa"]:
		var span := fposmod(float(s["to_deg"]) - float(s["from_deg"]), 360.0)
		if span == 0.0:
			span = 360.0
		var a := deg_to_rad(float(s["from_deg"]) + span * 0.5)
		_t(c + Vector2(sin(a), -cos(a)) * rad * 0.55, str(int(s["alt_ft"])), 12, INK, 0, true)
	_t(c + Vector2(0, -rad - 8), "360°", 10, GREY, 0)


## Plan view: map sim nm into the box, north up.
func _plan(d: Dictionary, r: Rect2) -> void:
	_box(r, 2.0)
	var lo := Vector2(-25.0, -27.0)
	var hi := Vector2(33.0, 25.0)
	var k := minf(r.size.x / (hi.x - lo.x), r.size.y / (hi.y - lo.y))
	var origin := r.position + Vector2(-lo.x * k + (r.size.x - (hi.x - lo.x) * k) * 0.5, hi.y * k + (r.size.y - (hi.y - lo.y) * k) * 0.5)
	var P := func(x: float, y: float) -> Vector2: return origin + Vector2(x, -y) * k
	# Terrain: shaded discs with an inner contour and the summit elevation.
	for t: Dictionary in d["terrain"]:
		var c: Vector2 = P.call(float(t["x"]), float(t["y"]))
		var rr := float(t["radius_nm"]) * k
		draw_circle(c, rr * 1.35, TERR)
		draw_circle(c, rr, TERR_HI)
		draw_arc(c, rr * 1.35, 0, TAU, 48, TERR_INK, 1.0, true)
		draw_arc(c, rr, 0, TAU, 48, TERR_INK, 1.2, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4.5, 3), c + Vector2(-4.5, 3)]), TERR_INK)
		_t(c + Vector2(0, 16), "%d'" % int(t["elev_ft"]), 16, TERR_INK, 0, true)
		_t(c + Vector2(0, -16), String(t["name"]), 12, TERR_INK, 0)
	# DME rings from FTW.
	for ring: float in [10.0, 25.0]:
		_dashed_circle(P.call(0.0, 0.0), ring * k, GREY)
		_t(P.call(0.0, 0.0) + Vector2(ring * k * 0.71 + 6, ring * k * 0.71), "D%d" % int(ring), 12, GREY)
	# Hold.
	_hold(d, P, k)
	# Final course and its feather.
	var ils: Dictionary = d["ils"]
	var faf: Dictionary = ils["faf"]
	var ridge := _fix(d, "RIDGE")
	draw_line(P.call(0.0, 0.0), P.call(float(ridge["x"]) + 2.0, 0.0), INK, 3.0)
	_t(P.call(11.0, 0.0) + Vector2(0, -16), "270°", 16, INK, 0, true)
	_arrow(P.call(5.0, 0.0), PI, INK)
	# Missed approach: straight ahead then right turn towards the hold.
	var ma0: Vector2 = P.call(-1.4, 0.0)
	var ma1: Vector2 = P.call(-6.0, 0.0)
	var ma2: Vector2 = P.call(-5.0, 4.0)
	var hp: Vector2 = P.call(float(_fix(d, "HOLDR")["x"]), float(_fix(d, "HOLDR")["y"]))
	_dashed(ma0, ma1, INK)
	_dashed(ma1, ma2, INK)
	_dashed(ma2, hp, INK)
	_arrow(ma2.lerp(hp, 0.5), (hp - ma2).angle(), INK)
	# Runway.
	var a: Vector2 = P.call(0.0, 0.0)
	var b: Vector2 = P.call(-float(d["runway"]["length_nm"]), 0.0)
	draw_line(a, b, INK, 6.0)
	draw_line(a, b, PAPER, 2.0)
	_t(a + Vector2(10, 16), "FTW", 13, INK, -1, true)
	# Fixes.
	for f: Dictionary in d["fixes"]:
		var p: Vector2 = P.call(float(f["x"]), float(f["y"]))
		var is_faf := String(f["name"]) == String(faf["name"])
		if is_faf:
			_maltese(p, 9.0)
			_t(p + Vector2(0, 24), "%s" % f["name"], 15, INK, 0, true)
			_t(p + Vector2(0, 42), "D%.1f" % float(f["x"]), 13, INK, 0)
		else:
			_triangle(p, 8.0)
			_t(p + Vector2(0, -18), String(f["name"]), 14, INK, 0, true)
	# North arrow and scale.
	var na := r.position + Vector2(r.size.x - 34, 46)
	_arrow(na, -PI * 0.5, INK)
	draw_line(na, na + Vector2(0, 26), INK, 2.0)
	_t(na + Vector2(0, -22), "N", 14, INK, 0, true)
	var sb := r.position + Vector2(18, r.size.y - 20)
	draw_line(sb, sb + Vector2(10.0 * k, 0), INK, 2.0)
	for i in 3:
		draw_line(sb + Vector2(5.0 * k * i, -5), sb + Vector2(5.0 * k * i, 5), INK, 2.0)
	_t(sb + Vector2(10.0 * k + 8, 0), "10 NM", 12)


func _hold(d: Dictionary, P: Callable, k: float) -> void:
	var h: Dictionary = d["hold"]
	var fx := _fix(d, String(h["fix"]))
	var p: Vector2 = P.call(float(fx["x"]), float(fx["y"]))
	var inbound := deg_to_rad(float(h["inbound_course_deg"]))
	var dir := Vector2(sin(inbound), -cos(inbound))
	var right := Vector2(-dir.y, dir.x)
	var leg := 4.0 * k
	var wdt := 2.4 * k
	var start := p - dir * leg
	var pts := PackedVector2Array()
	pts.append(start)
	pts.append(p)
	for i in 13:
		var a := PI * i / 12.0
		pts.append(p + right * wdt * 0.5 + (-right * cos(a) + dir * sin(a)) * wdt * 0.5)
	pts.append(start + right * wdt)
	for i in 13:
		var a := PI * i / 12.0
		pts.append(start + right * wdt * 0.5 + (right * cos(a) - dir * sin(a)) * wdt * 0.5)
	draw_polyline(pts, INK, 2.0, true)
	_arrow(start.lerp(p, 0.55), dir.angle(), INK)
	_t(p + right * wdt + Vector2(8, 8), "%03d°" % int(h["inbound_course_deg"]), 13, INK, -1, true)
	_t(p + right * wdt + Vector2(8, 26), "MHA %d" % int(h["min_alt_ft"]), 12, INK)


func _profile(d: Dictionary, r: Rect2) -> void:
	_box(r, 2.0)
	var ils: Dictionary = d["ils"]
	var field := float(d["field_elev_ft"])
	var plat := float(ils["platform_alt_ft"])
	var faf_x := float(ils["faf"]["x"])
	var ridge_x := float(_fix(d, "RIDGE")["x"])
	var da := float(ils["da_ft"])
	var tch := float(ils["tch_ft"])
	# x: threshold on the left margin (approach comes from the right, as in plan view).
	var x0 := r.position.x + 70.0
	var x1 := r.end.x - 26.0
	var kx := (x1 - x0) / (ridge_x + 0.5)
	var y_ground := r.end.y - 46.0
	var ky := (y_ground - (r.position.y + 70.0)) / (plat + 400.0 - field)
	var X := func(nm: float) -> float: return x0 + nm * kx
	var Y := func(ft: float) -> float: return y_ground - (ft - field) * ky
	draw_line(Vector2(r.position.x + 10, y_ground), Vector2(r.end.x - 10, y_ground), INK, 2.0)
	# Runway block.
	draw_rect(Rect2(x0 - 40, y_ground - 5, 40, 5), INK)
	_t(Vector2(x0 - 20, y_ground + 16), "RWY 27", 12, INK, 0, true)
	_t(Vector2(x0 - 20, y_ground + 32), "TDZE %d" % int(field), 11, GREY, 0)
	# Platform segment and glidepath.
	var pf: Vector2 = Vector2(X.call(faf_x), Y.call(plat))
	var pr: Vector2 = Vector2(X.call(ridge_x), Y.call(plat))
	draw_line(pr, pf, INK, 3.0)
	var th: Vector2 = Vector2(X.call(0.0), Y.call(field + tch))
	draw_line(pf, th, INK, 3.0)
	_arrow(pf.lerp(th, 0.5), (th - pf).angle(), INK)
	_arrow(pr.lerp(pf, 0.5), PI, INK)
	_t(pr.lerp(pf, 0.5) + Vector2(0, -18), "%d'" % int(plat), 18, INK, 0, true)
	_maltese(pf, 9.0)
	_t(pf + Vector2(0, -34), "%s" % ils["faf"]["name"], 15, INK, 0, true)
	_t(pf + Vector2(0, -18), "D%.1f" % faf_x, 12, INK, 0)
	_t(pf.lerp(th, 0.45) + Vector2(34, -40), "GS %.2f°" % float(ils["glide_deg"]), 15, INK, -1, true)
	_t(pf.lerp(th, 0.45) + Vector2(34, -22), "TCH %d'" % int(tch), 13, INK, -1)
	# Vertical reference lines and distances.
	for nm: float in [faf_x, ridge_x]:
		_dashed(Vector2(X.call(nm), Y.call(plat)), Vector2(X.call(nm), y_ground), GREY)
		_t(Vector2(X.call(nm), y_ground + 16), "D%.1f" % nm, 12, INK, 0)
	_triangle(pr, 7.0)
	_t(pr + Vector2(0, -18), "RIDGE", 13, INK, 0, true)
	# Decision altitude.
	var yda: float = Y.call(da)
	_dashed(Vector2(x0, yda), Vector2(X.call(2.0), yda), Color(0.6, 0.1, 0.1))
	_t(Vector2(X.call(2.0) + 6, yda), "DA %d'" % int(da), 14, Color(0.6, 0.1, 0.1), -1, true)
	# Missed approach climb arrow from the threshold.
	var m0 := Vector2(x0 - 46, Y.call(field + 300.0))
	_dashed(Vector2(x0 - 6, yda), m0 + Vector2(0, -50), INK)
	_arrow(m0 + Vector2(0, -50), -PI * 0.62, INK)
	_t(Vector2(r.position.x + 10, r.position.y + 18), "PROFILE  (not to scale vertically)", 12, GREY)
	_t(Vector2(r.end.x - 10, r.position.y + 18), "%.1f NM to THR" % faf_x, 12, GREY, 1)


func _minimums(d: Dictionary, r: Rect2) -> void:
	_box(r, 2.0)
	var field := int(d["field_elev_ft"])
	var da := int(d["ils"]["da_ft"])
	var cols := ["CATEGORY", "A", "B", "C", "D"]
	var cw := r.size.x / cols.size()
	draw_line(Vector2(r.position.x, r.position.y + 30), Vector2(r.end.x, r.position.y + 30), INK, 1.2)
	for i in cols.size():
		_t(Vector2(r.position.x + cw * (i + 0.5), r.position.y + 16), String(cols[i]), 14, INK, 0, true)
	_t(Vector2(r.position.x + 10, r.position.y + 56), "S-ILS 27", 14, INK, -1, true)
	_t(Vector2(r.position.x + cw * 3.0, r.position.y + 56), "DA %d' (%d')   RVR 550 m" % [da, da - field], 17, INK, 0, true)
	_t(Vector2(r.position.x + 10, r.position.y + 88), "S-LOC 27", 14, INK, -1, true)
	_t(Vector2(r.position.x + cw * 3.0, r.position.y + 88), "MDA 920' (408')   VIS 1500 m", 15, INK, 0)
	_t(Vector2(r.position.x + 10, r.position.y + 118), "CIRCLING", 14, INK, -1, true)
	_t(Vector2(r.position.x + cw * 3.0, r.position.y + 118), "NOT AUTHORISED (terrain)", 15, INK, 0)


func _notes(d: Dictionary, r: Rect2) -> void:
	_box(r, 2.0)
	var h: Dictionary = d["hold"]
	var lines := [
		"1. Landing: crossing the threshold established on LOC and G/S,",
		"    gear down, flaps FULL (3), IAS 155 kt or less.",
		"2. Hold %s: inbound %03d°, %s turns, minimum %d'." % [h["fix"], int(h["inbound_course_deg"]),
			"right" if String(h["turn"]) == "R" else "left", int(h["min_alt_ft"])],
		"3. Terrain up to 4900' within 15 NM. Obey MSA when not established.",
		"4. Glideslope captures from below only; intercept at the platform.",
	]
	for i in lines.size():
		_t(r.position + Vector2(10, 20 + i * 26), String(lines[i]), 14)


func _fix(d: Dictionary, n: String) -> Dictionary:
	for f: Dictionary in d["fixes"]:
		if String(f["name"]) == n:
			return f
	return {"x": 0.0, "y": 0.0}


func _triangle(p: Vector2, s: float) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.9, s * 0.65), p + Vector2(-s * 0.9, s * 0.65)])
	draw_colored_polygon(pts, PAPER)
	Avionics.polyline_closed(self, pts, INK, 1.8)


func _maltese(p: Vector2, s: float) -> void:
	for i in 4:
		var a := i * PI * 0.5
		var dir := Vector2(sin(a), -cos(a))
		var side := Vector2(cos(a), sin(a))
		draw_colored_polygon(PackedVector2Array([p, p + dir * s - side * s * 0.45, p + dir * s + side * s * 0.45]), INK)


func _arrow(p: Vector2, ang: float, col: Color) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([p + d * 9.0, p - d * 5.0 + n * 6.0, p - d * 5.0 - n * 6.0]), col)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	draw_dashed_line(a, b, col, 1.8, 8.0, true, true)


func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var n := maxi(24, int(r / 6.0))
	for i in n:
		if i % 2 == 0:
			draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 3, col, 1.2, true)
