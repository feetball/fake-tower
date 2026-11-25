extends Control
## Static video map: range rings, compass ticks at the scope edge, MSA sectors,
## terrain, extended centreline, runway, hold and fixes. Redrawn only when the
## view or a layer toggle changes.

const Ctx := preload("res://scenes/controller/scope/scope_ctx.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")
const DU := preload("res://scenes/controller/scope/draw_util.gd")

const MSA_RADIUS := 25.0
const RING_MAX := 60

var ctx: Ctx


func _draw() -> void:
	if ctx == null or ctx.world.is_empty():
		return
	var layers: Dictionary = ctx.model.layers
	if layers["rr"]:
		_rings()
	if layers["msa"]:
		_msa()
	if layers["terr"]:
		_terrain()
	if layers["cl"]:
		_centreline()
	_runway()
	if layers["hold"]:
		_hold()
	if layers["fix"]:
		_fixes()
	if layers["rr"]:
		_compass()


func _rings() -> void:
	var o := ctx.xform.to_screen(Vector2.ZERO)
	var k := ctx.xform.k
	var font := ctx.mono(500)
	var fsz := ctx.fs(11.0)
	var w := ctx.px(1.0)
	var step := 5 if k * 5.0 > ctx.px(18.0) else 10
	for r in range(step, RING_MAX + 1, step):
		var col := Look.RING_10 if r % 10 == 0 else Look.RING
		DU.circle_outline(self, o, r * k, col, w)
		var lp := ctx.xform.to_screen(Fmt.point_at(Vector2.ZERO, 225.0, float(r)))
		if ctx.xform.plot.grow(-ctx.px(8.0)).has_point(lp):
			DU.text(self, font, lp, str(r), fsz, Look.RING_LABEL, 0, 0, ctx.px(4.0), Look.BG)


## Bearing ticks where rays from the field meet the edge of the plot.
func _compass() -> void:
	var plot := ctx.xform.plot.grow(-ctx.px(6.0))
	var o := ctx.xform.to_screen(Vector2.ZERO)
	if not plot.has_point(o):
		return
	var font := ctx.mono(500)
	var fsz := ctx.fs(11.0)
	for b in range(0, 360, 5):
		var d := Vector2(sin(deg_to_rad(b)), -cos(deg_to_rad(b)))
		var t := INF
		if d.x > 0.0001:
			t = minf(t, (plot.end.x - o.x) / d.x)
		elif d.x < -0.0001:
			t = minf(t, (plot.position.x - o.x) / d.x)
		if d.y > 0.0001:
			t = minf(t, (plot.end.y - o.y) / d.y)
		elif d.y < -0.0001:
			t = minf(t, (plot.position.y - o.y) / d.y)
		var p := o + d * t
		var major := b % 10 == 0
		var length := ctx.px(12.0 if b % 30 == 0 else (8.0 if major else 4.0))
		draw_line(p, p - d * length, Look.COMPASS, ctx.px(1.0), true)
		if b % 30 == 0:
			DU.text(self, font, p - d * (length + ctx.px(12.0)), "%03d" % b, fsz, Look.COMPASS, 0, 0)


func _msa() -> void:
	var o := ctx.xform.to_screen(Vector2.ZERO)
	var r := MSA_RADIUS * ctx.xform.k
	var w := ctx.px(1.0)
	DU.dashed_circle(self, o, r, Look.MSA, w, ctx.px(7.0), ctx.px(6.0))
	var font := ctx.mono(700)
	var fsz := ctx.fs(12.0)
	for s: Dictionary in ctx.world.get("msa", []):
		var a0 := float(s["from_deg"])
		var a1 := float(s["to_deg"])
		var edge := ctx.xform.to_screen(Fmt.point_at(Vector2.ZERO, a0, MSA_RADIUS))
		DU.dashed_polyline(self, PackedVector2Array([o, edge]), Look.MSA, w, ctx.px(7.0), ctx.px(6.0))
		var span := a1 - a0
		if span <= 0.0:
			span += 360.0
		var lp := ctx.xform.to_screen(Fmt.point_at(Vector2.ZERO, a0 + span * 0.5, MSA_RADIUS - 3.0))
		DU.text(self, font, lp, "MSA %d" % int(s["alt_ft"]), fsz, Look.MSA_LABEL, 0, 0, ctx.px(4.0), Look.BG)


