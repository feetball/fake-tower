extends Control
## Radar targets as of the last sweep: history trail, predicted track line,
## symbol, leader line and data block (with cheap automatic de-clutter),
## CA/LA flashing, crashed X, the brief LND tag and the range/bearing line.
## Redrawn on sweeps, on selection/leader/scratchpad/RBL changes, while the
## sweep persistence decays and on flash ticks.

const Ctx := preload("res://scenes/controller/scope/scope_ctx.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")
const DU := preload("res://scenes/controller/scope/draw_util.gd")
const Model := preload("res://scenes/controller/scope/scope_model.gd")

## Auto leader directions in order of preference (bearing of the leader line).
const AUTO_DIRS: Array[int] = [45, 315, 135, 225, 90, 270, 0, 180]
const PERSIST_SEC := 0.45

var ctx: Ctx


func _draw() -> void:
	if ctx == null or ctx.world.is_empty():
		return
	ctx.block_rects.clear()
	var m := ctx.model
	var shown := m.visible_callsigns(ctx.now_ms)
	var age := m.sweep_age_sec(ctx.now_ms)
	var boost := exp(-maxf(age, 0.0) / PERSIST_SEC) if age >= 0.0 else 0.0
	if m.layers["hist"]:
		for cs in shown:
			_history(cs)
	var obstacles: Array[Rect2] = []
	for cs in shown:
		var t: Dictionary = m.targets[cs]
		if String(t["status"]) == "landed":
			continue
		var p := ctx.xform.to_screen(Fmt.target_pos(t))
		obstacles.append(Rect2(p - Vector2(7, 7) * ctx.ui_scale, Vector2(14, 14) * ctx.ui_scale))
	# Alerted and selected targets last so their blocks end up on top.
	var ordered := PackedStringArray()
	var late := PackedStringArray()
	for cs in shown:
		var t: Dictionary = m.targets[cs]
		if cs == m.selected or Fmt.alert_tag(t) != "":
			late.append(cs)
		else:
			ordered.append(cs)
	ordered.append_array(late)
	for cs in ordered:
		var t: Dictionary = m.targets[cs]
		match String(t["status"]):
			"crashed":
				_crashed(t)
			"landed":
				_landed(t)
			_:
				_flying(t, boost, obstacles)
	_rbl()


func _history(cs: String) -> void:
	var t: Dictionary = ctx.model.targets[cs]
	if String(t["status"]) != "flying":
		return
	var hist: PackedVector2Array = ctx.model.history.get(cs, PackedVector2Array())
	var n := hist.size()
	for i in n:
		var p := ctx.xform.to_screen(hist[i])
		var age := n - i # 1 = most recent
		var a := 0.85 - 0.15 * (age - 1)
		draw_circle(p, ctx.px(2.1), Color(Look.HIST, a))


func _flying(t: Dictionary, boost: float, obstacles: Array[Rect2]) -> void:
	var cs := String(t["callsign"])
	var p := ctx.xform.to_screen(Fmt.target_pos(t))
	var selected := cs == ctx.model.selected
	var tag := Fmt.alert_tag(t)
	var alert_col := Look.CA if tag == "CA" else Look.LA
	var flash := ctx.flash_on or ctx.force_flash
	var base := Look.SEL if selected else Look.BLOCK
	var col := alert_col if tag != "" and flash else base
	col = col.lerp(Color.WHITE, 0.3 * boost)

	if ctx.model.layers["ptl"] and float(t["gs"]) > 0.0:
		var q := ctx.xform.to_screen(Fmt.point_at(Fmt.target_pos(t), float(t["track"]), float(t["gs"]) / 60.0))
		draw_line(p, q, Look.PTL, ctx.px(1.0), true)

	var sym := (alert_col if tag != "" else Look.TARGET).lerp(Color.WHITE, 0.45 * boost)
	draw_circle(p, ctx.px(9.0), Color(sym, 0.05 + 0.12 * boost))
	draw_circle(p, ctx.px(4.2), sym)
	if selected:
		DU.circle_outline(self, p, ctx.px(9.5), Look.SEL, ctx.px(1.3))

	var lines := Fmt.block_lines(t, String(ctx.model.scratch.get(cs, "")))
	var font := ctx.mono(700)
	var fsz := ctx.fs(15.0)
	var line_h := font.get_height(fsz) * 0.98
	var bw := 0.0
	for l in lines:
		bw = maxf(bw, DU.text_width(font, l, fsz))
	var bh := line_h * (lines.size() + (1 if tag != "" else 0))
	var dir := _choose_dir(cs, p, Vector2(bw, bh), line_h, obstacles)
	var leader_len := ctx.px(30.0)
	var d := Vector2(sin(deg_to_rad(dir)), -cos(deg_to_rad(dir)))
	var le := p + d * leader_len
	var rect := _block_rect(le, d, Vector2(bw, bh), line_h)
	obstacles.append(rect)
	ctx.block_rects[cs] = rect
	draw_line(p + d * ctx.px(6.5), le, col, ctx.px(1.2), true)

	if selected or tag != "":
		draw_rect(rect.grow(ctx.px(3.0)), Look.BLOCK_BACK)
	if selected:
		draw_rect(rect.grow(ctx.px(4.0)), Color(Look.SEL, 0.55), false, ctx.px(1.0))
	var y := rect.position.y
	if tag != "":
		var tag_col := alert_col if flash else alert_col.darkened(0.45)
		DU.text(self, font, Vector2(rect.position.x, y), tag, fsz, tag_col, -1, -1, ctx.px(4.0), Look.BG)
		y += line_h
	for i in lines.size():
		var lc := col
		if i == 2:
			lc = Color(col, 0.8)
		DU.text(self, font, Vector2(rect.position.x, y), lines[i], fsz, lc, -1, -1, ctx.px(4.0), Look.BG)
		y += line_h