func _terrain() -> void:
	var font_b := ctx.mono(700)
	var font := ctx.mono(500)
	for t: Dictionary in ctx.world.get("terrain", []):
		var c := ctx.xform.to_screen(Vector2(float(t["x"]), float(t["y"])))
		var r := float(t["radius_nm"]) * ctx.xform.k
		if not DU.near_rect(ctx.xform.plot, c, r + 40.0):
			continue
		draw_circle(c, r, Look.TERR_FILL)
		DU.dashed_circle(self, c, r, Look.TERR, ctx.px(1.0), ctx.px(4.0), ctx.px(4.0))
		var tri := ctx.px(5.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -tri), c + Vector2(tri * 0.85, tri * 0.6),
			c + Vector2(-tri * 0.85, tri * 0.6)]), Look.TERR_LABEL)
		var box := DU.text(self, font_b, c + Vector2(0, tri + ctx.px(3.0)), str(int(t["elev_ft"])),
			ctx.fs(13.0), Look.TERR_LABEL, 0, -1, ctx.px(4.0), Look.BG)
		DU.text(self, font, Vector2(c.x, box.end.y), String(t["name"]).to_upper(), ctx.fs(10.5),
			Look.TERR_NAME, 0, -1, ctx.px(4.0), Look.BG)


func _centreline() -> void:
	var ils: Dictionary = ctx.world.get("ils", {})
	var rng := float(ils.get("range_nm", 25.0))
	var back := float(ils.get("course_deg", 270.0)) + 180.0
	var a := ctx.xform.to_screen(Vector2.ZERO)
	var b := ctx.xform.to_screen(Fmt.point_at(Vector2.ZERO, back, rng))
	var w := ctx.px(1.0)
	draw_line(a, b, Look.CL, w, true)
	var perp := Vector2(sin(deg_to_rad(back + 90.0)), -cos(deg_to_rad(back + 90.0)))
	for d in range(1, int(rng) + 1):
		var p := ctx.xform.to_screen(Fmt.point_at(Vector2.ZERO, back, float(d)))
		var half := ctx.px(7.0 if d % 5 == 0 else 3.5)
		draw_line(p - perp * half, p + perp * half, Look.CL, w, true)


func _runway() -> void:
	var rwy: Dictionary = ctx.world.get("runway", {})
	var a := ctx.xform.to_screen(Vector2.ZERO)
	var b := ctx.xform.to_screen(Fmt.point_at(Vector2.ZERO, float(rwy.get("heading_deg", 270.0)),
		float(rwy.get("length_nm", 1.4))))
	draw_line(a, b, Look.RWY, clampf(ctx.xform.k * 0.09, ctx.px(3.0), ctx.px(9.0)), true)
	var label := "%s RWY %s" % [String(ctx.world.get("icao", "")), String(rwy.get("name", ""))]
	DU.text(self, ctx.mono(600), b + Vector2(-ctx.px(4.0), ctx.px(8.0)), label, ctx.fs(12.0), Look.MAP, 1, -1,
		ctx.px(4.0), Look.BG)


func _hold() -> void:
	var pts := Fmt.hold_path(ctx.world)
	if pts.is_empty():
		return
	var scr := PackedVector2Array()
	for p in pts:
		scr.append(ctx.xform.to_screen(p))
	scr.append(scr[0])
	DU.dashed_polyline(self, scr, Look.HOLD, ctx.px(1.0), ctx.px(6.0), ctx.px(4.0))
	var hold: Dictionary = ctx.world["hold"]
	var fix: Variant = Fmt.fix_pos(ctx.world, String(hold["fix"]))
	if fix == null:
		return
	var lp := ctx.xform.to_screen(Fmt.point_at(fix, float(hold["inbound_course_deg"]) + 180.0, 4.6))
	var label := "HOLD %s°%s %d+" % [Fmt.hdg_text(float(hold["inbound_course_deg"])), String(hold["turn"]),
		int(hold["min_alt_ft"])]
	DU.text(self, ctx.mono(500), lp + Vector2(ctx.px(6.0), -ctx.px(4.0)), label, ctx.fs(11.0), Look.HOLD, -1, 1,
		ctx.px(4.0), Look.BG)


func _fixes() -> void:
	var font := ctx.mono(600)
	var fsz := ctx.fs(11.5)
	var faf := String(ctx.world.get("ils", {}).get("faf", {}).get("name", ""))
	var s := ctx.px(5.5)
	for f: Dictionary in ctx.world.get("fixes", []):
		var p := ctx.xform.to_screen(Vector2(float(f["x"]), float(f["y"])))
		if not DU.near_rect(ctx.xform.plot, p, 60.0):
			continue
		var tri := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.9, s * 0.65), p + Vector2(-s * 0.9, s * 0.65)])
		var is_faf := String(f["name"]) == faf
		if is_faf:
			draw_colored_polygon(tri, Look.FIX)
		else:
			tri.append(tri[0])
			draw_polyline(tri, Look.FIX, ctx.px(1.2), true)
		var off := Vector2(ctx.px(8.0), -ctx.px(11.0) if is_faf else 0.0)
		DU.text(self, font, p + off, String(f["name"]), fsz, Look.FIX, -1, 0, ctx.px(4.0), Look.BG)
	# VOR/DME at the threshold
	var o := ctx.xform.to_screen(Vector2.ZERO)
	var h := ctx.px(4.5)
	draw_rect(Rect2(o - Vector2(h, h), Vector2(h, h) * 2.0), Look.FIX, false, ctx.px(1.2))