func _choose_dir(cs: String, p: Vector2, size: Vector2, line_h: float, obstacles: Array[Rect2]) -> int:
	if ctx.model.leader_dir.has(cs):
		return int(ctx.model.leader_dir[cs])
	var leader_len := ctx.px(30.0)
	var plot := ctx.xform.plot
	var best := AUTO_DIRS[0]
	var best_cost := INF
	for dir in AUTO_DIRS:
		var d := Vector2(sin(deg_to_rad(dir)), -cos(deg_to_rad(dir)))
		var r := _block_rect(p + d * leader_len, d, size, line_h).grow(ctx.px(3.0))
		var cost := 0.0
		for o in obstacles:
			if o.intersects(r):
				cost += o.intersection(r).get_area()
		if not plot.encloses(r):
			cost += r.get_area() * 0.5
		if cost < best_cost - 0.5:
			best_cost = cost
			best = dir
		if cost <= 0.0:
			break
	return best


## Block rect for a leader ending at `le` pointing along `d` (screen space).
func _block_rect(le: Vector2, d: Vector2, size: Vector2, line_h: float) -> Rect2:
	var gap := ctx.px(3.0)
	var bx := le.x - size.x * 0.5
	if d.x > 0.3:
		bx = le.x + gap
	elif d.x < -0.3:
		bx = le.x - gap - size.x
	var by := le.y - size.y * 0.5
	if absf(d.x) <= 0.3:
		by = le.y - gap - size.y if d.y < 0.0 else le.y + gap
	elif d.y < -0.3:
		by = le.y - size.y + line_h * 0.5
	elif d.y > 0.3:
		by = le.y - line_h * 0.5
	return Rect2(bx, by, size.x, size.y)


func _crashed(t: Dictionary) -> void:
	var p := ctx.xform.to_screen(Fmt.target_pos(t))
	var s := ctx.px(6.5)
	var w := ctx.px(2.4)
	draw_line(p + Vector2(-s, -s), p + Vector2(s, s), Look.CRASH, w, true)
	draw_line(p + Vector2(s, -s), p + Vector2(-s, s), Look.CRASH, w, true)
	var font := ctx.mono(700)
	var fsz := ctx.fs(14.0)
	var r := DU.text(self, font, p + Vector2(s + ctx.px(6.0), -ctx.px(2.0)), String(t["callsign"]), fsz,
		Look.CRASH, -1, 1, ctx.px(4.0), Look.BG)
	DU.text(self, ctx.mono(500), Vector2(r.position.x, r.end.y), "CRASH  %s" % Fmt.alt_hundreds(float(t["alt"])),
		ctx.fs(12.0), Look.CRASH.darkened(0.25), -1, -1, ctx.px(4.0), Look.BG)
	ctx.block_rects[String(t["callsign"])] = Rect2(r.position, Vector2(r.size.x, r.size.y * 2.0))


func _landed(t: Dictionary) -> void:
	var cs := String(t["callsign"])
	var age := ctx.model.landed_age(cs, ctx.now_ms)
	var fade := clampf((Model.LANDED_SHOW_MS / 1000.0 - age) / 5.0, 0.0, 1.0)
	var col := Color(Look.LANDED, 0.85 * fade)
	var p := ctx.xform.to_screen(Fmt.target_pos(t))
	var h := ctx.px(3.0)
	draw_rect(Rect2(p - Vector2(h, h), Vector2(h, h) * 2.0), col)
	DU.text(self, ctx.mono(600), p + Vector2(ctx.px(7.0), ctx.px(4.0)), "%s LND" % cs, ctx.fs(12.0), col, -1, -1,
		ctx.px(3.0), Look.BG)


func _rbl() -> void:
	if not ctx.rbl_active:
		return
	var a := ctx.xform.to_screen(ctx.rbl_a)
	var b := ctx.xform.to_screen(ctx.rbl_b)
	draw_line(a, b, Look.RBL, ctx.px(1.3), true)
	draw_circle(a, ctx.px(3.0), Look.RBL)
	draw_circle(b, ctx.px(3.0), Look.RBL)
	var dist := ctx.rbl_a.distance_to(ctx.rbl_b)
	if dist < 0.05:
		return
	var label := "BRG %s° / %.1f NM" % [Fmt.hdg_text(Fmt.bearing_to(ctx.rbl_a, ctx.rbl_b)), dist]
	var font := ctx.mono(700)
	var fsz := ctx.fs(14.0)
	var mid := (a + b) * 0.5 + Vector2(ctx.px(12.0), -ctx.px(12.0))
	var w := DU.text_width(font, label, fsz)
	var h := font.get_height(fsz)
	draw_rect(Rect2(mid.x - ctx.px(5.0), mid.y - h * 0.5 - ctx.px(3.0), w + ctx.px(10.0), h + ctx.px(6.0)), Look.BLOCK_BACK)
	DU.text(self, font, mid, label, fsz, Look.RBL, -1, 0)
